package metrics

import (
	"github.com/prometheus/client_golang/prometheus"
	"sigs.k8s.io/controller-runtime/pkg/metrics"
)

var (
	// MALE 정책 적용 성공/실패 카운터
	PolicyApplicationsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "male_policy_applications_total",
			Help: "Total number of MALE policy applications",
		},
		[]string{"policy_name", "namespace", "status", "workload_type"},
	)

	// 클러스터별 MALE 값 분포
	MALEValuesGauge = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "male_values_current",
			Help: "Current MALE values applied to workloads",
		},
		[]string{"cluster", "workload", "namespace", "metric_type"},
	)

	// 정책 적용 소요 시간
	PolicyApplicationDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "male_policy_application_duration_seconds",
			Help:    "Time taken to apply MALE policy",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"policy_name", "workload_type"},
	)

	// 활성 정책 수
	ActivePoliciesGauge = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "male_active_policies_total",
			Help: "Number of active MALE policies",
		},
		[]string{"namespace"},
	)

	// 클러스터 프로파일 정보
	ClusterProfileInfo = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "male_cluster_profile_info",
			Help: "Information about cluster profiles",
		},
		[]string{"cluster", "type", "cpu_cores", "memory_gb", "gpu_count"},
	)
)

func init() {
	// 메트릭을 controller-runtime에 등록
	metrics.Registry.MustRegister(
		PolicyApplicationsTotal,
		MALEValuesGauge,
		PolicyApplicationDuration,
		ActivePoliciesGauge,
		ClusterProfileInfo,
	)
}

// RecordPolicyApplication records a policy application event
func RecordPolicyApplication(policyName, namespace, status, workloadType string) {
	PolicyApplicationsTotal.WithLabelValues(policyName, namespace, status, workloadType).Inc()
}

// RecordMALEValues records current MALE values for a workload
func RecordMALEValues(cluster, workload, namespace string, accuracy, latency, energy int32) {
	MALEValuesGauge.WithLabelValues(cluster, workload, namespace, "accuracy").Set(float64(accuracy))
	MALEValuesGauge.WithLabelValues(cluster, workload, namespace, "latency").Set(float64(latency))
	MALEValuesGauge.WithLabelValues(cluster, workload, namespace, "energy").Set(float64(energy))
}

// RecordPolicyApplicationDuration records how long it took to apply a policy
func RecordPolicyApplicationDuration(policyName, workloadType string, duration float64) {
	PolicyApplicationDuration.WithLabelValues(policyName, workloadType).Observe(duration)
}

// UpdateActivePolicies updates the count of active policies in a namespace
func UpdateActivePolicies(namespace string, count float64) {
	ActivePoliciesGauge.WithLabelValues(namespace).Set(count)
}

// RecordClusterProfile records cluster profile information
func RecordClusterProfile(cluster, clusterType string, cpuCores, memoryGB, gpuCount int64) {
	ClusterProfileInfo.WithLabelValues(
		cluster,
		clusterType,
		string(rune(cpuCores)),
		string(rune(memoryGB)),
		string(rune(gpuCount)),
	).Set(1)
}
