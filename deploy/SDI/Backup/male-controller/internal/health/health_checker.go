package health

import (
	"context"
	"fmt"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	"k8s.io/apimachinery/pkg/types"
	opensdiv1alpha1 "male-policy-controller/api/v1alpha1"
	"sigs.k8s.io/controller-runtime/pkg/client"
	logf "sigs.k8s.io/controller-runtime/pkg/log"
)

// HealthChecker monitors the health of MALE policies and workloads
type HealthChecker struct {
	client.Client
	checkInterval time.Duration
}

// NewHealthChecker creates a new health checker
func NewHealthChecker(client client.Client, interval time.Duration) *HealthChecker {
	return &HealthChecker{
		Client:        client,
		checkInterval: interval,
	}
}

// HealthStatus represents the health status of a component
type HealthStatus struct {
	Component   string                 `json:"component"`
	Status      string                 `json:"status"` // healthy, degraded, unhealthy
	LastChecked time.Time              `json:"lastChecked"`
	Message     string                 `json:"message"`
	Details     map[string]interface{} `json:"details,omitempty"`
}

// PolicyHealthReport represents health report for a policy
type PolicyHealthReport struct {
	PolicyName     string                 `json:"policyName"`
	Namespace      string                 `json:"namespace"`
	OverallStatus  string                 `json:"overallStatus"`
	WorkloadHealth []WorkloadHealthStatus `json:"workloadHealth"`
	LastChecked    time.Time              `json:"lastChecked"`
	Issues         []string               `json:"issues,omitempty"`
}

// WorkloadHealthStatus represents health status of a workload
type WorkloadHealthStatus struct {
	Name          string           `json:"name"`
	Namespace     string           `json:"namespace"`
	Kind          string           `json:"kind"`
	Status        string           `json:"status"`
	MALEApplied   bool             `json:"maleApplied"`
	MALEValues    map[string]int32 `json:"maleValues"`
	ReplicaStatus string           `json:"replicaStatus"`
	LastUpdated   time.Time        `json:"lastUpdated"`
	Issues        []string         `json:"issues,omitempty"`
}

// Start begins the health checking process
func (hc *HealthChecker) Start(ctx context.Context) {
	log := logf.FromContext(ctx)
	ticker := time.NewTicker(hc.checkInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			log.Info("Health checker stopping")
			return
		case <-ticker.C:
			if err := hc.performHealthCheck(ctx); err != nil {
				log.Error(err, "Health check failed")
			}
		}
	}
}

// performHealthCheck performs a comprehensive health check
func (hc *HealthChecker) performHealthCheck(ctx context.Context) error {
	log := logf.FromContext(ctx)

	// 모든 MALE 정책 조회
	policyList := &opensdiv1alpha1.MALEPolicyList{}
	if err := hc.List(ctx, policyList); err != nil {
		return fmt.Errorf("failed to list MALE policies: %w", err)
	}

	for _, policy := range policyList.Items {
		report, err := hc.checkPolicyHealth(ctx, &policy)
		if err != nil {
			log.Error(err, "Failed to check policy health", "policy", policy.Name)
			continue
		}

		// 건강하지 않은 정책들에 대해 로그 출력
		if report.OverallStatus != "healthy" {
			log.Info("Policy health issue detected",
				"policy", report.PolicyName,
				"status", report.OverallStatus,
				"issues", report.Issues,
			)
		}
	}

	return nil
}

// checkPolicyHealth checks the health of a specific policy
func (hc *HealthChecker) checkPolicyHealth(ctx context.Context, policy *opensdiv1alpha1.MALEPolicy) (*PolicyHealthReport, error) {
	report := &PolicyHealthReport{
		PolicyName:     policy.Name,
		Namespace:      policy.Namespace,
		LastChecked:    time.Now(),
		WorkloadHealth: []WorkloadHealthStatus{},
		Issues:         []string{},
	}

	// 정책에 연결된 워크로드들의 상태 확인
	for _, workloadStatus := range policy.Status.WorkloadStatus {
		health, err := hc.checkWorkloadHealth(ctx, workloadStatus)
		if err != nil {
			report.Issues = append(report.Issues, fmt.Sprintf("Failed to check workload %s: %v", workloadStatus.Name, err))
			continue
		}
		report.WorkloadHealth = append(report.WorkloadHealth, *health)
	}

	// 전체 상태 결정
	report.OverallStatus = hc.determineOverallStatus(report)

	return report, nil
}

// checkWorkloadHealth checks the health of a specific workload
func (hc *HealthChecker) checkWorkloadHealth(ctx context.Context, workloadStatus opensdiv1alpha1.WorkloadStatus) (*WorkloadHealthStatus, error) {
	health := &WorkloadHealthStatus{
		Name:        workloadStatus.Name,
		Namespace:   workloadStatus.Namespace,
		Kind:        workloadStatus.Kind,
		Status:      workloadStatus.Status,
		LastUpdated: time.Now(),
		Issues:      []string{},
		MALEValues:  make(map[string]int32),
	}

	switch workloadStatus.Kind {
	case "Deployment":
		return hc.checkDeploymentHealth(ctx, health)
	case "Work":
		return hc.checkKarmadaWorkHealth(ctx, health)
	default:
		health.Issues = append(health.Issues, fmt.Sprintf("Unsupported workload kind: %s", workloadStatus.Kind))
		health.Status = "unknown"
	}

	return health, nil
}

// checkDeploymentHealth checks the health of a Deployment
func (hc *HealthChecker) checkDeploymentHealth(ctx context.Context, health *WorkloadHealthStatus) (*WorkloadHealthStatus, error) {
	var deployment appsv1.Deployment
	err := hc.Get(ctx, types.NamespacedName{Name: health.Name, Namespace: health.Namespace}, &deployment)
	if err != nil {
		health.Status = "unhealthy"
		health.Issues = append(health.Issues, fmt.Sprintf("Deployment not found: %v", err))
		return health, nil
	}

	// MALE 어노테이션 확인
	if deployment.Annotations != nil {
		if accuracy := deployment.Annotations["male-policy.opensdi.io/accuracy"]; accuracy != "" {
			health.MALEApplied = true
			// accuracy 값을 파싱해서 저장 (간단한 구현)
		}
	}

	// Replica 상태 확인
	health.ReplicaStatus = fmt.Sprintf("%d/%d", deployment.Status.ReadyReplicas, deployment.Status.Replicas)

	if deployment.Status.ReadyReplicas == 0 {
		health.Status = "unhealthy"
		health.Issues = append(health.Issues, "No ready replicas")
	} else if deployment.Status.ReadyReplicas < deployment.Status.Replicas {
		health.Status = "degraded"
		health.Issues = append(health.Issues, "Some replicas not ready")
	} else {
		health.Status = "healthy"
	}

	// MALE 어노테이션이 없으면 경고
	if !health.MALEApplied {
		health.Issues = append(health.Issues, "MALE policy not applied")
		if health.Status == "healthy" {
			health.Status = "degraded"
		}
	}

	return health, nil
}

// checkKarmadaWorkHealth checks the health of a Karmada Work
func (hc *HealthChecker) checkKarmadaWorkHealth(ctx context.Context, health *WorkloadHealthStatus) (*WorkloadHealthStatus, error) {
	// Karmada Work 리소스 상태 확인 로직
	// 실제 구현에서는 Work 리소스의 상태를 확인해야 함

	health.Status = "healthy" // 임시
	return health, nil
}

// determineOverallStatus determines the overall health status
func (hc *HealthChecker) determineOverallStatus(report *PolicyHealthReport) string {
	if len(report.Issues) > 0 {
		return "degraded"
	}

	healthyCount := 0
	degradedCount := 0
	unhealthyCount := 0

	for _, workload := range report.WorkloadHealth {
		switch workload.Status {
		case "healthy":
			healthyCount++
		case "degraded":
			degradedCount++
		case "unhealthy":
			unhealthyCount++
		}
	}

	if unhealthyCount > 0 {
		return "unhealthy"
	}

	if degradedCount > 0 {
		return "degraded"
	}

	return "healthy"
}

// GetSystemHealth returns overall system health
func (hc *HealthChecker) GetSystemHealth(ctx context.Context) (*HealthStatus, error) {
	status := &HealthStatus{
		Component:   "male-controller",
		LastChecked: time.Now(),
		Details:     make(map[string]interface{}),
	}

	// MALE 정책 수 확인
	policyList := &opensdiv1alpha1.MALEPolicyList{}
	if err := hc.List(ctx, policyList); err != nil {
		status.Status = "unhealthy"
		status.Message = fmt.Sprintf("Failed to list policies: %v", err)
		return status, nil
	}

	status.Details["totalPolicies"] = len(policyList.Items)

	// 정책별 상태 요약
	healthyPolicies := 0
	for _, policy := range policyList.Items {
		if len(policy.Status.WorkloadStatus) > 0 {
			healthyPolicies++
		}
	}

	status.Details["activePolicies"] = healthyPolicies

	if healthyPolicies == len(policyList.Items) {
		status.Status = "healthy"
		status.Message = "All policies are healthy"
	} else if healthyPolicies > 0 {
		status.Status = "degraded"
		status.Message = fmt.Sprintf("%d/%d policies are active", healthyPolicies, len(policyList.Items))
	} else {
		status.Status = "unhealthy"
		status.Message = "No active policies found"
	}

	return status, nil
}
