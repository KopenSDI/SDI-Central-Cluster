#!/bin/bash
#
# 전체 정리 스크립트
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

echo "============================================================"
echo " MALE-Operator 전체 정리"
echo "============================================================"
echo ""

# Step 1: Test Workloads 삭제
echo "[Step 1/4] 테스트 워크로드 삭제..."
kubectl delete -f "$BASE_DIR/03-test-workloads/" --ignore-not-found=true 2>/dev/null || true
echo "✓ 테스트 워크로드 삭제 완료"
echo ""

# Step 2: Operator 삭제
echo "[Step 2/4] Operator 삭제..."
kubectl delete -f "$BASE_DIR/02-operator/" --ignore-not-found=true 2>/dev/null || true
echo "✓ Operator 삭제 완료"
echo ""

# Step 3: MalePolicy 삭제
echo "[Step 3/4] MalePolicy 삭제..."
kubectl delete malepolicy --all --ignore-not-found=true 2>/dev/null || true
echo "✓ MalePolicy 삭제 완료"
echo ""

# Step 4: CRD 및 Namespace 삭제
echo "[Step 4/4] CRD 및 Namespace 삭제..."
kubectl delete namespace male-test --ignore-not-found=true 2>/dev/null || true
kubectl delete namespace male-system --ignore-not-found=true 2>/dev/null || true

# CRD 삭제 확인
read -p "CRD도 삭제하시겠습니까? (y/N) " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    kubectl delete crd maleworkloads.male.keti.dev --ignore-not-found=true 2>/dev/null || true
    kubectl delete crd malepolicies.male.keti.dev --ignore-not-found=true 2>/dev/null || true
    echo "✓ CRD 삭제 완료"
else
    echo "✓ CRD 유지됨"
fi
echo ""

echo "============================================================"
echo " 정리 완료"
echo "============================================================"
echo ""

# 남은 리소스 확인
echo "남은 CRD:"
kubectl get crd | grep male 2>/dev/null || echo "  (없음)"
echo ""

echo "남은 Namespace:"
kubectl get ns | grep -E "male-system|male-test" 2>/dev/null || echo "  (없음)"
echo ""
