#!/bin/bash
# Karmada 멀티 클러스터 배포 테스트 스크립트

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

KARMADA_KUBECONFIG="/etc/karmada/karmada-apiserver.config"
TEST_NAMESPACE="karmada-test"

echo "======================================"
echo "Karmada 멀티 클러스터 배포 테스트"
echo "======================================"
echo ""

# 1. Karmada 설치 확인
if [ ! -f "${KARMADA_KUBECONFIG}" ]; then
    echo -e "${RED}✗ Karmada가 설치되지 않았습니다.${NC}"
    exit 1
fi

# 2. Member 클러스터 확인
echo -e "${YELLOW}1. Member 클러스터 확인${NC}"
CLUSTERS=$(kubectl --kubeconfig="${KARMADA_KUBECONFIG}" get clusters -o jsonpath='{.items[*].metadata.name}')

if [ -z "$CLUSTERS" ]; then
    echo -e "${RED}✗ 등록된 클러스터가 없습니다.${NC}"
    echo "먼저 클러스터를 조인하세요:"
    echo "  ./join-cluster.sh <클러스터-이름> <kubeconfig-경로>"
    exit 1
fi

echo "등록된 클러스터:"
kubectl --kubeconfig="${KARMADA_KUBECONFIG}" get clusters
echo ""

# 3. 테스트 네임스페이스 생성
echo -e "${YELLOW}2. 테스트 네임스페이스 생성${NC}"
cat <<EOF | kubectl --kubeconfig="${KARMADA_KUBECONFIG}" apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: ${TEST_NAMESPACE}
EOF
echo -e "${GREEN}✓ 네임스페이스 생성 완료${NC}"
echo ""

# 4. 테스트 Deployment 생성
echo -e "${YELLOW}3. 테스트 Deployment 생성${NC}"
cat <<EOF | kubectl --kubeconfig="${KARMADA_KUBECONFIG}" apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-test
  namespace: ${TEST_NAMESPACE}
  labels:
    app: nginx-test
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx-test
  template:
    metadata:
      labels:
        app: nginx-test
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
EOF
echo -e "${GREEN}✓ Deployment 생성 완료${NC}"
echo ""

# 5. PropagationPolicy 생성 (모든 클러스터에 배포)
echo -e "${YELLOW}4. PropagationPolicy 생성 (모든 클러스터에 배포)${NC}"
cat <<EOF | kubectl --kubeconfig="${KARMADA_KUBECONFIG}" apply -f -
apiVersion: policy.karmada.io/v1alpha1
kind: PropagationPolicy
metadata:
  name: nginx-propagation
  namespace: ${TEST_NAMESPACE}
spec:
  resourceSelectors:
    - apiVersion: apps/v1
      kind: Deployment
      name: nginx-test
  placement:
    clusterAffinity:
      clusterNames:
$(for cluster in $CLUSTERS; do echo "        - $cluster"; done)
EOF
echo -e "${GREEN}✓ PropagationPolicy 생성 완료${NC}"
echo ""

# 6. 배포 상태 확인
echo -e "${YELLOW}5. 배포 상태 확인 (10초 대기)${NC}"
sleep 10

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Karmada Control Plane 상태${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo ""
echo "Deployment 상태:"
kubectl --kubeconfig="${KARMADA_KUBECONFIG}" get deployment -n ${TEST_NAMESPACE}

echo ""
echo "ResourceBinding 상태:"
kubectl --kubeconfig="${KARMADA_KUBECONFIG}" get resourcebinding -n ${TEST_NAMESPACE}

echo ""
echo "Work 상태:"
kubectl --kubeconfig="${KARMADA_KUBECONFIG}" get work -A | grep ${TEST_NAMESPACE} || echo "Work 리소스 없음"

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}각 Member 클러스터 상태${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

for cluster in $CLUSTERS; do
    echo ""
    echo -e "${GREEN}▶ 클러스터: ${cluster}${NC}"
    
    # 클러스터별 Pod 상태 확인
    CLUSTER_KUBECONFIG="/tmp/cluster-${cluster}-kubeconfig"
    
    # karmadactl을 통해 클러스터에 접근
    if kubectl --kubeconfig="${KARMADA_KUBECONFIG}" get secret -n karmada-cluster ${cluster} &>/dev/null; then
        kubectl --kubeconfig="${KARMADA_KUBECONFIG}" get secret -n karmada-cluster ${cluster} -o jsonpath='{.data.kubeconfig}' | base64 -d > "${CLUSTER_KUBECONFIG}" 2>/dev/null || true
        
        if [ -f "${CLUSTER_KUBECONFIG}" ]; then
            echo "Namespace:"
            kubectl --kubeconfig="${CLUSTER_KUBECONFIG}" get ns ${TEST_NAMESPACE} 2>/dev/null || echo "  네임스페이스 없음"
            
            echo "Deployment:"
            kubectl --kubeconfig="${CLUSTER_KUBECONFIG}" get deployment -n ${TEST_NAMESPACE} 2>/dev/null || echo "  Deployment 없음"
            
            echo "Pods:"
            kubectl --kubeconfig="${CLUSTER_KUBECONFIG}" get pods -n ${TEST_NAMESPACE} 2>/dev/null || echo "  Pod 없음"
            
            rm -f "${CLUSTER_KUBECONFIG}"
        else
            echo "  (클러스터 kubeconfig 접근 불가)"
        fi
    else
        echo "  (클러스터 secret 없음)"
    fi
done

echo ""
echo "======================================"
echo -e "${GREEN}테스트 완료!${NC}"
echo "======================================"
echo ""
echo "배포 확인 명령어:"
echo "  # Karmada에서 확인"
echo "  kubectl --kubeconfig=/etc/karmada/karmada-apiserver.config get deployment -n ${TEST_NAMESPACE}"
echo "  kubectl --kubeconfig=/etc/karmada/karmada-apiserver.config get resourcebinding -n ${TEST_NAMESPACE}"
echo ""
echo "  # 각 클러스터에서 직접 확인"
echo "  kubectl get pods -n ${TEST_NAMESPACE}"
echo ""
echo "테스트 리소스 삭제:"
echo "  ./cleanup-test.sh"



