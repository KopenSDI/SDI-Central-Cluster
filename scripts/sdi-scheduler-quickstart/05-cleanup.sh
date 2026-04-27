#!/bin/bash
# ==============================================================
# 05-cleanup.sh
# SDI 스케줄러 테스트 리소스 정리
#
# kubectl 대상:
#   KM (Karmada API)  — Namespace / PropagationPolicy / ResourceBinding 삭제
#   KL (로컬 클러스터) — Deployment / ConfigMap / RBAC 삭제 (--all 옵션 시)
#
# 사용법:
#   ./05-cleanup.sh             # 테스트 워크로드만 정리 (SDI 스케줄러 유지)
#   ./05-cleanup.sh --all       # 테스트 워크로드 + SDI 스케줄러 완전 제거
# ==============================================================

set -euo pipefail

KARMADA_CFG="/etc/karmada/karmada-apiserver.config"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

ok()   { echo -e "${GREEN}  ✓ $*${NC}"; }
warn() { echo -e "${YELLOW}  ! $*${NC}"; }
hdr()  { echo -e "\n${BLUE}━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
step() { echo -e "${CYAN}  → $*${NC}"; }

KL="kubectl"
KM="kubectl --kubeconfig=${KARMADA_CFG}"

CLEANUP_ALL=false
for arg in "$@"; do
    [ "${arg}" == "--all" ] && CLEANUP_ALL=true
done

# ────────────────────────────────────────────────────────────
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════╗"
echo "║       SDI Scheduler 테스트 리소스 정리           ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

if ${CLEANUP_ALL}; then
    echo -e "  모드: ${RED}전체 제거${NC} (SDI 스케줄러 포함)"
else
    echo -e "  모드: ${YELLOW}워크로드만${NC} (SDI 스케줄러 유지)"
fi

[ -f "${KARMADA_CFG}" ] || { echo -e "${RED}  ✗ Karmada kubeconfig 없음${NC}"; exit 1; }

# ────────────────────────────────────────────────────────────
hdr "1. 테스트 워크로드 정리 (Karmada API)"
# ────────────────────────────────────────────────────────────

step "PropagationPolicy 삭제..."
${KM} delete propagationpolicy -n sdi-test \
    intent-test-policy swarm-test-policy predict-test-policy \
    --ignore-not-found=true 2>/dev/null
ok "PropagationPolicy 삭제"

step "Deployment 삭제..."
${KM} delete deployment -n sdi-test \
    intent-test-workload swarm-test-workload predict-test-workload \
    --ignore-not-found=true 2>/dev/null
ok "Deployment 삭제"

step "Namespace sdi-test 삭제..."
${KM} delete namespace sdi-test --ignore-not-found=true 2>/dev/null
ok "Namespace sdi-test 삭제"

# ────────────────────────────────────────────────────────────
if ${CLEANUP_ALL}; then
    hdr "2. SDI Scheduler 완전 제거 (로컬 클러스터)"
    # ────────────────────────────────────────────────────────────

    step "SDI Scheduler Deployment 삭제..."
    ${KL} delete deployment sdi-scheduler -n karmada-system --ignore-not-found=true
    ok "Deployment 삭제"

    step "ConfigMap 삭제..."
    ${KL} delete configmap sdi-scheduler-env -n karmada-system --ignore-not-found=true
    ok "ConfigMap 삭제"

    step "RBAC 삭제..."
    ${KL} delete clusterrolebinding sdi-scheduler --ignore-not-found=true
    ${KL} delete clusterrole sdi-scheduler --ignore-not-found=true
    ${KL} delete serviceaccount sdi-scheduler -n karmada-system --ignore-not-found=true
    ok "RBAC 삭제"

    step "Secret 삭제..."
    ${KL} delete secret sdi-scheduler-config -n karmada-system --ignore-not-found=true
    ok "Secret 삭제"

    step "Leader Lease 삭제..."
    ${KL} delete lease sdi-scheduler -n karmada-system --ignore-not-found=true 2>/dev/null || true
    ok "Lease 삭제"
fi

# ────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}━━━ 정리 완료 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "현재 스케줄러 상태:"
${KL} get deployment -n karmada-system -l app=sdi-scheduler \
    --no-headers 2>/dev/null \
    | awk '{printf "  %-30s READY=%s/%s\n", $1, $2, $3}' \
    || echo "  (SDI 스케줄러 없음)"

echo ""
if ! ${CLEANUP_ALL}; then
    echo "SDI 스케줄러까지 완전 제거:"
    echo "  ./05-cleanup.sh --all"
fi
