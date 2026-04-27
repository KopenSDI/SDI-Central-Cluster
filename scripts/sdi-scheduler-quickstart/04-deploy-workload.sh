#!/bin/bash
# ==============================================================
# 04-deploy-workload.sh
# SDI 스케줄러 테스트 워크로드 배포
#
# kubectl 대상:
#   KL (로컬 클러스터) — 현재 알고리즘 확인 (Deployment env var)
#   KM (Karmada API)  — Namespace / PropagationPolicy / ResourceBinding
#
# 사용법:
#   ./04-deploy-workload.sh                       # 대화형 메뉴
#   ./04-deploy-workload.sh intent-driven
#   ./04-deploy-workload.sh collaborative-swarm
#   ./04-deploy-workload.sh predictive-context
#   ./04-deploy-workload.sh all                   # 세 가지 모두
# ==============================================================

set -euo pipefail

KARMADA_CFG="/etc/karmada/karmada-apiserver.config"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/manifests"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

ok()   { echo -e "${GREEN}  ✓ $*${NC}"; }
warn() { echo -e "${YELLOW}  ! $*${NC}"; }
err()  { echo -e "${RED}  ✗ $*${NC}"; exit 1; }
hdr()  { echo -e "\n${BLUE}━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

KL="kubectl"
KM="kubectl --kubeconfig=${KARMADA_CFG}"

# ────────────────────────────────────────────────────────────
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════╗"
echo "║       SDI Scheduler 테스트 워크로드 배포         ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

# 사전 확인
[ -f "${KARMADA_CFG}" ] || err "Karmada kubeconfig 없음: ${KARMADA_CFG}"
[ -d "${MANIFESTS_DIR}" ] || err "manifests 디렉토리 없음: ${MANIFESTS_DIR}"
${KM} get clusters &>/dev/null || err "Karmada API 연결 실패"

# 현재 알고리즘 (Deployment env var에서)
CURRENT_ALGO=$(${KL} get deployment sdi-scheduler -n karmada-system \
    -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="SDI_DEFAULT_ALGORITHM")].value}' \
    2>/dev/null || echo "intent-driven")
echo -e "  현재 기본 알고리즘: ${YELLOW}${CURRENT_ALGO}${NC}"

# ────────────────────────────────────────────────────────────
# 알고리즘 선택
# ────────────────────────────────────────────────────────────
normalize_algorithm() {
    case "$(echo "$1" | tr '[:upper:]' '[:lower:]' | tr '_' '-')" in
        "1"|"intent"|"intent-driven"|"intentdriven") echo "intent-driven" ;;
        "2"|"swarm"|"collaborative-swarm"|"collaborativeswarm") echo "collaborative-swarm" ;;
        "3"|"predict"|"predictive"|"predictive-context"|"predictivecontext") echo "predictive-context" ;;
        "all") echo "all" ;;
        *) echo "" ;;
    esac
}

if [ $# -ge 1 ]; then
    TARGET=$(normalize_algorithm "$1")
    [ -n "${TARGET}" ] || { echo -e "${RED}  ✗ 알 수 없는 알고리즘: $1${NC}"; exit 1; }
else
    hdr "배포할 워크로드 알고리즘 선택"
    echo ""
    echo -e "  ${CYAN}1) intent-driven${NC}       — 자율주행/AI 추론 (QoS 우선)"
    echo -e "  ${CYAN}2) collaborative-swarm${NC} — 분산 IoT/Web (로드밸런싱)"
    echo -e "  ${CYAN}3) predictive-context${NC}  — 터틀봇/드론 (에너지 예측)"
    echo -e "  ${CYAN}4) all${NC}                 — 세 가지 모두 배포"
    echo ""
    read -rp "  선택 (1-4 또는 이름): " CHOICE
    TARGET=$(normalize_algorithm "${CHOICE:-1}")
    [ -n "${TARGET}" ] || { echo -e "${RED}  ✗ 잘못된 입력: ${CHOICE}${NC}"; exit 1; }
fi

# ────────────────────────────────────────────────────────────
hdr "Karmada Namespace 생성"
# ────────────────────────────────────────────────────────────
${KM} apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: sdi-test
EOF
ok "Namespace sdi-test 준비"

# ────────────────────────────────────────────────────────────
deploy_manifest() {
    local algo="$1"
    local manifest="$2"
    local deployment_name="$3"

    hdr "워크로드 배포: ${algo}"
    echo "  파일: ${manifest}"

    [ -f "${manifest}" ] || err "매니페스트 파일 없음: ${manifest}"

    ${KM} apply -f "${manifest}"
    ok "매니페스트 적용 완료"

    echo ""
    echo "  ResourceBinding 스케줄링 대기..."
    for i in $(seq 1 20); do
        sleep 3
        BINDING=$(${KM} get resourcebinding -n sdi-test 2>/dev/null \
            | grep "${deployment_name}" | head -1 | awk '{print $1}')

        if [ -n "${BINDING}" ]; then
            CLUSTERS=$(${KM} get resourcebinding "${BINDING}" -n sdi-test \
                -o jsonpath='{.spec.clusters[*].name}' 2>/dev/null || echo "")
            if [ -n "${CLUSTERS}" ]; then
                echo ""
                ok "스케줄링 완료!"
                echo -e "  선택된 클러스터: ${GREEN}${CLUSTERS}${NC}"
                return 0
            fi
        fi
        echo -n "."
    done

    echo ""
    warn "스케줄링 결과 미확인. 직접 확인:"
    echo "  ${KM} get resourcebinding -n sdi-test"
    echo "  kubectl logs -n karmada-system -l app=sdi-scheduler --tail=30"
}

# ────────────────────────────────────────────────────────────
case "${TARGET}" in
    "intent-driven")
        deploy_manifest "intent-driven" \
            "${MANIFESTS_DIR}/01-workload-intent-driven.yaml" \
            "intent-test-workload"
        ;;
    "collaborative-swarm")
        deploy_manifest "collaborative-swarm" \
            "${MANIFESTS_DIR}/02-workload-swarm.yaml" \
            "swarm-test-workload"
        ;;
    "predictive-context")
        deploy_manifest "predictive-context" \
            "${MANIFESTS_DIR}/03-workload-predictive.yaml" \
            "predict-test-workload"
        ;;
    "all")
        deploy_manifest "intent-driven" \
            "${MANIFESTS_DIR}/01-workload-intent-driven.yaml" \
            "intent-test-workload"
        deploy_manifest "collaborative-swarm" \
            "${MANIFESTS_DIR}/02-workload-swarm.yaml" \
            "swarm-test-workload"
        deploy_manifest "predictive-context" \
            "${MANIFESTS_DIR}/03-workload-predictive.yaml" \
            "predict-test-workload"
        ;;
esac

# ────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}━━━ 배포 완료 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "전체 ResourceBinding 확인:"
echo "  ${KM} get resourcebinding -n sdi-test -o wide"
echo ""
echo "스케줄러 로그 (점수 상세):"
echo "  kubectl logs -n karmada-system -l app=sdi-scheduler --tail=50"
echo ""
echo "클러스터 라벨 확인 (predictive 알고리즘 입력값):"
echo "  ${KM} get clusters --show-labels"
echo ""
echo "정리:"
echo "  ./05-cleanup.sh"
