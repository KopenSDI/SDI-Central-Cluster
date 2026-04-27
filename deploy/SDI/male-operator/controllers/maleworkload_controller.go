/*
Copyright 2024 KETI.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package controllers

import (
	"context"
	"fmt"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	malev1alpha1 "github.com/keti-lab/male-operator/api/v1alpha1"
	"github.com/keti-lab/male-operator/internal/override"
	"github.com/keti-lab/male-operator/internal/policy"
)

// MaleWorkloadReconciler reconciles a MaleWorkload object
type MaleWorkloadReconciler struct {
	client.Client
	Scheme          *runtime.Scheme
	ConfigMapReader *override.ConfigMapReader
	WebhookCache    *override.WebhookOverrideCache
}

//+kubebuilder:rbac:groups=male.keti.dev,resources=maleworkloads,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups=male.keti.dev,resources=maleworkloads/status,verbs=get;update;patch
//+kubebuilder:rbac:groups=male.keti.dev,resources=maleworkloads/finalizers,verbs=update
//+kubebuilder:rbac:groups=apps,resources=deployments;statefulsets,verbs=get;list;watch;update;patch
//+kubebuilder:rbac:groups=batch,resources=jobs,verbs=get;list;watch;update;patch
//+kubebuilder:rbac:groups="",resources=pods,verbs=get;list;watch;update;patch
//+kubebuilder:rbac:groups="",resources=configmaps,verbs=get;list;watch

// Reconcile is part of the main kubernetes reconciliation loop
func (r *MaleWorkloadReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx)

	workload := &malev1alpha1.MaleWorkload{}
	if err := r.Get(ctx, req.NamespacedName, workload); err != nil {
		if errors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	// Get the active MalePolicy (cluster-scoped, assume single policy for now)
	policyList := &malev1alpha1.MalePolicyList{}
	if err := r.List(ctx, policyList); err != nil {
		logger.Error(err, "Failed to list MalePolicies")
		return ctrl.Result{}, err
	}

	if len(policyList.Items) == 0 {
		logger.Info("No MalePolicy found, skipping reconciliation")
		r.updateCondition(ctx, workload, "Pending", "NoPolicy", "No MalePolicy found", metav1.ConditionFalse)
		return ctrl.Result{RequeueAfter: time.Minute}, nil
	}

	// Use the first policy (in production, you might want to select by label or name)
	activePolicy := &policyList.Items[0]

	// Get effective importance values (apply override if enabled)
	effectiveImportance := workload.Spec.Importance

	if workload.Spec.AllowPolicyOverride && activePolicy.Spec.Override.Enabled {
		// Try webhook cache first
		if webhookOverride := r.WebhookCache.GetOverride(workload.Namespace, workload.Name); webhookOverride != nil {
			effectiveImportance = override.ApplyOverride(effectiveImportance, webhookOverride)
		} else if activePolicy.Spec.Override.Source.Type == "ConfigMap" {
			// Try ConfigMap
			configMapOverride, err := r.ConfigMapReader.GetOverride(ctx, activePolicy.Spec.Override.Source,
				workload.Namespace, workload.Name)
			if err != nil {
				logger.Error(err, "Failed to read ConfigMap override")
			} else if configMapOverride != nil {
				effectiveImportance = override.ApplyOverride(effectiveImportance, configMapOverride)
			}
		}
	}

	// Clamp values to bounds
	effectiveImportance = policy.ClampValues(effectiveImportance, activePolicy.Spec.Bounds)

	// Calculate mixed score
	mixedScore, err := policy.CalculateMixedScore(activePolicy.Spec.Weights, effectiveImportance)
	if err != nil {
		logger.Error(err, "Failed to calculate mixed score")
		r.updateCondition(ctx, workload, "Error", "CalculationFailed", err.Error(), metav1.ConditionFalse)
		return ctrl.Result{}, err
	}

	// Find priority bucket
	bucket, err := policy.FindPriorityBucket(mixedScore, activePolicy.Spec.PriorityBuckets)
	if err != nil {
		logger.Error(err, "Failed to find priority bucket")
		r.updateCondition(ctx, workload, "Error", "BucketNotFound", err.Error(), metav1.ConditionFalse)
		return ctrl.Result{}, err
	}

	// ============================================================
	// MC Criticality Determination (MALE Paper-based)
	// ============================================================
	// Determine criticality based on ALE importance values
	// This implements the MALE paper's mission-driven evaluation method
	var userCriticality string
	if workload.Spec.MCSpec != nil {
		userCriticality = workload.Spec.MCSpec.Criticality
	}

	criticalityResult := policy.DetermineCriticality(
		effectiveImportance,
		userCriticality,
		workload.Spec.AllowPolicyOverride,
	)

	// Build effective MC spec
	effectiveMCSpec := r.buildEffectiveMCSpec(workload, criticalityResult)

	if criticalityResult.WasOverridden {
		logger.Info("MC Criticality overridden by MALE evaluation",
			"original", criticalityResult.OriginalCriticality,
			"effective", criticalityResult.Criticality,
			"missionType", criticalityResult.MissionType,
			"reason", criticalityResult.Reason)
	}

	// Update target workload with labels/annotations
	if err := r.updateTargetWorkload(ctx, workload, bucket.Name); err != nil {
		logger.Error(err, "Failed to update target workload")
		r.updateCondition(ctx, workload, "Error", "UpdateFailed", err.Error(), metav1.ConditionFalse)
		return ctrl.Result{RequeueAfter: time.Minute}, err
	}

	// Update status
	now := metav1.Now()
	workload.Status.EffectiveImportance = &effectiveImportance
	workload.Status.EffectiveMCSpec = effectiveMCSpec
	workload.Status.MixedScore = &mixedScore
	workload.Status.PriorityClassName = bucket.Name
	workload.Status.LastEvaluationTime = &now

	if err := r.Status().Update(ctx, workload); err != nil {
		logger.Error(err, "Failed to update status")
		return ctrl.Result{}, err
	}

	r.updateCondition(ctx, workload, "Ready", "Evaluated",
		fmt.Sprintf("Score: %.3f, PriorityClass: %s, Criticality: %s (%s)",
			mixedScore, bucket.Name, criticalityResult.Criticality, criticalityResult.MissionType),
		metav1.ConditionTrue)

	return ctrl.Result{}, nil
}

// updateTargetWorkload updates the target workload with labels and annotations
func (r *MaleWorkloadReconciler) updateTargetWorkload(ctx context.Context, workload *malev1alpha1.MaleWorkload, priorityClassName string) error {
	ref := workload.Spec.TargetRef
	key := types.NamespacedName{
		Namespace: workload.Namespace,
		Name:      ref.Name,
	}

	// Add workload label for webhook identification
	workloadLabel := fmt.Sprintf("%s.%s", workload.Namespace, workload.Name)

	switch ref.Kind {
	case "Deployment":
		deploy := &appsv1.Deployment{}
		if err := r.Get(ctx, key, deploy); err != nil {
			return fmt.Errorf("failed to get Deployment: %w", err)
		}

		// Update pod template labels
		if deploy.Spec.Template.Labels == nil {
			deploy.Spec.Template.Labels = make(map[string]string)
		}
		deploy.Spec.Template.Labels["male.keti.dev/workload"] = workloadLabel
		if workload.Spec.Mission != "" {
			deploy.Spec.Template.Labels["male.keti.dev/mission"] = workload.Spec.Mission
		}

		// Add scheduling hints
		for k, v := range workload.Spec.SchedulingHints.AddLabels {
			deploy.Spec.Template.Labels[k] = v
		}

		if deploy.Spec.Template.Annotations == nil {
			deploy.Spec.Template.Annotations = make(map[string]string)
		}
		deploy.Spec.Template.Annotations["male.keti.dev/priority-class"] = priorityClassName
		deploy.Spec.Template.Annotations["male.keti.dev/score-source"] = "operator"

		for k, v := range workload.Spec.SchedulingHints.AddAnnotations {
			deploy.Spec.Template.Annotations[k] = v
		}

		return r.Update(ctx, deploy)

	case "StatefulSet":
		sts := &appsv1.StatefulSet{}
		if err := r.Get(ctx, key, sts); err != nil {
			return fmt.Errorf("failed to get StatefulSet: %w", err)
		}

		if sts.Spec.Template.Labels == nil {
			sts.Spec.Template.Labels = make(map[string]string)
		}
		sts.Spec.Template.Labels["male.keti.dev/workload"] = workloadLabel
		if workload.Spec.Mission != "" {
			sts.Spec.Template.Labels["male.keti.dev/mission"] = workload.Spec.Mission
		}

		for k, v := range workload.Spec.SchedulingHints.AddLabels {
			sts.Spec.Template.Labels[k] = v
		}

		if sts.Spec.Template.Annotations == nil {
			sts.Spec.Template.Annotations = make(map[string]string)
		}
		sts.Spec.Template.Annotations["male.keti.dev/priority-class"] = priorityClassName
		sts.Spec.Template.Annotations["male.keti.dev/score-source"] = "operator"

		for k, v := range workload.Spec.SchedulingHints.AddAnnotations {
			sts.Spec.Template.Annotations[k] = v
		}

		return r.Update(ctx, sts)

	case "Job":
		job := &batchv1.Job{}
		if err := r.Get(ctx, key, job); err != nil {
			return fmt.Errorf("failed to get Job: %w", err)
		}

		if job.Spec.Template.Labels == nil {
			job.Spec.Template.Labels = make(map[string]string)
		}
		job.Spec.Template.Labels["male.keti.dev/workload"] = workloadLabel
		if workload.Spec.Mission != "" {
			job.Spec.Template.Labels["male.keti.dev/mission"] = workload.Spec.Mission
		}

		for k, v := range workload.Spec.SchedulingHints.AddLabels {
			job.Spec.Template.Labels[k] = v
		}

		if job.Spec.Template.Annotations == nil {
			job.Spec.Template.Annotations = make(map[string]string)
		}
		job.Spec.Template.Annotations["male.keti.dev/priority-class"] = priorityClassName
		job.Spec.Template.Annotations["male.keti.dev/score-source"] = "operator"

		for k, v := range workload.Spec.SchedulingHints.AddAnnotations {
			job.Spec.Template.Annotations[k] = v
		}

		return r.Update(ctx, job)

	case "Pod":
		pod := &corev1.Pod{}
		if err := r.Get(ctx, key, pod); err != nil {
			return fmt.Errorf("failed to get Pod: %w", err)
		}

		if pod.Labels == nil {
			pod.Labels = make(map[string]string)
		}
		pod.Labels["male.keti.dev/workload"] = workloadLabel
		if workload.Spec.Mission != "" {
			pod.Labels["male.keti.dev/mission"] = workload.Spec.Mission
		}

		for k, v := range workload.Spec.SchedulingHints.AddLabels {
			pod.Labels[k] = v
		}

		if pod.Annotations == nil {
			pod.Annotations = make(map[string]string)
		}
		pod.Annotations["male.keti.dev/priority-class"] = priorityClassName
		pod.Annotations["male.keti.dev/score-source"] = "operator"

		for k, v := range workload.Spec.SchedulingHints.AddAnnotations {
			pod.Annotations[k] = v
		}

		return r.Update(ctx, pod)

	default:
		return fmt.Errorf("unsupported workload kind: %s", ref.Kind)
	}
}

func (r *MaleWorkloadReconciler) updateCondition(ctx context.Context, workload *malev1alpha1.MaleWorkload,
	conditionType, reason, message string, status metav1.ConditionStatus) {
	condition := metav1.Condition{
		Type:               conditionType,
		Status:             status,
		Reason:             reason,
		Message:            message,
		LastTransitionTime: metav1.Now(),
	}

	existing := false
	for i := range workload.Status.Conditions {
		if workload.Status.Conditions[i].Type == conditionType {
			workload.Status.Conditions[i] = condition
			existing = true
			break
		}
	}
	if !existing {
		workload.Status.Conditions = append(workload.Status.Conditions, condition)
	}

	if err := r.Status().Update(ctx, workload); err != nil {
		logger := log.FromContext(ctx)
		logger.Error(err, "Failed to update condition", "type", conditionType)
	}
}

// buildEffectiveMCSpec constructs the effective MC spec from user input and criticality result
func (r *MaleWorkloadReconciler) buildEffectiveMCSpec(
	workload *malev1alpha1.MaleWorkload,
	criticalityResult policy.CriticalityResult,
) *malev1alpha1.EffectiveMCSpec {
	effectiveMCSpec := &malev1alpha1.EffectiveMCSpec{
		Criticality: string(criticalityResult.Criticality),
		MissionType: string(criticalityResult.MissionType),
	}

	// Copy user-specified MC parameters if available
	if workload.Spec.MCSpec != nil {
		mcSpec := workload.Spec.MCSpec

		// Use user-specified values or defaults
		if mcSpec.RTPeriod > 0 {
			effectiveMCSpec.RTPeriod = mcSpec.RTPeriod
		} else {
			effectiveMCSpec.RTPeriod = 100 // Default: 100ms
		}

		if mcSpec.RTWcet > 0 {
			effectiveMCSpec.RTWcet = mcSpec.RTWcet
		} else {
			effectiveMCSpec.RTWcet = 30 // Default: 30ms
		}

		if mcSpec.RTDeadline > 0 {
			effectiveMCSpec.RTDeadline = mcSpec.RTDeadline
		} else {
			effectiveMCSpec.RTDeadline = effectiveMCSpec.RTPeriod // Default: same as period
		}

		effectiveMCSpec.MissionId = mcSpec.MissionId
	} else {
		// Use defaults
		effectiveMCSpec.RTPeriod = 100
		effectiveMCSpec.RTWcet = 30
		effectiveMCSpec.RTDeadline = 100
	}

	// Set override reason if criticality was changed
	if criticalityResult.WasOverridden {
		effectiveMCSpec.OverrideReason = criticalityResult.Reason
	}

	return effectiveMCSpec
}

// SetupWithManager sets up the controller with the Manager.
func (r *MaleWorkloadReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&malev1alpha1.MaleWorkload{}).
		Owns(&appsv1.Deployment{}).
		Owns(&appsv1.StatefulSet{}).
		Owns(&batchv1.Job{}).
		Complete(r)
}
