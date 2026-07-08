#!/bin/bash
#
# MALE-Operator 테스트 전 필수 리소스 배포
#
# 이 스크립트는 다음을 배포합니다:
# 1. MalePolicy CRD 및 인스턴스
# 2. MALE-Operator (이미 배포되어 있으면 스킵)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="/root/KETI_SDI_Central_Cluster"
MALE_OPERATOR_DIR="$PROJECT_ROOT/deploy/SDI/male-operator"

echo "============================================================"
echo " Step 1: CRD 설치"
echo "============================================================"

# CRD 적용
kubectl apply -f "$MALE_OPERATOR_DIR/config/crd/bases/"

echo ""
echo "CRD 설치 완료"
kubectl get crd | grep male

echo ""
echo "============================================================"
echo " Step 2: MalePolicy 생성"
echo "============================================================"

cat <<EOF | kubectl apply -f -
apiVersion: male.keti.dev/v1alpha1
kind: MalePolicy
metadata:
  name: default-male-policy
spec:
  weights:
    accuracy: 0.4
    latency: 0.4
    energy: 0.2
  bounds:
    accuracy:
      min: 0.0
      max: 1.0
    latency:
      min: 0.0
      max: 1.0
    energy:
      min: 0.0
      max: 1.0
  priorityBuckets:
    - name: male-critical
      min: 0.8
      max: 1.0
    - name: male-high
      min: 0.5
      max: 0.8
    - name: male-medium
      min: 0.2
      max: 0.5
    - name: male-low
      min: 0.0
      max: 0.2
  override:
    enabled: false
    source:
      type: ConfigMap
      namespace: male-system
      name: male-policy-overrides
EOF

echo ""
echo "MalePolicy 생성 완료"
kubectl get malepolicy

echo ""
echo "============================================================"
echo " Step 3: Operator 배포 확인"
echo "============================================================"

# Operator 파드 확인
if kubectl get pods -n male-system -l control-plane=controller-manager 2>/dev/null | grep -q Running; then
    echo "MALE-Operator가 이미 실행 중입니다"
else
    echo "MALE-Operator 배포 중..."
    kubectl apply -f "$MALE_OPERATOR_DIR/config/manager/"

    echo "Operator 시작 대기 중..."
    kubectl wait --for=condition=Available deployment/male-controller-manager -n male-system --timeout=120s
fi

kubectl get pods -n male-system

echo ""
echo "============================================================"
echo " Prerequisites 배포 완료!"
echo "============================================================"
echo ""
echo "다음 단계: ./02-test-cases.sh 실행"
