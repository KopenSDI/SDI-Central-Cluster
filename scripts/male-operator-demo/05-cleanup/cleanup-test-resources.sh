#!/bin/bash
#
# 테스트 리소스 정리 스크립트
#
# 테스트 중 생성된 MaleWorkload와 Deployment를 삭제합니다.
# Operator와 CRD는 유지됩니다.
#

set -e

echo "============================================================"
echo " 테스트 리소스 정리"
echo "============================================================"
echo ""

# MaleWorkload 삭제
echo "[1/2] MaleWorkload 삭제 중..."
kubectl delete maleworkload --all -n default 2>/dev/null || true

# 테스트 Deployment 삭제
echo "[2/2] 테스트 Deployment 삭제 중..."
kubectl delete deployment -l app=deploy-av -n default 2>/dev/null || true
kubectl delete deployment -l app=deploy-robot -n default 2>/dev/null || true
kubectl delete deployment -l app=deploy-iot -n default 2>/dev/null || true

# 예제 파일에서 생성된 리소스 삭제
kubectl delete deployment autonomous-vehicle-perception -n default 2>/dev/null || true
kubectl delete deployment realtime-robot-controller -n default 2>/dev/null || true
kubectl delete deployment iot-sensor-collector -n default 2>/dev/null || true

# 테스트 케이스에서 생성된 Deployment 삭제
kubectl delete deployment deploy-av deploy-robot deploy-iot -n default 2>/dev/null || true

echo ""
echo "============================================================"
echo " 정리 완료"
echo "============================================================"
echo ""
echo "남아있는 리소스 확인:"
echo ""
echo "MaleWorkload:"
kubectl get maleworkload -A 2>/dev/null || echo "  (없음)"
echo ""
echo "Deployments in default namespace:"
kubectl get deployment -n default 2>/dev/null || echo "  (없음)"
echo ""
