#!/bin/bash
# Karmada 배포 상태 실시간 확인 스크립트

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

KARMADA_KUBECONFIG="/etc/karmada/karmada-apiserver.config"
TEST_NAMESPACE="karmada-test"

if [ ! -f "${KARMADA_KUBECONFIG}" ]; then
    echo -e "${RED}✗ Karmada가 설치되지 않았습니다.${NC}"
    exit 1
fi

echo "======================================"
echo "Karmada 배포 상태 실시간 확인"
echo "======================================"
echo ""
echo "Ctrl+C로 종료"
echo ""

while true; do
    clear
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Karmada Control Plane 상태${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    echo ""
    echo "Member 클러스터:"
    kubectl --kubeconfig="${KARMADA_KUBECONFIG}" get clusters
    
    echo ""
    echo "Deployment:"
    kubectl --kubeconfig="${KARMADA_KUBECONFIG}" get deployment -n ${TEST_NAMESPACE} 2>/dev/null || echo "Deployment 없음"
    
    echo ""
    echo "ResourceBinding:"
    kubectl --kubeconfig="${KARMADA_KUBECONFIG}" get resourcebinding -n ${TEST_NAMESPACE} 2>/dev/null || echo "ResourceBinding 없음"
    
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}각 Member 클러스터의 Pod 상태${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    CLUSTERS=$(kubectl --kubeconfig="${KARMADA_KUBECONFIG}" get clusters -o jsonpath='{.items[*].metadata.name}')
    
    for cluster in $CLUSTERS; do
        echo ""
        echo -e "${GREEN}▶ ${cluster}${NC}"
        
        CLUSTER_KUBECONFIG="/tmp/cluster-${cluster}-kubeconfig"
        
        if kubectl --kubeconfig="${KARMADA_KUBECONFIG}" get secret -n karmada-cluster ${cluster} &>/dev/null; then
            kubectl --kubeconfig="${KARMADA_KUBECONFIG}" get secret -n karmada-cluster ${cluster} -o jsonpath='{.data.kubeconfig}' | base64 -d > "${CLUSTER_KUBECONFIG}" 2>/dev/null || true
            
            if [ -f "${CLUSTER_KUBECONFIG}" ]; then
                kubectl --kubeconfig="${CLUSTER_KUBECONFIG}" get pods -n ${TEST_NAMESPACE} 2>/dev/null || echo "  Pod 없음"
                rm -f "${CLUSTER_KUBECONFIG}"
            else
                echo "  (접근 불가)"
            fi
        else
            echo "  (secret 없음)"
        fi
    done
    
    echo ""
    echo "$(date '+%Y-%m-%d %H:%M:%S') - 5초마다 갱신 (Ctrl+C로 종료)"
    sleep 5
done



