#!/bin/bash
#
# 테스트 워크로드만 정리 (Operator와 CRD는 유지)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

echo "============================================================"
echo " 테스트 워크로드 정리 (Operator 유지)"
echo "============================================================"
echo ""

# MaleWorkloads 삭제
echo "[1/2] MaleWorkloads 삭제..."
kubectl delete maleworkloads --all -n male-test --ignore-not-found=true 2>/dev/null || true
echo "✓ MaleWorkloads 삭제 완료"
echo ""

# Deployments 삭제
echo "[2/2] Deployments 삭제..."
kubectl delete deployments --all -n male-test --ignore-not-found=true 2>/dev/null || true
echo "✓ Deployments 삭제 완료"
echo ""

echo "============================================================"
echo " 정리 완료"
echo "============================================================"
echo ""
echo "Operator 상태:"
kubectl get pods -n male-system -l control-plane=controller-manager
echo ""
echo "재배포: kubectl apply -f $BASE_DIR/03-test-workloads/"
