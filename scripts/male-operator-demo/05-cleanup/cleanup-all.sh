#!/bin/bash
#
# 전체 정리 스크립트
#
# 모든 MALE-Operator 관련 리소스를 삭제합니다:
# - MaleWorkload
# - MalePolicy
# - Operator Deployment
# - CRD (선택)
#

set -e

echo "============================================================"
echo " MALE-Operator 전체 정리"
echo "============================================================"
echo ""
echo "⚠️  주의: 이 스크립트는 모든 MALE 관련 리소스를 삭제합니다."
echo ""

# 확인
read -p "계속하시겠습니까? (y/N) " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "취소됨."
    exit 0
fi

echo ""

# 1. MaleWorkload 삭제
echo "[1/5] MaleWorkload 삭제 중..."
kubectl delete maleworkload --all -A 2>/dev/null || true

# 2. MalePolicy 삭제
echo "[2/5] MalePolicy 삭제 중..."
kubectl delete malepolicy --all 2>/dev/null || true

# 3. 테스트 Deployment 삭제
echo "[3/5] 테스트 Deployment 삭제 중..."
kubectl delete deployment -l male.keti.dev/workload -A 2>/dev/null || true
kubectl delete deployment deploy-av deploy-robot deploy-iot -n default 2>/dev/null || true
kubectl delete deployment autonomous-vehicle-perception realtime-robot-controller iot-sensor-collector -n default 2>/dev/null || true

# 4. Operator 삭제
echo "[4/5] Operator 삭제 중..."
PROJECT_ROOT="/root/KETI_SDI_Central_Cluster"
MALE_OPERATOR_DIR="$PROJECT_ROOT/deploy/SDI/male-operator"

if [ -d "$MALE_OPERATOR_DIR/config/manager" ]; then
    kubectl delete -f "$MALE_OPERATOR_DIR/config/manager/" 2>/dev/null || true
fi

# male-system 네임스페이스 내용 삭제
kubectl delete all --all -n male-system 2>/dev/null || true

# 5. CRD 삭제 (선택)
echo ""
read -p "CRD도 삭제하시겠습니까? (y/N) " confirm_crd
if [[ "$confirm_crd" =~ ^[Yy]$ ]]; then
    echo "[5/5] CRD 삭제 중..."
    kubectl delete crd maleworkloads.male.keti.dev 2>/dev/null || true
    kubectl delete crd malepolicies.male.keti.dev 2>/dev/null || true
else
    echo "[5/5] CRD 유지"
fi

echo ""
echo "============================================================"
echo " 정리 완료"
echo "============================================================"
echo ""
echo "남아있는 CRD:"
kubectl get crd | grep male 2>/dev/null || echo "  (없음)"
echo ""
echo "남아있는 male-system 네임스페이스 리소스:"
kubectl get all -n male-system 2>/dev/null || echo "  (없음)"
echo ""
