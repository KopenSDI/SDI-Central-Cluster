#!/bin/bash
# Federation Receiver 배포 스크립트
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=============================================="
echo "Federation Receiver Kubernetes 배포"
echo "=============================================="

# tbot-monitoring 네임스페이스 확인
echo "[1/3] 네임스페이스 확인..."
kubectl get namespace tbot-monitoring &>/dev/null || {
    echo "tbot-monitoring 네임스페이스가 없습니다."
    echo "먼저 Metric-Collector를 배포하세요:"
    echo "  kubectl apply -f ../../../SDI-Orchestration/Metric-Collector/Metric-Collector-deploy.yaml"
    exit 1
}

# InfluxDB 상태 확인
echo "[2/3] InfluxDB 상태 확인..."
kubectl get deployment influxdb -n tbot-monitoring &>/dev/null || \
kubectl get statefulset influxdb -n tbot-monitoring &>/dev/null || {
    echo "경고: InfluxDB가 배포되지 않았습니다."
    echo "Federation Receiver는 InfluxDB에 메트릭을 저장합니다."
}

# 기존 배포 삭제 (있으면)
echo "[3/3] Federation Receiver 배포..."
kubectl delete deployment federation-receiver -n tbot-monitoring 2>/dev/null || true
kubectl delete service federation-receiver -n tbot-monitoring 2>/dev/null || true
kubectl delete service federation-receiver-internal -n tbot-monitoring 2>/dev/null || true

# 새로 배포
kubectl apply -f federation-receiver-deploy.yaml

echo ""
echo "=============================================="
echo "배포 완료"
echo "=============================================="

# 상태 확인 대기
echo ""
echo "Pod 상태 확인 중..."
sleep 3
kubectl get pods -n tbot-monitoring -l app=federation-receiver -o wide

echo ""
echo "서비스 정보:"
kubectl get svc -n tbot-monitoring -l app=federation-receiver

echo ""
echo "=============================================="
echo "Federation Receiver 엔드포인트:"
echo "  - 내부: http://federation-receiver.tbot-monitoring.svc.cluster.local:8080"
echo "  - 외부: http://<NODE_IP>:30080"
echo ""
echo "Edge Cluster에서 메트릭 전송:"
echo "  POST http://<CENTRAL_CLUSTER_IP>:30080/api/v1/federation/metrics"
echo "=============================================="
