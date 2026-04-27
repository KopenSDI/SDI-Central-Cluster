#!/bin/bash
# ============================================================
# 테스트 리소스 정리 스크립트
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

NAMESPACE="${1:-${DEFAULT_NAMESPACE}}"

echo "테스트 리소스 정리 중..."
echo "  - Namespace: ${NAMESPACE}"
echo ""

# Central 클러스터에서 삭제
echo "[1/3] Central 클러스터 정리..."
kubectl delete ns "${NAMESPACE}" 2>/dev/null && echo "  ✓ Central namespace 삭제" || echo "  - Central namespace 없음"

# Karmada에서 삭제
echo "[2/3] Karmada 정리..."
kubectl --kubeconfig="${KARMADA_KUBECONFIG}" delete ns "${NAMESPACE}" 2>/dev/null && echo "  ✓ Karmada namespace 삭제" || echo "  - Karmada namespace 없음"

# Edge 클러스터에서 삭제
echo "[3/3] Edge 클러스터 정리..."
ssh_edge "kubectl delete ns ${NAMESPACE} --force --grace-period=0 2>/dev/null" 2>/dev/null && echo "  ✓ Edge namespace 삭제" || echo "  - Edge namespace 없음 또는 접근 불가"

echo ""
echo "정리 완료!"
