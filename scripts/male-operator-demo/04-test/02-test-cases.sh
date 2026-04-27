#!/bin/bash
#
# MALE Paper 3가지 산업 사례 테스트
#
# Case 1: Autonomous Vehicles (A=0.6, L=0.3, E=0.1) → A → C
# Case 2: Real-Time Robotics (A=0.1, L=0.7, E=0.2) → A → B
# Case 3: IoT Sensors (A=0.2, L=0.1, E=0.7) → C → A
#

set -e

echo "============================================================"
echo " MALE MC Criticality 재정의 테스트"
echo "============================================================"
echo ""
echo "MALE Paper 기반 규칙:"
echo "  - L >= 0.9                → C (Safety-Critical)"
echo "  - L >= 0.7 && A >= 0.5    → C (Safety-Critical)"
echo "  - A >= 0.6 && L >= 0.3    → C (Autonomous Vehicles)"
echo "  - A + L >= 0.9            → C (Combined threshold)"
echo "  - L >= 0.5                → B (Mission-Critical)"
echo "  - E >= 0.5 && L < 0.5     → A (Energy-Critical)"
echo ""

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS_COUNT=0
FAIL_COUNT=0

# ============================================================
# 테스트 케이스 함수
# ============================================================
test_case() {
    local NAME=$1
    local DEPLOY_NAME=$2
    local A=$3
    local L=$4
    local E=$5
    local USER_CRIT=$6
    local EXPECTED_CRIT=$7

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "테스트: $NAME"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "[입력] importance: A=$A, L=$L, E=$E"
    echo "[입력] mcSpec.criticality: $USER_CRIT (사용자 지정)"
    echo "[예상] effectiveMcSpec.criticality: $EXPECTED_CRIT"
    echo ""

    # Deployment 생성
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $DEPLOY_NAME
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $DEPLOY_NAME
  template:
    metadata:
      labels:
        app: $DEPLOY_NAME
    spec:
      containers:
      - name: test
        image: nginx:alpine
        resources:
          requests:
            cpu: "50m"
            memory: "64Mi"
EOF

    # MaleWorkload 생성
    cat <<EOF | kubectl apply -f -
apiVersion: male.keti.dev/v1alpha1
kind: MaleWorkload
metadata:
  name: $NAME
  namespace: default
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: $DEPLOY_NAME
  mission: "$NAME-mission"
  importance:
    accuracy: $A
    latency: $L
    energy: $E
  mcSpec:
    criticality: "$USER_CRIT"
    rtPeriod: 100
    rtWcet: 30
  allowPolicyOverride: true
EOF

    # Operator 처리 대기
    echo "Operator 처리 대기 중..."
    sleep 3

    # 결과 확인
    ACTUAL_CRIT=$(kubectl get maleworkload $NAME -o jsonpath='{.status.effectiveMcSpec.criticality}' 2>/dev/null || echo "N/A")
    MISSION_TYPE=$(kubectl get maleworkload $NAME -o jsonpath='{.status.effectiveMcSpec.missionType}' 2>/dev/null || echo "N/A")
    OVERRIDE_REASON=$(kubectl get maleworkload $NAME -o jsonpath='{.status.effectiveMcSpec.overrideReason}' 2>/dev/null || echo "N/A")
    MIXED_SCORE=$(kubectl get maleworkload $NAME -o jsonpath='{.status.mixedScore}' 2>/dev/null || echo "N/A")

    echo ""
    echo "[출력] effectiveMcSpec:"
    echo "  criticality:    $ACTUAL_CRIT"
    echo "  missionType:    $MISSION_TYPE"
    echo "  overrideReason: $OVERRIDE_REASON"
    echo "  mixedScore:     $MIXED_SCORE"
    echo ""

    # 검증
    if [ "$ACTUAL_CRIT" == "$EXPECTED_CRIT" ]; then
        echo -e "${GREEN}[결과] ✓ PASS${NC}"
        ((PASS_COUNT++))
    else
        echo -e "${RED}[결과] ✗ FAIL (expected: $EXPECTED_CRIT, actual: $ACTUAL_CRIT)${NC}"
        ((FAIL_COUNT++))
    fi
    echo ""
}

# ============================================================
# 테스트 케이스 실행
# ============================================================

echo ""
echo "Case 1: Autonomous Vehicles (자율주행)"
echo "─────────────────────────────────────────────────────────"
test_case "test-autonomous-vehicle" "deploy-av" 0.6 0.3 0.1 "A" "C"

echo ""
echo "Case 2: Real-Time Robotics (실시간 로봇)"
echo "─────────────────────────────────────────────────────────"
test_case "test-realtime-robot" "deploy-robot" 0.1 0.7 0.2 "A" "B"

echo ""
echo "Case 3: IoT Sensor Networks (IoT 센서)"
echo "─────────────────────────────────────────────────────────"
test_case "test-iot-sensor" "deploy-iot" 0.2 0.1 0.7 "C" "A"

# ============================================================
# 결과 요약
# ============================================================
echo ""
echo "============================================================"
echo " 테스트 결과 요약"
echo "============================================================"
echo ""
echo -e "${GREEN}PASS: $PASS_COUNT${NC}"
echo -e "${RED}FAIL: $FAIL_COUNT${NC}"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}모든 테스트 통과!${NC}"
    exit 0
else
    echo -e "${RED}일부 테스트 실패${NC}"
    exit 1
fi
