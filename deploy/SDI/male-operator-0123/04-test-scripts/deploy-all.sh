#!/bin/bash
#
# 전체 배포 스크립트
# CRD + Policy + Operator + Test Workloads 순서대로 배포
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

echo "============================================================"
echo " MALE-Operator 전체 배포"
echo "============================================================"
echo ""
echo "Base Directory: $BASE_DIR"
echo ""

# Step 1: Prerequisites (CRD, Namespace, Policy)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[Step 1/4] Prerequisites 배포 (CRD, Namespace, Policy)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kubectl apply -f "$BASE_DIR/01-prerequisites/"
echo "✓ Prerequisites 배포 완료"
echo ""

# Wait for CRD to be established
echo "CRD 등록 대기 중..."
sleep 3
kubectl wait --for=condition=Established crd/maleworkloads.male.keti.dev --timeout=30s
kubectl wait --for=condition=Established crd/malepolicies.male.keti.dev --timeout=30s
echo "✓ CRD 등록 완료"
echo ""

# Step 2: Operator
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[Step 2/4] MALE-Operator 배포"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kubectl apply -f "$BASE_DIR/02-operator/"
echo ""

echo "Operator Pod 시작 대기 중..."
sleep 5
kubectl wait --for=condition=Available deployment/male-controller-manager -n male-system --timeout=120s
echo "✓ Operator 배포 완료"
echo ""

# Show operator status
echo "Operator 상태:"
kubectl get pods -n male-system -l control-plane=controller-manager
echo ""

# Step 3: Test Workloads
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[Step 3/4] 테스트 워크로드 배포"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kubectl apply -f "$BASE_DIR/03-test-workloads/"
echo "✓ 테스트 워크로드 배포 완료"
echo ""

# Wait for operator to process
echo "Operator 처리 대기 중 (5초)..."
sleep 5

# Step 4: Verify
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[Step 4/4] 배포 결과 확인"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "MalePolicy:"
kubectl get malepolicy
echo ""

echo "MaleWorkloads:"
kubectl get maleworkloads -n male-test
echo ""

echo "Deployments:"
kubectl get deployments -n male-test
echo ""

echo "============================================================"
echo " 배포 완료!"
echo "============================================================"
echo ""
echo "결과 확인: ./verify-results.sh"
echo "정리:      ../05-cleanup/cleanup-all.sh"
