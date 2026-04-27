#!/bin/bash
#
# 전체 통합 테스트 스크립트
#
# 테스트 흐름:
# 1. Central에 MaleWorkload + Deployment 생성
# 2. MALE-Operator가 MC Criticality 재정의 확인
# 3. Karmada로 Edge 클러스터에 전파
# 4. Edge에서 워크로드 실행 확인
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
EDGE_KUBECONFIG="/root/KETI_SDI_Central_Cluster/scripts/etri-setup/karmada/edge-cluster-kubeconfig.yaml"
KARMADA_KUBECONFIG="/etc/karmada/karmada-apiserver.config"

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "============================================================"
echo " MALE-Operator 전체 통합 테스트"
echo "============================================================"
echo ""

# ============================================================
# Step 0: 사전 확인
# ============================================================
echo -e "${BLUE}[Step 0] 사전 확인${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Karmada 연결 확인
echo -n "Karmada 클러스터 확인... "
if kubectl --kubeconfig=$KARMADA_KUBECONFIG get clusters 2>/dev/null | grep -q "edge-cluster"; then
    echo -e "${GREEN}OK${NC} (edge-cluster 연결됨)"
else
    echo -e "${RED}FAIL${NC}"
    exit 1
fi

# MALE Operator 확인
echo -n "MALE-Operator 확인... "
if kubectl get pods -n male-operator-system -l control-plane=controller-manager 2>/dev/null | grep -q "Running"; then
    echo -e "${GREEN}OK${NC} (Running)"
else
    echo -e "${RED}FAIL${NC} (Operator not running)"
    exit 1
fi

# Edge kubeconfig 확인
echo -n "Edge kubeconfig 확인... "
if [ -f "$EDGE_KUBECONFIG" ]; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAIL${NC} ($EDGE_KUBECONFIG not found)"
    exit 1
fi
echo ""

# ============================================================
# Step 1: 기존 리소스 정리
# ============================================================
echo -e "${BLUE}[Step 1] 기존 리소스 정리${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kubectl delete maleworkloads --all -n male-test 2>/dev/null || true
kubectl delete deployments --all -n male-test 2>/dev/null || true
kubectl --kubeconfig=$KARMADA_KUBECONFIG delete deployments --all -n male-test 2>/dev/null || true
kubectl --kubeconfig=$KARMADA_KUBECONFIG delete propagationpolicy --all -n male-test 2>/dev/null || true
echo "✓ 정리 완료"
echo ""
sleep 2

# ============================================================
# Step 2: Central에 Deployment + MaleWorkload 생성
# ============================================================
echo -e "${BLUE}[Step 2] Central에 워크로드 생성${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Namespace 확인/생성
kubectl create namespace male-test 2>/dev/null || true

# 테스트 워크로드 배포
kubectl apply -f "$BASE_DIR/03-test-workloads/01-autonomous-vehicle.yaml"
kubectl apply -f "$BASE_DIR/03-test-workloads/02-realtime-robot.yaml"
kubectl apply -f "$BASE_DIR/03-test-workloads/03-iot-sensor.yaml"
echo "✓ 워크로드 생성 완료"
echo ""

# Operator 처리 대기
echo "MALE-Operator 처리 대기 (5초)..."
sleep 5

# ============================================================
# Step 3: MC Criticality 재정의 확인
# ============================================================
echo -e "${BLUE}[Step 3] MC Criticality 재정의 확인${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

PASS=0
FAIL=0

check_criticality() {
    local NAME=$1
    local EXPECTED=$2

    ACTUAL=$(kubectl get maleworkload $NAME -n male-test -o jsonpath='{.status.effectiveMcSpec.criticality}' 2>/dev/null)
    USER=$(kubectl get maleworkload $NAME -n male-test -o jsonpath='{.spec.mcSpec.criticality}' 2>/dev/null)

    if [ "$ACTUAL" == "$EXPECTED" ]; then
        echo -e "  $NAME: ${GREEN}✓ PASS${NC} (User: $USER → Effective: $ACTUAL)"
        PASS=$((PASS+1))
    else
        echo -e "  $NAME: ${RED}✗ FAIL${NC} (Expected: $EXPECTED, Got: $ACTUAL)"
        FAIL=$((FAIL+1))
    fi
}

check_criticality "autonomous-vehicle" "C"
check_criticality "realtime-robot" "B"
check_criticality "iot-sensor" "A"

echo ""
echo "  MC 재정의 결과: $PASS/3 통과"
echo ""

# ============================================================
# Step 4: Karmada로 Edge 전파
# ============================================================
echo -e "${BLUE}[Step 4] Karmada로 Edge 클러스터 전파${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Karmada namespace 생성
kubectl --kubeconfig=$KARMADA_KUBECONFIG create namespace male-test 2>/dev/null || true

# PropagationPolicy 적용
kubectl --kubeconfig=$KARMADA_KUBECONFIG apply -f "$BASE_DIR/03-test-workloads/00-propagation-policy.yaml"

# Karmada에 Deployment 생성 (Edge 전파용)
for wl in autonomous-vehicle realtime-robot iot-sensor; do
    # Central에서 Deployment 정보 가져와서 Karmada에 적용
    kubectl get deployment $wl -n male-test -o yaml | \
        grep -v "resourceVersion\|uid\|creationTimestamp\|generation\|selfLink" | \
        kubectl --kubeconfig=$KARMADA_KUBECONFIG apply -f - 2>/dev/null || true
done

echo "✓ Karmada 전파 설정 완료"
echo ""

# 전파 대기
echo "Edge 클러스터 전파 대기 (10초)..."
sleep 10

# ============================================================
# Step 5: Edge 클러스터 확인
# ============================================================
echo -e "${BLUE}[Step 5] Edge 클러스터 확인${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "Edge 클러스터 (10.0.0.39) Pods:"
kubectl --kubeconfig=$EDGE_KUBECONFIG get pods -n male-test -o wide 2>/dev/null || echo "  (male-test namespace not found)"
echo ""

# ============================================================
# 결과 요약
# ============================================================
echo "============================================================"
echo " 테스트 결과 요약"
echo "============================================================"
echo ""
echo -e "MC Criticality 재정의: ${GREEN}$PASS${NC}/${RED}$((PASS+FAIL))${NC}"
echo ""

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN} 테스트 성공!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
else
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED} 일부 테스트 실패${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
fi
echo ""
echo "상세 확인: ./show-status.sh"
