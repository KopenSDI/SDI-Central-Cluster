#!/bin/bash
# ==============================================================
# 01-check-status.sh
# SDI 스케줄러 환경 상태 확인
#
# kubectl 대상:
#   KL (로컬 클러스터) — 스케줄러 Deployment / ConfigMap
#   KM (Karmada API)  — clusters / PropagationPolicy / ResourceBinding
# ==============================================================

set -euo pipefail

KARMADA_CFG="/etc/karmada/karmada-apiserver.config"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

ok()   { echo -e "${GREEN}  ✓ $*${NC}"; }
warn() { echo -e "${YELLOW}  ! $*${NC}"; }
fail() { echo -e "${RED}  ✗ $*${NC}"; }
hdr()  { echo -e "\n${BLUE}━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

KL="kubectl"
KM="kubectl --kubeconfig=${KARMADA_CFG}"

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════╗"
echo "║       SDI Scheduler 환경 상태 확인               ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

# ────────────────────────────────────────────────────────────
hdr "1. 로컬 클러스터 (스케줄러 실행 위치)"
# ────────────────────────────────────────────────────────────
if ${KL} get nodes &>/dev/null; then
    ok "로컬 클러스터 연결 정상"
    ${KL} get nodes --no-headers | awk '{printf "    %-30s %s\n", $1, $2}'
else
    fail "로컬 클러스터 연결 실패"
    exit 1
fi

# ────────────────────────────────────────────────────────────
hdr "2. Karmada API 서버"
# ────────────────────────────────────────────────────────────
if [ ! -f "${KARMADA_CFG}" ]; then
    fail "Karmada kubeconfig 없음: ${KARMADA_CFG}"
    exit 1
fi

if ${KM} get clusters &>/dev/null; then
    ok "Karmada API 연결 정상"
else
    fail "Karmada API 연결 실패"
    exit 1
fi

# ────────────────────────────────────────────────────────────
hdr "3. SDI Scheduler Pod (로컬 클러스터 karmada-system)"
# ────────────────────────────────────────────────────────────
POD_STATUS=$(${KL} get pods -n karmada-system -l app=sdi-scheduler \
    --no-headers 2>/dev/null | head -1)

if [ -n "${POD_STATUS}" ]; then
    ok "SDI Scheduler 실행 중"
    echo "    ${POD_STATUS}"

    # 현재 알고리즘: deployment spec.template.spec.containers[].env 우선
    ALGO=$(${KL} get deployment sdi-scheduler -n karmada-system \
        -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="SDI_DEFAULT_ALGORITHM")].value}' \
        2>/dev/null || echo "")
    # 없으면 ConfigMap에서
    if [ -z "${ALGO}" ]; then
        ALGO=$(${KL} get configmap sdi-scheduler-env -n karmada-system \
            -o jsonpath='{.data.SDI_DEFAULT_ALGORITHM}' 2>/dev/null || echo "not-set")
    fi
    echo -e "    기본 알고리즘: ${YELLOW}${ALGO:-not-set}${NC}"

    IMAGE=$(${KL} get deployment sdi-scheduler -n karmada-system \
        -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "unknown")
    echo "    이미지: ${IMAGE}"
else
    warn "SDI Scheduler Pod 없음 — 02-deploy-sdi-scheduler.sh 실행 필요"
fi

# ────────────────────────────────────────────────────────────
hdr "4. sdi-scheduler-env ConfigMap"
# ────────────────────────────────────────────────────────────
if ${KL} get configmap sdi-scheduler-env -n karmada-system &>/dev/null; then
    ok "ConfigMap 존재"
    ${KL} get configmap sdi-scheduler-env -n karmada-system \
        -o go-template='{{range $k,$v := .data}}    {{$k}} = {{$v}}{{"\n"}}{{end}}' 2>/dev/null
else
    warn "ConfigMap 없음"
fi

# ────────────────────────────────────────────────────────────
hdr "5. Karmada Member Clusters"
# ────────────────────────────────────────────────────────────
${KM} get clusters -o wide 2>/dev/null || warn "클러스터 없음"

# ────────────────────────────────────────────────────────────
hdr "6. 클러스터 SDI 라벨 (스케줄러 입력값)"
# ────────────────────────────────────────────────────────────
CLUSTERS=$(${KM} get clusters -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
if [ -n "${CLUSTERS}" ]; then
    for c in ${CLUSTERS}; do
        echo ""
        echo -e "  ${CYAN}[${c}]${NC}"
        LABELS=$(${KM} get cluster "${c}" \
            -o jsonpath='{.metadata.labels}' 2>/dev/null || echo "{}")
        echo "${LABELS}" | tr ',' '\n' | tr -d '{}' | grep 'sdi.keti.dev' \
            | sed 's/"//g' | awk -F':' '{printf "    %-45s = %s\n", $1, $2}' \
            || echo "    (sdi.keti.dev/* 라벨 없음)"
    done
else
    warn "멤버 클러스터 없음"
fi

# ────────────────────────────────────────────────────────────
hdr "7. 최근 ResourceBinding (스케줄링 결과)"
# ────────────────────────────────────────────────────────────
${KM} get resourcebinding -A --no-headers 2>/dev/null \
    | awk '{printf "  %-20s %-40s %s\n", $1, $2, $3}' \
    | tail -10 \
    || warn "ResourceBinding 없음"

echo ""
echo -e "${GREEN}━━━ 확인 완료 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "다음 단계:"
echo "  SDI 스케줄러 배포/업데이트: ./02-deploy-sdi-scheduler.sh"
echo "  알고리즘 전환:              ./03-switch-algorithm.sh"
echo "  워크로드 배포:              ./04-deploy-workload.sh"
