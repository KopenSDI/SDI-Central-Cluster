/*
Copyright 2025.

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

package controller

import (
	"context"
	"fmt"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/labels"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	logf "sigs.k8s.io/controller-runtime/pkg/log"

	opensdiv1alpha1 "male-policy-controller/api/v1alpha1"
	"male-policy-controller/internal/alerts"
	"male-policy-controller/internal/metrics"
	"male-policy-controller/internal/validation"
)

// MALEPolicyReconciler reconciles a MALEPolicy object
type MALEPolicyReconciler struct {
	client.Client
	Scheme          *runtime.Scheme
	AlertManager    *alerts.AlertManager
	PolicyValidator *validation.PolicyValidator
}

// +kubebuilder:rbac:groups=opensdi.opensdi.io,resources=malepolicies,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=opensdi.opensdi.io,resources=malepolicies/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=opensdi.opensdi.io,resources=malepolicies/finalizers,verbs=update
// +kubebuilder:rbac:groups=apps,resources=deployments,verbs=get;list;watch

// Reconcile is part of the main kubernetes reconciliation loop which aims to
// move the current state of the cluster closer to the desired state.
//
// For more details, check Reconcile and its Result here:
// - https://pkg.go.dev/sigs.k8s.io/controller-runtime@v0.21.0/pkg/reconcile
func (r *MALEPolicyReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	log := logf.FromContext(ctx)
	startTime := time.Now()

	// MALEPolicy 리소스 조회
	var malePolicy opensdiv1alpha1.MALEPolicy
	if err := r.Get(ctx, req.NamespacedName, &malePolicy); err != nil {
		if client.IgnoreNotFound(err) != nil {
			log.Error(err, "unable to fetch MALEPolicy")
			metrics.RecordPolicyApplication(req.Name, req.Namespace, "failed", "unknown")
			return ctrl.Result{}, err
		}
		// 리소스가 삭제된 경우
		log.Info("MALEPolicy resource deleted", "name", req.Name, "namespace", req.Namespace)
		return ctrl.Result{}, nil
	}

	// 정책 검증
	if r.PolicyValidator != nil {
		if err := r.PolicyValidator.ValidatePolicy(&malePolicy); err != nil {
			log.Error(err, "Policy validation failed", "policy", malePolicy.Name)
			if r.AlertManager != nil {
				r.AlertManager.AlertPolicyFailure(ctx, &malePolicy, "validation", err)
			}
			metrics.RecordPolicyApplication(malePolicy.Name, malePolicy.Namespace, "validation_failed", "policy")
			return ctrl.Result{RequeueAfter: time.Minute * 2}, err
		}
	}

	// MALEPolicy 변경 감지 및 로깅
	log.Info("MALEPolicy reconciling",
		"name", malePolicy.Name,
		"namespace", malePolicy.Namespace,
		"accuracy", malePolicy.Spec.Accuracy,
		"latency", malePolicy.Spec.Latency,
		"energy", malePolicy.Spec.Energy,
		"selector", malePolicy.Spec.Selector,
		"targetNamespaces", malePolicy.Spec.TargetNamespaces,
	)

	// 워크로드에 MALE 정책 적용
	workloadStatuses, err := r.applyPolicyToWorkloads(ctx, &malePolicy)
	if err != nil {
		log.Error(err, "failed to apply policy to workloads")
		return ctrl.Result{}, err
	}

	// Karmada 환경에서 Work 리소스에도 MALE 정책 적용
	karmadaStatuses, err := r.applyToKarmadaWorks(ctx, &malePolicy)
	if err != nil {
		log.Error(err, "failed to apply policy to Karmada Works")
		// Karmada 연동 실패는 전체 실패로 처리하지 않음
	} else if len(karmadaStatuses) > 0 {
		workloadStatuses = append(workloadStatuses, karmadaStatuses...)
		log.Info("Applied MALE policy to Karmada Works", "count", len(karmadaStatuses))
	}

	// Status 업데이트
	err = r.updatePolicyStatus(ctx, &malePolicy, workloadStatuses)
	if err != nil {
		log.Error(err, "failed to update policy status")
		if r.AlertManager != nil {
			r.AlertManager.AlertPolicyFailure(ctx, &malePolicy, "status_update", err)
		}
		return ctrl.Result{RequeueAfter: time.Minute * 1}, err
	}

	// 메트릭 기록
	duration := time.Since(startTime).Seconds()
	metrics.RecordPolicyApplicationDuration(malePolicy.Name, "policy", duration)
	metrics.RecordPolicyApplication(malePolicy.Name, malePolicy.Namespace, "success", "policy")
	metrics.UpdateActivePolicies(malePolicy.Namespace, float64(len(workloadStatuses)))

	// MALE 값 메트릭 기록
	for _, status := range workloadStatuses {
		metrics.RecordMALEValues("local", status.Name, status.Namespace,
			malePolicy.Spec.Accuracy, malePolicy.Spec.Latency, malePolicy.Spec.Energy)
	}

	log.Info("MALEPolicy successfully applied", "appliedWorkloads", len(workloadStatuses), "duration", duration)
	return ctrl.Result{RequeueAfter: time.Minute * 5}, nil
}

// applyPolicyToWorkloads finds and applies MALE policy to matching workloads
func (r *MALEPolicyReconciler) applyPolicyToWorkloads(ctx context.Context, policy *opensdiv1alpha1.MALEPolicy) ([]opensdiv1alpha1.WorkloadStatus, error) {
	log := logf.FromContext(ctx)
	var workloadStatuses []opensdiv1alpha1.WorkloadStatus

	// 1. 특정 워크로드 직접 지정된 경우 우선 처리
	if len(policy.Spec.TargetWorkloads) > 0 {
		for _, target := range policy.Spec.TargetWorkloads {
			status := r.applyToSpecificWorkload(ctx, policy, target)
			workloadStatuses = append(workloadStatuses, status)
		}
	}

	// 2. 라벨 셀렉터 기반 매칭
	if len(policy.Spec.Selector) > 0 {
		selectorStatuses, err := r.applyBySelector(ctx, policy)
		if err != nil {
			log.Error(err, "failed to apply policy by selector")
			return workloadStatuses, err
		}
		workloadStatuses = append(workloadStatuses, selectorStatuses...)
	}

	// 3. GlobalDefault인 경우 모든 워크로드에 적용
	if policy.Spec.GlobalDefault && len(policy.Spec.TargetWorkloads) == 0 && len(policy.Spec.Selector) == 0 {
		globalStatuses, err := r.applyGlobalDefault(ctx, policy)
		if err != nil {
			log.Error(err, "failed to apply global default policy")
			return workloadStatuses, err
		}
		workloadStatuses = append(workloadStatuses, globalStatuses...)
	}

	return workloadStatuses, nil
}

// applyToSpecificWorkload applies policy to a specifically named workload
func (r *MALEPolicyReconciler) applyToSpecificWorkload(ctx context.Context, policy *opensdiv1alpha1.MALEPolicy, target opensdiv1alpha1.WorkloadTarget) opensdiv1alpha1.WorkloadStatus {
	log := logf.FromContext(ctx)
	status := opensdiv1alpha1.WorkloadStatus{
		Name:      target.Name,
		Namespace: target.Namespace,
		Kind:      target.Kind,
		Status:    "Pending",
	}

	switch target.Kind {
	case "Deployment":
		var deployment appsv1.Deployment
		err := r.Get(ctx, client.ObjectKey{Name: target.Name, Namespace: target.Namespace}, &deployment)
		if err != nil {
			log.Error(err, "failed to get specific deployment", "name", target.Name, "namespace", target.Namespace)
			status.Status = "Failed"
			return status
		}

		if err := r.applyPolicyToDeployment(ctx, &deployment, policy); err != nil {
			log.Error(err, "failed to apply policy to specific deployment", "name", target.Name)
			status.Status = "Failed"
		} else {
			status.Status = "Applied"
			log.Info("Applied MALE policy to specific deployment",
				"deployment", target.Name,
				"namespace", target.Namespace,
				"accuracy", policy.Spec.Accuracy,
				"latency", policy.Spec.Latency,
				"energy", policy.Spec.Energy,
			)
		}

	default:
		log.Info("Unsupported workload kind for specific targeting", "kind", target.Kind)
		status.Status = "Failed"
	}

	return status
}

// applyBySelector applies policy to workloads matching the selector
func (r *MALEPolicyReconciler) applyBySelector(ctx context.Context, policy *opensdiv1alpha1.MALEPolicy) ([]opensdiv1alpha1.WorkloadStatus, error) {
	log := logf.FromContext(ctx)
	var workloadStatuses []opensdiv1alpha1.WorkloadStatus

	// 타겟 네임스페이스 결정
	namespaces := policy.Spec.TargetNamespaces
	if len(namespaces) == 0 {
		// 모든 네임스페이스 대상
		namespaceList := &corev1.NamespaceList{}
		if err := r.List(ctx, namespaceList); err != nil {
			return nil, fmt.Errorf("failed to list namespaces: %w", err)
		}
		for _, ns := range namespaceList.Items {
			namespaces = append(namespaces, ns.Name)
		}
	}

	// 각 네임스페이스에서 매칭되는 워크로드 찾기
	for _, namespace := range namespaces {
		deployments, err := r.findMatchingDeployments(ctx, namespace, policy.Spec.Selector)
		if err != nil {
			log.Error(err, "failed to find deployments", "namespace", namespace)
			continue
		}

		for _, deployment := range deployments {
			status := opensdiv1alpha1.WorkloadStatus{
				Name:      deployment.Name,
				Namespace: deployment.Namespace,
				Kind:      "Deployment",
				Status:    "Pending",
			}

			if err := r.applyPolicyToDeployment(ctx, &deployment, policy); err != nil {
				log.Error(err, "failed to apply policy to deployment", "name", deployment.Name)
				status.Status = "Failed"
			} else {
				status.Status = "Applied"
				log.Info("Applied MALE policy to deployment via selector",
					"deployment", deployment.Name,
					"namespace", deployment.Namespace,
				)
			}

			workloadStatuses = append(workloadStatuses, status)
		}
	}

	return workloadStatuses, nil
}

// applyGlobalDefault applies policy to all workloads (used when GlobalDefault is true)
func (r *MALEPolicyReconciler) applyGlobalDefault(ctx context.Context, policy *opensdiv1alpha1.MALEPolicy) ([]opensdiv1alpha1.WorkloadStatus, error) {
	// 모든 네임스페이스의 모든 Deployment에 적용
	return r.applyBySelector(ctx, policy)
}

// applyToKarmadaWorks applies MALE policy to Karmada Work resources for multi-cluster deployment
func (r *MALEPolicyReconciler) applyToKarmadaWorks(ctx context.Context, policy *opensdiv1alpha1.MALEPolicy) ([]opensdiv1alpha1.WorkloadStatus, error) {
	log := logf.FromContext(ctx)
	var workloadStatuses []opensdiv1alpha1.WorkloadStatus

	// 클러스터 프로파일 자동 수집
	clusterProfiles, err := r.discoverClusterProfiles(ctx)
	if err != nil {
		log.Error(err, "failed to discover cluster profiles")
		clusterProfiles = make(map[string]*ClusterProfile) // 빈 프로파일로 계속 진행
	}

	// Karmada Work 리소스 조회
	workList := &unstructured.UnstructuredList{}
	workList.SetAPIVersion("work.karmada.io/v1alpha1")
	workList.SetKind("Work")

	err = r.List(ctx, workList)
	if err != nil {
		// Karmada가 설치되지 않은 경우 무시
		log.Info("Karmada Work resources not found, skipping multi-cluster deployment")
		return workloadStatuses, nil
	}

	for _, work := range workList.Items {
		// Work 내부의 Deployment 리소스 확인
		workloads, found, err := unstructured.NestedSlice(work.Object, "spec", "workload", "manifests")
		if err != nil || !found {
			continue
		}

		for i, workload := range workloads {
			workloadMap, ok := workload.(map[string]interface{})
			if !ok {
				continue
			}

			// Deployment인지 확인
			kind, _, _ := unstructured.NestedString(workloadMap, "kind")
			if kind != "Deployment" {
				continue
			}

			// 라벨 매칭 확인
			if r.matchesPolicy(workloadMap, policy) {
				// 클러스터 이름 추출 (Work 네임스페이스에서)
				clusterName := r.extractClusterNameFromWork(&work)

				// 클러스터별 MALE 값 자동 조정
				adjustedAccuracy, adjustedLatency, adjustedEnergy := r.applyClusterSpecificMALE(policy, clusterName, clusterProfiles)

				// 조정된 값으로 새 정책 생성
				adjustedPolicy := &opensdiv1alpha1.MALEPolicy{
					ObjectMeta: policy.ObjectMeta,
					Spec: opensdiv1alpha1.MALEPolicySpec{
						Accuracy: adjustedAccuracy,
						Latency:  adjustedLatency,
						Energy:   adjustedEnergy,
					},
				}

				// MALE 정책 적용
				err := r.applyMALEToWorkResource(workloadMap, adjustedPolicy, work.GetName())
				if err != nil {
					log.Error(err, "failed to apply MALE policy to Karmada Work", "work", work.GetName())
					continue
				}

				log.Info("Applied cluster-specific MALE policy",
					"work", work.GetName(),
					"cluster", clusterName,
					"clusterType", r.getClusterType(clusterName, clusterProfiles),
					"adjustedAccuracy", adjustedAccuracy,
					"adjustedLatency", adjustedLatency,
					"adjustedEnergy", adjustedEnergy,
				)

				// 수정된 workload를 다시 Work에 저장
				workloads[i] = workloadMap
			}
		}

		// 수정된 manifests를 Work에 저장
		if err := unstructured.SetNestedSlice(work.Object, workloads, "spec", "workload", "manifests"); err != nil {
			log.Error(err, "failed to update Work manifests", "work", work.GetName())
			continue
		}

		// Work 리소스 업데이트
		if err := r.Update(ctx, &work); err != nil {
			log.Error(err, "failed to update Karmada Work", "work", work.GetName())
			workloadStatuses = append(workloadStatuses, opensdiv1alpha1.WorkloadStatus{
				Name:      work.GetName(),
				Namespace: work.GetNamespace(),
				Kind:      "Work",
				Status:    "Failed",
			})
		} else {
			log.Info("Applied MALE policy to Karmada Work",
				"work", work.GetName(),
				"accuracy", policy.Spec.Accuracy,
				"latency", policy.Spec.Latency,
				"energy", policy.Spec.Energy,
			)
			workloadStatuses = append(workloadStatuses, opensdiv1alpha1.WorkloadStatus{
				Name:      work.GetName(),
				Namespace: work.GetNamespace(),
				Kind:      "Work",
				Status:    "Applied",
			})
		}
	}

	return workloadStatuses, nil
}

// matchesPolicy checks if a workload matches the policy selector
func (r *MALEPolicyReconciler) matchesPolicy(workload map[string]interface{}, policy *opensdiv1alpha1.MALEPolicy) bool {
	if len(policy.Spec.Selector) == 0 {
		return policy.Spec.GlobalDefault
	}

	// 워크로드의 라벨 확인
	labels, found, err := unstructured.NestedStringMap(workload, "metadata", "labels")
	if err != nil || !found {
		return false
	}

	// 모든 셀렉터 조건이 일치하는지 확인
	for key, value := range policy.Spec.Selector {
		if labels[key] != value {
			return false
		}
	}

	return true
}

// applyMALEToWorkResource applies MALE policy to a workload within a Karmada Work
func (r *MALEPolicyReconciler) applyMALEToWorkResource(workload map[string]interface{}, policy *opensdiv1alpha1.MALEPolicy, workName string) error {
	// Deployment annotations에 MALE 정책 추가
	annotations, found, err := unstructured.NestedStringMap(workload, "metadata", "annotations")
	if err != nil {
		return fmt.Errorf("failed to get annotations: %w", err)
	}
	if !found {
		annotations = make(map[string]string)
	}

	annotations["male-policy.opensdi.io/accuracy"] = fmt.Sprintf("%d", policy.Spec.Accuracy)
	annotations["male-policy.opensdi.io/latency"] = fmt.Sprintf("%d", policy.Spec.Latency)
	annotations["male-policy.opensdi.io/energy"] = fmt.Sprintf("%d", policy.Spec.Energy)
	annotations["male-policy.opensdi.io/policy-name"] = policy.Name
	annotations["male-policy.opensdi.io/work-name"] = workName
	annotations["male-policy.opensdi.io/applied-at"] = time.Now().Format(time.RFC3339)

	if err := unstructured.SetNestedStringMap(workload, annotations, "metadata", "annotations"); err != nil {
		return fmt.Errorf("failed to set annotations: %w", err)
	}

	// Pod template의 환경변수에 MALE 값 추가
	containers, found, err := unstructured.NestedSlice(workload, "spec", "template", "spec", "containers")
	if err != nil || !found {
		return fmt.Errorf("failed to get containers: %w", err)
	}

	for i, container := range containers {
		containerMap, ok := container.(map[string]interface{})
		if !ok {
			continue
		}

		// 기존 환경변수 가져오기
		env, found, err := unstructured.NestedSlice(containerMap, "env")
		if err != nil {
			return fmt.Errorf("failed to get env: %w", err)
		}
		if !found {
			env = []interface{}{}
		}

		// 기존 MALE 환경변수 제거
		var newEnv []interface{}
		for _, e := range env {
			envMap, ok := e.(map[string]interface{})
			if !ok {
				continue
			}
			name, _, _ := unstructured.NestedString(envMap, "name")
			if name != "MALE_ACCURACY" && name != "MALE_LATENCY" && name != "MALE_ENERGY" {
				newEnv = append(newEnv, e)
			}
		}

		// 새로운 MALE 환경변수 추가
		maleEnvs := []map[string]interface{}{
			{"name": "MALE_ACCURACY", "value": fmt.Sprintf("%d", policy.Spec.Accuracy)},
			{"name": "MALE_LATENCY", "value": fmt.Sprintf("%d", policy.Spec.Latency)},
			{"name": "MALE_ENERGY", "value": fmt.Sprintf("%d", policy.Spec.Energy)},
		}

		for _, maleEnv := range maleEnvs {
			newEnv = append(newEnv, maleEnv)
		}

		// 컨테이너에 환경변수 설정
		if err := unstructured.SetNestedSlice(containerMap, newEnv, "env"); err != nil {
			return fmt.Errorf("failed to set env: %w", err)
		}

		containers[i] = containerMap
	}

	// 수정된 컨테이너를 다시 설정
	return unstructured.SetNestedSlice(workload, containers, "spec", "template", "spec", "containers")
}

// ClusterProfile represents the characteristics of a cluster
type ClusterProfile struct {
	Name         string
	ClusterType  string // edge, gpu, cpu, hybrid
	CPUCores     int64
	MemoryGB     int64
	GPUCount     int64
	GPUType      string
	PowerProfile string // low-power, high-performance, balanced
	NetworkType  string // 5g, wifi, ethernet
	Location     string // edge, datacenter, cloud
}

// discoverClusterProfiles automatically discovers cluster characteristics
func (r *MALEPolicyReconciler) discoverClusterProfiles(ctx context.Context) (map[string]*ClusterProfile, error) {
	log := logf.FromContext(ctx)
	profiles := make(map[string]*ClusterProfile)

	// Karmada Cluster 리소스 조회
	clusterList := &unstructured.UnstructuredList{}
	clusterList.SetAPIVersion("cluster.karmada.io/v1alpha1")
	clusterList.SetKind("Cluster")

	err := r.List(ctx, clusterList)
	if err != nil {
		return nil, fmt.Errorf("failed to list Karmada clusters: %w", err)
	}

	for _, cluster := range clusterList.Items {
		profile, err := r.analyzeClusterCapabilities(ctx, &cluster)
		if err != nil {
			log.Error(err, "failed to analyze cluster", "cluster", cluster.GetName())
			continue
		}

		profiles[cluster.GetName()] = profile
		log.Info("Discovered cluster profile",
			"cluster", profile.Name,
			"type", profile.ClusterType,
			"cpus", profile.CPUCores,
			"memory", profile.MemoryGB,
			"gpus", profile.GPUCount,
		)
	}

	return profiles, nil
}

// analyzeClusterCapabilities analyzes a cluster's hardware and classifies it
func (r *MALEPolicyReconciler) analyzeClusterCapabilities(ctx context.Context, cluster *unstructured.Unstructured) (*ClusterProfile, error) {
	profile := &ClusterProfile{
		Name: cluster.GetName(),
	}

	// 1. Cluster status에서 노드 정보 추출
	nodesSummary, found, err := unstructured.NestedMap(cluster.Object, "status", "nodeSummary")
	if err != nil || !found {
		return profile, fmt.Errorf("node summary not found")
	}

	// 총 CPU 코어 수
	if totalCPU, found, _ := unstructured.NestedInt64(nodesSummary, "totalCPU"); found {
		profile.CPUCores = totalCPU
	}

	// 총 메모리 (bytes를 GB로 변환)
	if totalMemory, found, _ := unstructured.NestedInt64(nodesSummary, "totalMemory"); found {
		profile.MemoryGB = totalMemory / (1024 * 1024 * 1024)
	}

	// 2. 클러스터 라벨에서 추가 정보 수집
	labels := cluster.GetLabels()
	if labels != nil {
		// GPU 정보
		if gpuCount := labels["hardware.karmada.io/gpu-count"]; gpuCount != "" {
			if count, err := fmt.Sscanf(gpuCount, "%d", &profile.GPUCount); err == nil && count > 0 {
				profile.GPUType = labels["hardware.karmada.io/gpu-type"]
			}
		}

		// 전력 프로파일
		if powerProfile := labels["hardware.karmada.io/power-profile"]; powerProfile != "" {
			profile.PowerProfile = powerProfile
		}

		// 네트워크 타입
		if networkType := labels["network.karmada.io/type"]; networkType != "" {
			profile.NetworkType = networkType
		}

		// 위치 정보
		if location := labels["topology.karmada.io/location"]; location != "" {
			profile.Location = location
		}
	}

	// 3. 자동 클러스터 타입 분류
	profile.ClusterType = r.classifyCluster(profile)

	return profile, nil
}

// classifyCluster automatically classifies cluster type based on hardware characteristics
func (r *MALEPolicyReconciler) classifyCluster(profile *ClusterProfile) string {
	// GPU가 있으면 GPU 클러스터
	if profile.GPUCount > 0 {
		return "gpu"
	}

	// 전력 프로파일이 low-power이거나 위치가 edge면 엣지 클러스터
	if profile.PowerProfile == "low-power" || profile.Location == "edge" {
		return "edge"
	}

	// 5G 네트워크이면서 CPU가 적으면 엣지
	if profile.NetworkType == "5g" && profile.CPUCores < 8 {
		return "edge"
	}

	// 높은 CPU/메모리 리소스면 고성능 클러스터
	if profile.CPUCores >= 32 && profile.MemoryGB >= 64 {
		return "high-performance"
	}

	// 중간 리소스면 일반 CPU 클러스터
	if profile.CPUCores >= 8 && profile.MemoryGB >= 16 {
		return "cpu"
	}

	// 기본값은 edge (소형 클러스터)
	return "edge"
}

// applyClusterSpecificMALE applies cluster-specific MALE adjustments
func (r *MALEPolicyReconciler) applyClusterSpecificMALE(policy *opensdiv1alpha1.MALEPolicy, clusterName string, profiles map[string]*ClusterProfile) (int32, int32, int32) {
	baseAccuracy := policy.Spec.Accuracy
	baseLatency := policy.Spec.Latency
	baseEnergy := policy.Spec.Energy

	profile, exists := profiles[clusterName]
	if !exists {
		// 프로파일이 없으면 기본값 반환
		return baseAccuracy, baseLatency, baseEnergy
	}

	// 클러스터 타입별 자동 조정
	switch profile.ClusterType {
	case "gpu":
		// GPU 클러스터: 고성능 우선
		return r.clampValue(baseAccuracy + 100), // 정확도 증가
			r.clampValue(baseLatency - 50), // 지연시간 감소
			r.clampValue(baseEnergy - 100) // 전력효율 감소 (성능 우선)

	case "edge":
		// 엣지 클러스터: 전력효율 우선
		return r.clampValue(baseAccuracy - 100), // 정확도 감소
			r.clampValue(baseLatency + 100), // 지연시간 증가 허용
			r.clampValue(baseEnergy + 200) // 전력효율 증가

	case "high-performance":
		// 고성능 클러스터: 균형 잡힌 고성능
		return r.clampValue(baseAccuracy + 50), // 정확도 약간 증가
			r.clampValue(baseLatency - 30), // 지연시간 약간 감소
			r.clampValue(baseEnergy - 50) // 전력효율 약간 감소

	case "cpu":
		// 일반 CPU 클러스터: 균형 유지
		return baseAccuracy,
			baseLatency,
			r.clampValue(baseEnergy + 50) // 전력효율 약간 증가

	default:
		return baseAccuracy, baseLatency, baseEnergy
	}
}

// clampValue clamps MALE values to valid range (0-1000)
func (r *MALEPolicyReconciler) clampValue(value int32) int32 {
	if value < 0 {
		return 0
	}
	if value > 1000 {
		return 1000
	}
	return value
}

// extractClusterNameFromWork extracts cluster name from Karmada Work namespace
func (r *MALEPolicyReconciler) extractClusterNameFromWork(work *unstructured.Unstructured) string {
	namespace := work.GetNamespace()
	// Karmada Work 네임스페이스 형식: karmada-es-{cluster-name}
	if len(namespace) > 11 && namespace[:11] == "karmada-es-" {
		return namespace[11:]
	}
	return "unknown"
}

// getClusterType returns cluster type for a given cluster name
func (r *MALEPolicyReconciler) getClusterType(clusterName string, profiles map[string]*ClusterProfile) string {
	if profile, exists := profiles[clusterName]; exists {
		return profile.ClusterType
	}
	return "unknown"
}

// findMatchingDeployments finds deployments matching the selector
func (r *MALEPolicyReconciler) findMatchingDeployments(ctx context.Context, namespace string, selector map[string]string) ([]appsv1.Deployment, error) {
	deploymentList := &appsv1.DeploymentList{}

	listOpts := []client.ListOption{
		client.InNamespace(namespace),
	}

	if len(selector) > 0 {
		labelSelector := labels.SelectorFromSet(selector)
		listOpts = append(listOpts, client.MatchingLabelsSelector{Selector: labelSelector})
	}

	err := r.List(ctx, deploymentList, listOpts...)
	if err != nil {
		return nil, fmt.Errorf("failed to list deployments: %w", err)
	}

	return deploymentList.Items, nil
}

// applyPolicyToDeployment applies MALE policy to a deployment via annotations and environment variables
func (r *MALEPolicyReconciler) applyPolicyToDeployment(ctx context.Context, deployment *appsv1.Deployment, policy *opensdiv1alpha1.MALEPolicy) error {
	// Deployment annotation에 MALE 정책 추가
	if deployment.Annotations == nil {
		deployment.Annotations = make(map[string]string)
	}

	deployment.Annotations["male-policy.opensdi.io/accuracy"] = fmt.Sprintf("%d", policy.Spec.Accuracy)
	deployment.Annotations["male-policy.opensdi.io/latency"] = fmt.Sprintf("%d", policy.Spec.Latency)
	deployment.Annotations["male-policy.opensdi.io/energy"] = fmt.Sprintf("%d", policy.Spec.Energy)
	deployment.Annotations["male-policy.opensdi.io/policy-name"] = policy.Name
	deployment.Annotations["male-policy.opensdi.io/applied-at"] = time.Now().Format(time.RFC3339)

	// Pod template에 환경변수로도 MALE 값 추가
	containers := deployment.Spec.Template.Spec.Containers
	for i := range containers {
		envVars := []corev1.EnvVar{
			{Name: "MALE_ACCURACY", Value: fmt.Sprintf("%d", policy.Spec.Accuracy)},
			{Name: "MALE_LATENCY", Value: fmt.Sprintf("%d", policy.Spec.Latency)},
			{Name: "MALE_ENERGY", Value: fmt.Sprintf("%d", policy.Spec.Energy)},
		}

		// 기존 MALE_ 환경변수 제거
		var filteredEnv []corev1.EnvVar
		for _, env := range containers[i].Env {
			if env.Name != "MALE_ACCURACY" && env.Name != "MALE_LATENCY" && env.Name != "MALE_ENERGY" {
				filteredEnv = append(filteredEnv, env)
			}
		}

		// 새로운 MALE 환경변수 추가
		containers[i].Env = append(filteredEnv, envVars...)
	}

	// Deployment 업데이트
	return r.Update(ctx, deployment)
}

// updatePolicyStatus updates the MALEPolicy status
func (r *MALEPolicyReconciler) updatePolicyStatus(ctx context.Context, policy *opensdiv1alpha1.MALEPolicy, workloadStatuses []opensdiv1alpha1.WorkloadStatus) error {
	policy.Status.AppliedWorkloads = int32(len(workloadStatuses))
	policy.Status.WorkloadStatus = workloadStatuses
	policy.Status.LastUpdated = time.Now().Format(time.RFC3339)

	return r.Status().Update(ctx, policy)
}

// SetupWithManager sets up the controller with the Manager.
func (r *MALEPolicyReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&opensdiv1alpha1.MALEPolicy{}).
		Owns(&appsv1.Deployment{}).
		Named("malepolicy").
		Complete(r)
}
