#!/bin/bash
# ==============================================================
# 03-switch-algorithm.sh
# SDI 스케줄러 기본 알고리즘 전환
#
# kubectl 대상:
#   KL (로컬 클러스터) — Deployment env var 업데이트
#
# 사용법:
#   ./03-switch-algorithm.sh                     # 대화형 메뉴
#   ./03-switch-algorithm.sh intent-driven
#   ./03-switch-algorithm.sh collaborative-swarm
#   ./03-switch-algorithm.sh predictive-context
#
# 참고:
#   기본 알고리즘 = Deployment spec의 SDI_DEFAULT_ALGORITHM env var
#   워크로드별 개별 지정은 PropagationPolicy affinityName으로 따로 가능
# ==============================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

ok()   { echo -e "${GREEN}  ✓ $*${NC}"; }
warn() { echo -e "${YELLOW}  ! $*${NC}"; }
hdr()  { echo -e "\n${BLUE}━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# 스케줄러 Deployment는 로컬 클러스터에 있음
KL="kubectl"

print_algorithms() {
    echo ""
    echo -e "  ${CYAN}1) intent-driven${NC}       — 지연시간/정확도/에너지 멀티목적 최적화"
    echo    "                          (자율주행, 실시간 AI 추론 등 QoS가 중요한 경우)"
    echo ""
    echo -e "  ${CYAN}2) collaborative-swarm${NC} — PSO 기반 크로스클러스터 로드밸런싱"
    echo    "                          (지역 친화성, 분산 배포가 중요한 경우)"
    echo ""
    echo -e "  ${CYAN}3) predictive-context${NC}  — 시계열 예측 기반 선제적 스케줄링"
    echo    "                          (IoT 엣지, 배터리 기기, 에너지 제약 환경)"
    echo ""
}

normalize_algorithm() {
    case "$(echo "$1" | tr '[:upper:]' '[:lower:]' | tr '_' '-')" in
        "1"|"intent"|"intent-driven"|"intentdriven")
            echo "intent-driven" ;;
        "2"|"swarm"|"collaborative-swarm"|"collaborativeswarm")
            echo "collaborative-swarm" ;;
        "3"|"predict"|"predictive"|"predictive-context"|"predictivecontext")
            echo "predictive-context" ;;
        *)
            echo "" ;;
    esac
}

# ────────────────────────────────────────────────────────────
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════╗"
echo "║       SDI Scheduler 알고리즘 전환                ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

# 스케줄러 존재 확인
${KL} get deployment sdi-scheduler -n karmada-system &>/dev/null \
    || { echo -e "${RED}  ✗ sdi-scheduler Deployment 없음 — 먼저 02-deploy-sdi-scheduler.sh 실행${NC}"; exit 1; }

# 현재 알고리즘: Deployment env var에서 읽기
CURRENT=$(${KL} get deployment sdi-scheduler -n karmada-system \
    -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="SDI_DEFAULT_ALGORITHM")].value}' \
    2>/dev/null || echo "not-set")
echo -e "  현재 기본 알고리즘: ${YELLOW}${CURRENT}${NC}"

# ────────────────────────────────────────────────────────────
if [ $# -ge 1 ]; then
    TARGET=$(normalize_algorithm "$1")
    if [ -z "${TARGET}" ]; then
        echo -e "${RED}  ✗ 알 수 없는 알고리즘: $1${NC}"
        print_algorithms
        exit 1
    fi
else
    hdr "알고리즘 선택"
    print_algorithms
    read -rp "  선택 (1/2/3 또는 이름 입력): " CHOICE
    TARGET=$(normalize_algorithm "${CHOICE}")
    if [ -z "${TARGET}" ]; then
        echo -e "${RED}  ✗ 잘못된 입력: ${CHOICE}${NC}"
        exit 1
    fi
fi

if [ "${TARGET}" == "${CURRENT}" ]; then
    ok "이미 ${TARGET} 사용 중 — 변경 없음"
    exit 0
fi

# ────────────────────────────────────────────────────────────
hdr "Deployment env var 업데이트: ${CURRENT} → ${TARGET}"
# ────────────────────────────────────────────────────────────
# kubectl set env은 Deployment를 patch하고 롤링 재시작을 트리거함
${KL} set env deployment/sdi-scheduler \
    -n karmada-system \
    "SDI_DEFAULT_ALGORITHM=${TARGET}"
ok "env var 업데이트 완료 (롤링 재시작 시작)"

# ────────────────────────────────────────────────────────────
hdr "스케줄러 Pod 재시작 대기"
# ────────────────────────────────────────────────────────────
echo -n "  대기 중"
for i in $(seq 1 30); do
    sleep 2
    READY=$(${KL} get deployment sdi-scheduler -n karmada-system \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [ "${READY}" == "1" ]; then
        echo ""
        ok "재시작 완료"
        break
    fi
    echo -n "."
done

VERIFIED=$(${KL} get deployment sdi-scheduler -n karmada-system \
    -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="SDI_DEFAULT_ALGORITHM")].value}' \
    2>/dev/null)

# ────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}━━━ 전환 완료 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  기본 알고리즘: ${YELLOW}${CURRENT}${NC} → ${GREEN}${VERIFIED}${NC}"
echo ""
echo -e "${BLUE}  ─── 알고리즘별 특징 ───────────────────────────────${NC}"
case "${TARGET}" in
    "intent-driven")
        echo "  스코어 공식: S = (wL×latencyScore + wA×accuracyScore + wE×energyScore) / totalW × 1000"
        echo "  기본 가중치: Latency=0.4, Accuracy=0.4, Energy=0.2"
        echo "  필터 조건:   200% CPU overcommit 허용, ultra-low latency는 엣지만"
        ;;
    "collaborative-swarm")
        echo "  스코어 공식: fitness = wLoad×loadFit + wAffinity×affinityFit + 0.2×energyFit + 0.1×√capacity"
        echo "  최적 부하율: 30% (너무 비어있어도, 너무 차있어도 감점)"
        echo "  필터 조건:   Healthy 체크, collaboration group 필터"
        ;;
    "predictive-context")
        echo "  스코어 공식: S = (0.2×current + 0.35×predicted + 0.2×power + 0.15×stability + 0.1×battery) × confidence"
        echo "  예측 방식:   클러스터 라벨의 pred-* 값 우선, 없으면 trend 기반 추정"
        echo "  필터 조건:   파워 예산 초과시 거부, 배터리 threshold (mobile 타입만)"
        ;;
esac
echo ""
echo "워크로드 배포:"
echo "  ./04-deploy-workload.sh                    # 기본 알고리즘(${TARGET}) 사용"
echo "  ./04-deploy-workload.sh intent-driven      # 이 워크로드만 intent-driven"
