package server

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"male-policy-controller/internal/health"
	"sigs.k8s.io/controller-runtime/pkg/client"
	logf "sigs.k8s.io/controller-runtime/pkg/log"
)

// HealthServer provides HTTP endpoints for health checking
type HealthServer struct {
	healthChecker *health.HealthChecker
	server        *http.Server
}

// NewHealthServer creates a new health server
func NewHealthServer(client client.Client, addr string) *HealthServer {
	healthChecker := health.NewHealthChecker(client, time.Minute*2)

	mux := http.NewServeMux()
	hs := &HealthServer{
		healthChecker: healthChecker,
		server: &http.Server{
			Addr:    addr,
			Handler: mux,
		},
	}

	// 엔드포인트 등록
	mux.HandleFunc("/health", hs.handleHealth)
	mux.HandleFunc("/health/live", hs.handleLiveness)
	mux.HandleFunc("/health/ready", hs.handleReadiness)
	mux.HandleFunc("/metrics/health", hs.handleHealthMetrics)

	return hs
}

// Start starts the health server
func (hs *HealthServer) Start(ctx context.Context) error {
	log := logf.FromContext(ctx)

	// 헬스체커 시작
	go hs.healthChecker.Start(ctx)

	log.Info("Starting health server", "addr", hs.server.Addr)

	// 서버 시작
	go func() {
		if err := hs.server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Error(err, "Health server failed")
		}
	}()

	// 컨텍스트 취소 시 서버 종료
	<-ctx.Done()

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	return hs.server.Shutdown(shutdownCtx)
}

// handleHealth returns overall system health
func (hs *HealthServer) handleHealth(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	status, err := hs.healthChecker.GetSystemHealth(ctx)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")

	if status.Status == "unhealthy" {
		w.WriteHeader(http.StatusServiceUnavailable)
	} else if status.Status == "degraded" {
		w.WriteHeader(http.StatusOK) // 또는 다른 상태 코드
	} else {
		w.WriteHeader(http.StatusOK)
	}

	json.NewEncoder(w).Encode(status)
}

// handleLiveness returns liveness probe response
func (hs *HealthServer) handleLiveness(w http.ResponseWriter, r *http.Request) {
	// 단순한 liveness 체크 (서버가 살아있으면 OK)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)

	response := map[string]interface{}{
		"status":    "alive",
		"timestamp": time.Now().Format(time.RFC3339),
	}

	json.NewEncoder(w).Encode(response)
}

// handleReadiness returns readiness probe response
func (hs *HealthServer) handleReadiness(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	// 시스템 준비 상태 확인
	status, err := hs.healthChecker.GetSystemHealth(ctx)
	if err != nil {
		http.Error(w, "Not ready", http.StatusServiceUnavailable)
		return
	}

	w.Header().Set("Content-Type", "application/json")

	if status.Status == "unhealthy" {
		w.WriteHeader(http.StatusServiceUnavailable)
		response := map[string]interface{}{
			"status":    "not_ready",
			"reason":    status.Message,
			"timestamp": time.Now().Format(time.RFC3339),
		}
		json.NewEncoder(w).Encode(response)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := map[string]interface{}{
		"status":    "ready",
		"timestamp": time.Now().Format(time.RFC3339),
	}

	json.NewEncoder(w).Encode(response)
}

// handleHealthMetrics returns detailed health metrics
func (hs *HealthServer) handleHealthMetrics(w http.ResponseWriter, r *http.Request) {
	// 상세한 헬스 메트릭 수집
	// 실제 구현에서는 더 자세한 메트릭을 제공

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)

	metrics := map[string]interface{}{
		"controller": map[string]interface{}{
			"uptime":         time.Since(time.Now()).String(), // 실제로는 시작 시간을 저장해야 함
			"last_reconcile": time.Now().Format(time.RFC3339),
		},
		"policies": map[string]interface{}{
			"total_active": 0, // 실제 값으로 대체
			"total_failed": 0,
		},
		"workloads": map[string]interface{}{
			"total_managed": 0,
			"healthy":       0,
			"degraded":      0,
		},
	}

	json.NewEncoder(w).Encode(metrics)
}
