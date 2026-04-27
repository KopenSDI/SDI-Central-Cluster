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

package webhook

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"

	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/webhook/admission"

	malev1alpha1 "github.com/keti-lab/male-operator/api/v1alpha1"
	"github.com/keti-lab/male-operator/internal/policy"
)

// PodMutator mutates Pods to inject priorityClassName
type PodMutator struct {
	Client  client.Client
	decoder admission.Decoder
}

// NewPodMutator creates a new PodMutator
func NewPodMutator(client client.Client) *PodMutator {
	return &PodMutator{Client: client}
}

// InjectDecoder injects the decoder
func (m *PodMutator) InjectDecoder(d admission.Decoder) error {
	m.decoder = d
	return nil
}

// Handle handles Pod admission requests
func (m *PodMutator) Handle(ctx context.Context, req admission.Request) admission.Response {
	pod := &corev1.Pod{}
	if err := m.decoder.Decode(req, pod); err != nil {
		return admission.Errored(400, err)
	}

	// Check if this Pod should be mutated
	workloadLabel, shouldMutate := m.shouldMutatePod(pod)
	if !shouldMutate {
		return admission.Allowed("Pod does not require MALE mutation")
	}

	// Get the active MalePolicy
	policyList := &malev1alpha1.MalePolicyList{}
	if err := m.Client.List(ctx, policyList); err != nil {
		return admission.Errored(500, fmt.Errorf("failed to list MalePolicies: %w", err))
	}

	if len(policyList.Items) == 0 {
		return admission.Allowed("No MalePolicy found")
	}

	activePolicy := &policyList.Items[0]

	// Try to get importance from Pod labels/annotations first (highest priority)
	var effectiveImportance malev1alpha1.ImportanceValues
	podImportance, hasPodImportance := m.getImportanceFromPod(pod)

	if hasPodImportance {
		// Use Pod's direct importance values
		effectiveImportance = *podImportance
	} else {
		// Fallback to MaleWorkload
		workload, err := m.getMaleWorkload(ctx, pod.Namespace, workloadLabel)
		if err != nil {
			return admission.Errored(500, fmt.Errorf("failed to get MaleWorkload: %w", err))
		}

		if workload == nil {
			return admission.Allowed("MaleWorkload not found and no direct importance values in Pod")
		}

		effectiveImportance = workload.Spec.Importance
		if workload.Spec.AllowPolicyOverride && activePolicy.Spec.Override.Enabled {
			// Override logic would go here (simplified for webhook)
			effectiveImportance = policy.ClampValues(effectiveImportance, activePolicy.Spec.Bounds)
		}
	}

	// Always clamp values to bounds
	effectiveImportance = policy.ClampValues(effectiveImportance, activePolicy.Spec.Bounds)

	// Calculate score and find bucket
	mixedScore, err := policy.CalculateMixedScore(activePolicy.Spec.Weights, effectiveImportance)
	if err != nil {
		return admission.Errored(500, fmt.Errorf("failed to calculate score: %w", err))
	}

	bucket, err := policy.FindPriorityBucket(mixedScore, activePolicy.Spec.PriorityBuckets)
	if err != nil {
		return admission.Errored(500, fmt.Errorf("failed to find bucket: %w", err))
	}

	// Mutate Pod
	podCopy := pod.DeepCopy()

	// Inject priorityClassName
	// Only override if not set, or if force label is present
	forceLabel := podCopy.Labels["male.keti.dev/force"]
	if podCopy.Spec.PriorityClassName == "" || forceLabel == "true" {
		podCopy.Spec.PriorityClassName = bucket.Name
	}

	// Add annotations
	if podCopy.Annotations == nil {
		podCopy.Annotations = make(map[string]string)
	}
	podCopy.Annotations["male.keti.dev/priority-class"] = bucket.Name
	podCopy.Annotations["male.keti.dev/mixed-score"] = fmt.Sprintf("%.3f", mixedScore)

	// Marshal podCopy to JSON
	podCopyJSON, err := json.Marshal(podCopy)
	if err != nil {
		return admission.Errored(500, fmt.Errorf("failed to marshal pod: %w", err))
	}

	return admission.PatchResponseFromRaw(req.Object.Raw, podCopyJSON)
}

// shouldMutatePod checks if a Pod should be mutated
func (m *PodMutator) shouldMutatePod(pod *corev1.Pod) (string, bool) {
	// Check if Pod has direct importance values (highest priority)
	if _, hasImportance := m.getImportanceFromPod(pod); hasImportance {
		return "", true
	}

	// Check annotation
	if enable, ok := pod.Annotations["male.keti.dev/enable"]; ok && enable == "true" {
		return "", true
	}

	// Check workload label
	if workloadLabel, ok := pod.Labels["male.keti.dev/workload"]; ok {
		return workloadLabel, true
	}

	// Check owner references (Deployment -> ReplicaSet -> Pod)
	if pod.OwnerReferences != nil {
		for _, owner := range pod.OwnerReferences {
			if owner.Kind == "ReplicaSet" {
				// Try to find the Deployment and check its labels
				// This is a simplified check - in production, you'd fetch the ReplicaSet/Deployment
				return "", true
			}
		}
	}

	return "", false
}

// getImportanceFromPod extracts importance values from Pod labels or annotations
// Supports both labels and annotations with keys:
//   - male.keti.dev/accuracy
//   - male.keti.dev/latency
//   - male.keti.dev/energy
//
// Returns the importance values and true if all three values are found, false otherwise
func (m *PodMutator) getImportanceFromPod(pod *corev1.Pod) (*malev1alpha1.ImportanceValues, bool) {
	var accuracy, latency, energy float64
	var hasAccuracy, hasLatency, hasEnergy bool
	var err error

	// Try labels first
	if val, ok := pod.Labels["male.keti.dev/accuracy"]; ok {
		accuracy, err = strconv.ParseFloat(val, 64)
		if err == nil {
			hasAccuracy = true
		}
	}
	if val, ok := pod.Labels["male.keti.dev/latency"]; ok {
		latency, err = strconv.ParseFloat(val, 64)
		if err == nil {
			hasLatency = true
		}
	}
	if val, ok := pod.Labels["male.keti.dev/energy"]; ok {
		energy, err = strconv.ParseFloat(val, 64)
		if err == nil {
			hasEnergy = true
		}
	}

	// If not found in labels, try annotations
	if !hasAccuracy {
		if val, ok := pod.Annotations["male.keti.dev/accuracy"]; ok {
			accuracy, err = strconv.ParseFloat(val, 64)
			if err == nil {
				hasAccuracy = true
			}
		}
	}
	if !hasLatency {
		if val, ok := pod.Annotations["male.keti.dev/latency"]; ok {
			latency, err = strconv.ParseFloat(val, 64)
			if err == nil {
				hasLatency = true
			}
		}
	}
	if !hasEnergy {
		if val, ok := pod.Annotations["male.keti.dev/energy"]; ok {
			energy, err = strconv.ParseFloat(val, 64)
			if err == nil {
				hasEnergy = true
			}
		}
	}

	// All three values must be present
	if hasAccuracy && hasLatency && hasEnergy {
		return &malev1alpha1.ImportanceValues{
			Accuracy: accuracy,
			Latency:  latency,
			Energy:   energy,
		}, true
	}

	return nil, false
}

// getMaleWorkload retrieves a MaleWorkload by namespace and label
func (m *PodMutator) getMaleWorkload(ctx context.Context, namespace, workloadLabel string) (*malev1alpha1.MaleWorkload, error) {
	if workloadLabel == "" {
		// Try to find by namespace and pod name pattern
		workloadList := &malev1alpha1.MaleWorkloadList{}
		if err := m.Client.List(ctx, workloadList, client.InNamespace(namespace)); err != nil {
			return nil, err
		}

		// Return first workload in namespace (simplified)
		if len(workloadList.Items) > 0 {
			return &workloadList.Items[0], nil
		}
		return nil, nil
	}

	// Parse workload label: <namespace>.<name>
	// For now, list all workloads and match
	workloadList := &malev1alpha1.MaleWorkloadList{}
	if err := m.Client.List(ctx, workloadList, client.InNamespace(namespace)); err != nil {
		return nil, err
	}

	for i := range workloadList.Items {
		wl := &workloadList.Items[i]
		expectedLabel := fmt.Sprintf("%s.%s", wl.Namespace, wl.Name)
		if workloadLabel == expectedLabel {
			return wl, nil
		}
	}

	return nil, nil
}
