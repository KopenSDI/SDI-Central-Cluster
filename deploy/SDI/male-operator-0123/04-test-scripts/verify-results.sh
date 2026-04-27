#!/bin/bash
#
# MC Criticality 재정의 결과 검증 스크립트
#

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "============================================================"
echo " MALE MC Criticality 재정의 결과 검증"
echo "============================================================"
echo ""

PASS_COUNT=0
FAIL_COUNT=0

# 테스트 케이스 검증 함수
verify_case() {
    local NAME=$1
    local EXPECTED_CRIT=$2
    local DESCRIPTION=$3

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}테스트: $DESCRIPTION${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 값 조회
    USER_CRIT=$(kubectl get maleworkload $NAME -n male-test -o jsonpath='{.spec.mcSpec.criticality}' 2>/dev/null || echo "N/A")
    ACTUAL_CRIT=$(kubectl get maleworkload $NAME -n male-test -o jsonpath='{.status.effectiveMcSpec.criticality}' 2>/dev/null || echo "N/A")
    MISSION_TYPE=$(kubectl get maleworkload $NAME -n male-test -o jsonpath='{.status.effectiveMcSpec.missionType}' 2>/dev/null || echo "N/A")
    OVERRIDE_REASON=$(kubectl get maleworkload $NAME -n male-test -o jsonpath='{.status.effectiveMcSpec.overrideReason}' 2>/dev/null || echo "N/A")
    MIXED_SCORE=$(kubectl get maleworkload $NAME -n male-test -o jsonpath='{.status.mixedScore}' 2>/dev/null || echo "N/A")

    A=$(kubectl get maleworkload $NAME -n male-test -o jsonpath='{.spec.importance.accuracy}' 2>/dev/null || echo "N/A")
    L=$(kubectl get maleworkload $NAME -n male-test -o jsonpath='{.spec.importance.latency}' 2>/dev/null || echo "N/A")
    E=$(kubectl get maleworkload $NAME -n male-test -o jsonpath='{.spec.importance.energy}' 2>/dev/null || echo "N/A")

    echo ""
    echo "[입력]"
    echo "  importance: A=$A, L=$L, E=$E"
    echo "  mcSpec.criticality: $USER_CRIT (사용자 지정)"
    echo ""
    echo "[출력]"
    echo "  effectiveMcSpec.criticality: $ACTUAL_CRIT"
    echo "  missionType: $MISSION_TYPE"
    echo "  overrideReason: $OVERRIDE_REASON"
    echo "  mixedScore: $MIXED_SCORE"
    echo ""

    # 검증
    if [ "$ACTUAL_CRIT" == "$EXPECTED_CRIT" ]; then
        echo -e "${GREEN}[결과] ✓ PASS${NC} (expected: $EXPECTED_CRIT, actual: $ACTUAL_CRIT)"
        ((PASS_COUNT++))
    else
        echo -e "${RED}[결과] ✗ FAIL${NC} (expected: $EXPECTED_CRIT, actual: $ACTUAL_CRIT)"
        ((FAIL_COUNT++))
    fi

    # 재정의 확인
    if [ "$USER_CRIT" != "$ACTUAL_CRIT" ]; then
        echo -e "${YELLOW}  ⚠ Criticality 재정의됨: $USER_CRIT → $ACTUAL_CRIT${NC}"
    fi
    echo ""
}

# 테스트 케이스 실행
echo ""
verify_case "autonomous-vehicle" "C" "Case 1: Autonomous Vehicles (자율주행)"
verify_case "realtime-robot" "B" "Case 2: Real-Time Robotics (실시간 로봇)"
verify_case "iot-sensor" "A" "Case 3: IoT Sensor Networks (IoT 센서)"

# 결과 요약
echo "============================================================"
echo " 테스트 결과 요약"
echo "============================================================"
echo ""
echo -e "${GREEN}PASS: $PASS_COUNT${NC}"
echo -e "${RED}FAIL: $FAIL_COUNT${NC}"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN} 모든 테스트 통과! MC Criticality 재정의 정상 동작${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    exit 0
else
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED} 일부 테스트 실패! 로그 확인 필요${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Operator 로그 확인:"
    echo "  kubectl logs -n male-system -l control-plane=controller-manager"
    exit 1
fi
