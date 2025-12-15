#!/bin/bash
# Karmada 테스트 리소스 정리 스크립트

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

KARMADA_KUBECONFIG="/etc/karmada/karmada-apiserver.config"
TEST_NAMESPACE="karmada-test"

echo "======================================"
echo "Karmada 테스트 리소스 정리"
echo "======================================"
echo ""

if [ ! -f "${KARMADA_KUBECONFIG}" ]; then
    echo -e "${RED}✗ Karmada가 설치되지 않았습니다.${NC}"
    exit 1
fi

echo -e "${YELLOW}테스트 네임스페이스 '${TEST_NAMESPACE}' 삭제 중...${NC}"

# PropagationPolicy 삭제
kubectl --kubeconfig="${KARMADA_KUBECONFIG}" delete propagationpolicy nginx-propagation -n ${TEST_NAMESPACE} 2>/dev/null || true

# Deployment 삭제
kubectl --kubeconfig="${KARMADA_KUBECONFIG}" delete deployment nginx-test -n ${TEST_NAMESPACE} 2>/dev/null || true

# 네임스페이스 삭제
kubectl --kubeconfig="${KARMADA_KUBECONFIG}" delete namespace ${TEST_NAMESPACE} 2>/dev/null || true

echo ""
echo -e "${GREEN}✓ 테스트 리소스 정리 완료${NC}"
echo ""
echo "확인:"
echo "  kubectl --kubeconfig=/etc/karmada/karmada-apiserver.config get ns ${TEST_NAMESPACE}"



