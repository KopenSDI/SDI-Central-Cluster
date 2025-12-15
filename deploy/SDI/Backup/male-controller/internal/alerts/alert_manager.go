package alerts

import (
	"context"
	"fmt"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	opensdiv1alpha1 "male-policy-controller/api/v1alpha1"
	"male-policy-controller/internal/health"
	"sigs.k8s.io/controller-runtime/pkg/client"
	logf "sigs.k8s.io/controller-runtime/pkg/log"
)

// AlertManager handles alerting for MALE controller issues
type AlertManager struct {
	client.Client
	webhookURL    string
	eventRecorder *EventRecorder
}

// AlertSeverity represents the severity of an alert
type AlertSeverity string

const (
	SeverityInfo     AlertSeverity = "info"
	SeverityWarning  AlertSeverity = "warning"
	SeverityCritical AlertSeverity = "critical"
)

// Alert represents an alert
type Alert struct {
	Title       string            `json:"title"`
	Message     string            `json:"message"`
	Severity    AlertSeverity     `json:"severity"`
	Component   string            `json:"component"`
	Timestamp   time.Time         `json:"timestamp"`
	Labels      map[string]string `json:"labels"`
	Annotations map[string]string `json:"annotations"`
}

// EventRecorder wraps Kubernetes event recording
type EventRecorder struct {
	client.Client
}

// NewAlertManager creates a new alert manager
func NewAlertManager(client client.Client, webhookURL string) *AlertManager {
	return &AlertManager{
		Client:        client,
		webhookURL:    webhookURL,
		eventRecorder: &EventRecorder{Client: client},
	}
}

// AlertPolicyFailure sends alert for policy application failure
func (am *AlertManager) AlertPolicyFailure(ctx context.Context, policy *opensdiv1alpha1.MALEPolicy, workload string, err error) {
	alert := &Alert{
		Title:     "MALE Policy Application Failed",
		Message:   fmt.Sprintf("Failed to apply policy '%s' to workload '%s': %v", policy.Name, workload, err),
		Severity:  SeverityWarning,
		Component: "male-controller",
		Timestamp: time.Now(),
		Labels: map[string]string{
			"policy":    policy.Name,
			"workload":  workload,
			"alertname": "MALEPolicyApplicationFailed",
		},
		Annotations: map[string]string{
			"namespace": policy.Namespace,
			"accuracy":  fmt.Sprintf("%d", policy.Spec.Accuracy),
			"latency":   fmt.Sprintf("%d", policy.Spec.Latency),
			"energy":    fmt.Sprintf("%d", policy.Spec.Energy),
		},
	}

	am.sendAlert(ctx, alert)
	am.recordEvent(ctx, policy, "Warning", "PolicyApplicationFailed", alert.Message)
}

// AlertClusterDiscoveryFailure sends alert for cluster discovery issues
func (am *AlertManager) AlertClusterDiscoveryFailure(ctx context.Context, clusterName string, err error) {
	alert := &Alert{
		Title:     "Cluster Discovery Failed",
		Message:   fmt.Sprintf("Failed to discover cluster profile for '%s': %v", clusterName, err),
		Severity:  SeverityWarning,
		Component: "male-controller",
		Timestamp: time.Now(),
		Labels: map[string]string{
			"cluster":   clusterName,
			"alertname": "ClusterDiscoveryFailed",
		},
	}

	am.sendAlert(ctx, alert)
}

// AlertHealthCheckFailure sends alert for health check failures
func (am *AlertManager) AlertHealthCheckFailure(ctx context.Context, report *health.PolicyHealthReport) {
	severity := SeverityInfo
	if report.OverallStatus == "unhealthy" {
		severity = SeverityCritical
	} else if report.OverallStatus == "degraded" {
		severity = SeverityWarning
	}

	alert := &Alert{
		Title:     "MALE Policy Health Issue",
		Message:   fmt.Sprintf("Policy '%s' health status: %s. Issues: %v", report.PolicyName, report.OverallStatus, report.Issues),
		Severity:  severity,
		Component: "male-controller",
		Timestamp: time.Now(),
		Labels: map[string]string{
			"policy":    report.PolicyName,
			"namespace": report.Namespace,
			"status":    report.OverallStatus,
			"alertname": "MALEPolicyHealthIssue",
		},
	}

	am.sendAlert(ctx, alert)
}

// AlertSignificantPolicyChange sends alert for significant policy changes
func (am *AlertManager) AlertSignificantPolicyChange(ctx context.Context, policy *opensdiv1alpha1.MALEPolicy, oldValues, newValues map[string]int32) {
	alert := &Alert{
		Title:     "Significant MALE Policy Change",
		Message:   fmt.Sprintf("Policy '%s' has significant changes that may impact workloads", policy.Name),
		Severity:  SeverityWarning,
		Component: "male-controller",
		Timestamp: time.Now(),
		Labels: map[string]string{
			"policy":    policy.Name,
			"namespace": policy.Namespace,
			"alertname": "SignificantMALEPolicyChange",
		},
		Annotations: map[string]string{
			"old_accuracy": fmt.Sprintf("%d", oldValues["accuracy"]),
			"new_accuracy": fmt.Sprintf("%d", newValues["accuracy"]),
			"old_latency":  fmt.Sprintf("%d", oldValues["latency"]),
			"new_latency":  fmt.Sprintf("%d", newValues["latency"]),
			"old_energy":   fmt.Sprintf("%d", oldValues["energy"]),
			"new_energy":   fmt.Sprintf("%d", newValues["energy"]),
		},
	}

	am.sendAlert(ctx, alert)
	am.recordEvent(ctx, policy, "Normal", "PolicyChanged", alert.Message)
}

// AlertKarmadaIntegrationIssue sends alert for Karmada integration problems
func (am *AlertManager) AlertKarmadaIntegrationIssue(ctx context.Context, workName string, err error) {
	alert := &Alert{
		Title:     "Karmada Integration Issue",
		Message:   fmt.Sprintf("Failed to apply MALE policy to Karmada Work '%s': %v", workName, err),
		Severity:  SeverityWarning,
		Component: "male-controller",
		Timestamp: time.Now(),
		Labels: map[string]string{
			"work":      workName,
			"alertname": "KarmadaIntegrationIssue",
		},
	}

	am.sendAlert(ctx, alert)
}

// sendAlert sends the alert through configured channels
func (am *AlertManager) sendAlert(ctx context.Context, alert *Alert) {
	log := logf.FromContext(ctx)

	// 로그로 알림 출력
	log.Info("Alert triggered",
		"title", alert.Title,
		"severity", alert.Severity,
		"message", alert.Message,
		"labels", alert.Labels,
	)

	// Webhook 전송 (실제 구현에서는 HTTP 클라이언트 사용)
	if am.webhookURL != "" {
		go am.sendWebhookAlert(ctx, alert)
	}

	// 추가 알림 채널 (Slack, Email 등) 구현 가능
}

// sendWebhookAlert sends alert to webhook endpoint
func (am *AlertManager) sendWebhookAlert(ctx context.Context, alert *Alert) {
	log := logf.FromContext(ctx)

	// 실제 구현에서는 HTTP POST 요청을 보내야 함
	log.Info("Sending webhook alert",
		"url", am.webhookURL,
		"title", alert.Title,
		"severity", alert.Severity,
	)

	// Example webhook payload format (Slack/Discord style)
	/*
		payload := map[string]interface{}{
			"text": alert.Title,
			"attachments": []map[string]interface{}{
				{
					"color": am.getSeverityColor(alert.Severity),
					"fields": []map[string]interface{}{
						{"title": "Message", "value": alert.Message, "short": false},
						{"title": "Severity", "value": string(alert.Severity), "short": true},
						{"title": "Component", "value": alert.Component, "short": true},
						{"title": "Time", "value": alert.Timestamp.Format(time.RFC3339), "short": true},
					},
				},
			},
		}
	*/
}

// recordEvent records Kubernetes events
func (am *AlertManager) recordEvent(ctx context.Context, object client.Object, eventType, reason, message string) {
	event := &corev1.Event{
		ObjectMeta: metav1.ObjectMeta{
			Name:      fmt.Sprintf("%s.%x", object.GetName(), time.Now().UnixNano()),
			Namespace: object.GetNamespace(),
		},
		InvolvedObject: corev1.ObjectReference{
			Kind:       object.GetObjectKind().GroupVersionKind().Kind,
			Name:       object.GetName(),
			Namespace:  object.GetNamespace(),
			UID:        object.GetUID(),
			APIVersion: object.GetObjectKind().GroupVersionKind().GroupVersion().String(),
		},
		Reason:  reason,
		Message: message,
		Type:    eventType,
		Source: corev1.EventSource{
			Component: "male-controller",
		},
		FirstTimestamp: metav1.NewTime(time.Now()),
		LastTimestamp:  metav1.NewTime(time.Now()),
		Count:          1,
	}

	if err := am.eventRecorder.Create(ctx, event); err != nil {
		log := logf.FromContext(ctx)
		log.Error(err, "Failed to record event", "object", object.GetName())
	}
}

// getSeverityColor returns color for webhook alerts based on severity
func (am *AlertManager) getSeverityColor(severity AlertSeverity) string {
	switch severity {
	case SeverityCritical:
		return "danger"
	case SeverityWarning:
		return "warning"
	case SeverityInfo:
		return "good"
	default:
		return "good"
	}
}
