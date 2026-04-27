#!/bin/bash
# ============================================================
# MALE + RTContainer Karmada 배포 테스트 스크립트
# ============================================================
#
# 아키텍처:
#   Central (Karmada)              Edge (K3s)
#   ┌─────────────────┐           ┌─────────────────┐
#   │ MaleWorkload    │           │ RTContainer     │
#   │ - importance    │──Karmada──│ (criticality,   │
#   │ - mcSpec        │   전파    │  period, wcet)  │
#   │ - container     │           │       │         │
#   │                 │           │       ▼         │
#   │                 │           │ sdi-scheduler   │
#   └─────────────────┘           └─────────────────┘
#
# 사용법:
#   ./test-deployment_rt.sh [namespace] [workload-name] [criticality] [latency]
#   ./test-deployment_rt.sh rt-test slam-processor C 0.95
#
# ============================================================

set -e

# ─────────────────────────────────────────────────────────────
# 설정값 (필요시 여기만 수정)
# ─────────────────────────────────────────────────────────────
KARMADA_KUBECONFIG="/etc/karmada/karmada-apiserver.config"

# Edge 클러스터 접속 정보
EDGE_CLUSTER_NAME="edge-cluster"
EDGE_CLUSTER_IP="10.0.0.39"
EDGE_CLUSTER_USER="root"
EDGE_CLUSTER_PASSWORD="ketilinux"

# 기본값
DEFAULT_NAMESPACE="rt-test"
DEFAULT_WORKLOAD_NAME="slam-processor"
DEFAULT_CRITICALITY="A"
DEFAULT_LATENCY="0.5"

# MALE 기본값
DEFAULT_ACCURACY="0.8"
DEFAULT_ENERGY="0.5"

# MC 기본값
DEFAULT_RT_PERIOD="100"
DEFAULT_RT_WCET="30"

# Container 기본값
DEFAULT_IMAGE="nginx:alpine"
DEFAULT_CPU_REQUEST="100m"
DEFAULT_CPU_LIMIT="500m"
DEFAULT_MEMORY_REQUEST="128Mi"
DEFAULT_MEMORY_LIMIT="256Mi"
DEFAULT_REPLICAS="1"

# Criticality 자동 결정 임계값
CRITICALITY_C_THRESHOLD="0.9"
CRITICALITY_B_THRESHOLD="0.7"

# ─────────────────────────────────────────────────────────────
# 색상 정의
# ─────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ─────────────────────────────────────────────────────────────
# 유틸리티 함수
# ─────────────────────────────────────────────────────────────
ssh_edge() {
    sshpass -p "${EDGE_CLUSTER_PASSWORD}" ssh -o StrictHostKeyChecking=no \
        "${EDGE_CLUSTER_USER}@${EDGE_CLUSTER_IP}" "$1" 2>/dev/null
}

get_criticality() {
    local latency="$1"
    if (( $(echo "$latency >= $CRITICALITY_C_THRESHOLD" | bc -l) )); then
        echo "C"
    elif (( $(echo "$latency >= $CRITICALITY_B_THRESHOLD" | bc -l) )); then
        echo "B"
    else
        echo "A"
    fi
}

# ─────────────────────────────────────────────────────────────
# 명령줄 인자 처리
# ─────────────────────────────────────────────────────────────
NAMESPACE="${1:-${DEFAULT_NAMESPACE}}"
WORKLOAD_NAME="${2:-${DEFAULT_WORKLOAD_NAME}}"
CRITICALITY="${3:-${DEFAULT_CRITICALITY}}"
LATENCY="${4:-${DEFAULT_LATENCY}}"

# Criticality 자동 결정
if [ "$CRITICALITY" == "auto" ]; then
    CRITICALITY=$(get_criticality "$LATENCY")
    echo -e "${CYAN}[INFO] Latency ${LATENCY} → Criticality ${CRITICALITY} 자동 결정${NC}"
fi

# rtDeadline 기본값 = rtPeriod
RT_DEADLINE="${DEFAULT_RT_PERIOD}"

echo -e "${CYAN}=====================================================${NC}"
echo -e "${CYAN} MALE + RTContainer Karmada 배포 테스트${NC}"
echo -e "${CYAN}=====================================================${NC}"
echo ""
echo "설정:"
echo "  - Namespace: ${NAMESPACE}"
echo "  - Workload: ${WORKLOAD_NAME}"
echo "  - Criticality: ${CRITICALITY}"
echo "  - Latency: ${LATENCY}"
echo "  - Edge: ${EDGE_CLUSTER_USER}@${EDGE_CLUSTER_IP}"
echo ""

# ─────────────────────────────────────────────────────────────
# 1. Karmada 설치 확인
# ─────────────────────────────────────────────────────────────
if [ ! -f "${KARMADA_KUBECONFIG}" ]; then
    echo -e "${RED}✗ Karmada가 설치되지 않았습니다.${NC}"
    exit 1
fi

# ─────────────────────────────────────────────────────────────
# 2. Member 클러스터 확인
# ─────────────────────────────────────────────────────────────
echo -e "${YELLOW}[1/7] Member 클러스터 확인${NC}"
CLUSTERS=$(kubectl --kubeconfig="${KARMADA_KUBECONFIG}" get clusters -o jsonpath='{.items[*].metadata.name}')

if [ -z "$CLUSTERS" ]; then
    echo -e "${RED}✗ 등록된 클러스터가 없습니다.${NC}"
    exit 1
fi

echo "등록된 클러스터:"
kubectl --kubeconfig="${KARMADA_KUBECONFIG}" get clusters
echo ""

# ─────────────────────────────────────────────────────────────
# 3. RTContainer CRD 확인 및 등록
# ─────────────────────────────────────────────────────────────
echo -e "${YELLOW}[2/7] RTContainer CRD 확인${NC}"

if ! kubectl --kubeconfig="${KARMADA_KUBECONFIG}" get crd rtcontainers.rt.keti.re.kr &>/dev/null; then
    echo "RTContainer CRD를 Karmada에 등록합니다..."
    cat <<'EOF' | kubectl --kubeconfig="${KARMADA_KUBECONFIG}" apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: rtcontainers.rt.keti.re.kr
spec:
  group: rt.keti.re.kr
  names:
    kind: RTContainer
    listKind: RTContainerList
    plural: rtcontainers
    singular: rtcontainer
    shortNames: [rtc, rt]
  scope: Namespaced
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          required: [spec]
          properties:
            spec:
              type: object
              required: [realTime, container]
              properties:
                realTime:
                  type: object
                  required: [criticality, rtPeriod, rtWcet]
                  properties:
                    criticality:
                      type: string
                      enum: ["A", "B", "C"]
                      default: "A"
                    rtPeriod:
                      type: integer
                      minimum: 1
                      default: 100
                    rtWcet:
                      type: integer
                      minimum: 1
                      default: 30
                    rtDeadline:
                      type: integer
                      minimum: 1
                    missionId:
                      type: string
                container:
                  type: object
                  required: [image]
                  properties:
                    image:
                      type: string
                    command:
                      type: array
                      items:
                        type: string
                    args:
                      type: array
                      items:
                        type: string
                    env:
                      type: array
                      items:
                        type: object
                        properties:
                          name:
                            type: string
                          value:
                            type: string
                    resources:
                      type: object
                      properties:
                        requests:
                          type: object
                          properties:
                            cpu:
                              type: string
                            memory:
                              type: string
                        limits:
                          type: object
                          properties:
                            cpu:
                              type: string
                            memory:
                              type: string
                replicas:
                  type: integer
                  minimum: 1
                  default: 1
                nodeSelector:
                  type: object
                  additionalProperties:
                    type: string
            status:
              type: object
              properties:
                phase:
                  type: string
                  enum: ["Pending", "Scheduled", "Running", "Failed"]
                nodeName:
                  type: string
                podName:
                  type: string
                utilization:
                  type: string
                message:
                  type: string
      additionalPrinterColumns:
        - name: Criticality
          type: string
          jsonPath: .spec.realTime.criticality
        - name: Period
          type: integer
          jsonPath: .spec.realTime.rtPeriod
        - name: WCET
          type: integer
          jsonPath: .spec.realTime.rtWcet
        - name: Phase
          type: string
          jsonPath: .status.phase
        - name: Node
          type: string
          jsonPath: .status.nodeName
        - name: Age
          type: date
          jsonPath: .metadata.creationTimestamp
      subresources:
        status: {}
EOF
    echo -e "${GREEN}✓ RTContainer CRD 등록 완료${NC}"
else
    echo -e "${GREEN}✓ RTContainer CRD 이미 존재${NC}"
fi
echo ""

# ─────────────────────────────────────────────────────────────
# 4. 테스트 네임스페이스 생성
# ─────────────────────────────────────────────────────────────
echo -e "${YELLOW}[3/7] 테스트 네임스페이스 생성${NC}"
kubectl create ns "${NAMESPACE}" 2>/dev/null || true
kubectl --kubeconfig="${KARMADA_KUBECONFIG}" create ns "${NAMESPACE}" 2>/dev/null || true
echo -e "${GREEN}✓ 네임스페이스 생성 완료${NC}"
echo ""

# ─────────────────────────────────────────────────────────────
# 5. MaleWorkload 생성 (Central)
# ─────────────────────────────────────────────────────────────
echo -e "${YELLOW}[4/7] MaleWorkload 생성 (Central)${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: male.keti.dev/v1alpha1
kind: MaleWorkload
metadata:
  name: ${WORKLOAD_NAME}
  namespace: ${NAMESPACE}
spec:
  importance:
    accuracy: ${DEFAULT_ACCURACY}
    latency: ${LATENCY}
    energy: ${DEFAULT_ENERGY}
  mcSpec:
    criticality: "${CRITICALITY}"
    rtPeriod: ${DEFAULT_RT_PERIOD}
    rtWcet: ${DEFAULT_RT_WCET}
    rtDeadline: ${RT_DEADLINE}
    missionId: "${WORKLOAD_NAME}-mission"
  container:
    image: ${DEFAULT_IMAGE}
    resources:
      requests:
        cpu: "${DEFAULT_CPU_REQUEST}"
        memory: "${DEFAULT_MEMORY_REQUEST}"
      limits:
        cpu: "${DEFAULT_CPU_LIMIT}"
        memory: "${DEFAULT_MEMORY_LIMIT}"
  replicas: ${DEFAULT_REPLICAS}
  targetRef:
    apiVersion: rt.keti.re.kr/v1
    kind: RTContainer
    name: ${WORKLOAD_NAME}-rt
  mission: "${WORKLOAD_NAME} RT Workload"
EOF
echo -e "${GREEN}✓ MaleWorkload 생성 완료${NC}"
echo ""

# ─────────────────────────────────────────────────────────────
# 6. RTContainer 생성 (Edge로 전파)
# ─────────────────────────────────────────────────────────────
echo -e "${YELLOW}[5/7] RTContainer 생성 (Edge로 전파)${NC}"
cat <<EOF | kubectl --kubeconfig="${KARMADA_KUBECONFIG}" apply -f -
apiVersion: rt.keti.re.kr/v1
kind: RTContainer
metadata:
  name: ${WORKLOAD_NAME}-rt
  namespace: ${NAMESPACE}
  labels:
    app: ${WORKLOAD_NAME}
    male.keti.dev/workload: ${WORKLOAD_NAME}
    criticality: "${CRITICALITY}"
  annotations:
    male.keti.dev/accuracy: "${DEFAULT_ACCURACY}"
    male.keti.dev/latency: "${LATENCY}"
    male.keti.dev/energy: "${DEFAULT_ENERGY}"
spec:
  realTime:
    criticality: "${CRITICALITY}"
    rtPeriod: ${DEFAULT_RT_PERIOD}
    rtWcet: ${DEFAULT_RT_WCET}
    rtDeadline: ${RT_DEADLINE}
    missionId: "${WORKLOAD_NAME}-mission"
  container:
    image: ${DEFAULT_IMAGE}
    resources:
      requests:
        cpu: "${DEFAULT_CPU_REQUEST}"
        memory: "${DEFAULT_MEMORY_REQUEST}"
      limits:
        cpu: "${DEFAULT_CPU_LIMIT}"
        memory: "${DEFAULT_MEMORY_LIMIT}"
  replicas: ${DEFAULT_REPLICAS}
EOF
echo -e "${GREEN}✓ RTContainer 생성 완료${NC}"
echo ""

# ─────────────────────────────────────────────────────────────
# 7. PropagationPolicy 생성
# ─────────────────────────────────────────────────────────────
echo -e "${YELLOW}[6/7] PropagationPolicy 생성${NC}"
cat <<EOF | kubectl --kubeconfig="${KARMADA_KUBECONFIG}" apply -f -
apiVersion: policy.karmada.io/v1alpha1
kind: PropagationPolicy
metadata:
  name: ${WORKLOAD_NAME}-propagation
  namespace: ${NAMESPACE}
spec:
  resourceSelectors:
    - apiVersion: rt.keti.re.kr/v1
      kind: RTContainer
      name: ${WORKLOAD_NAME}-rt
  placement:
    clusterAffinity:
      clusterNames:
$(for cluster in $CLUSTERS; do echo "        - $cluster"; done)
EOF
echo -e "${GREEN}✓ PropagationPolicy 생성 완료${NC}"
echo ""

# ─────────────────────────────────────────────────────────────
# 8. 배포 상태 확인
# ─────────────────────────────────────────────────────────────
echo -e "${YELLOW}[7/7] 배포 상태 확인 (10초 대기)${NC}"
sleep 10

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE} Central Cluster 상태${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo ""
echo -e "${CYAN}▶ MaleWorkload:${NC}"
kubectl get maleworkloads -n "${NAMESPACE}" -o wide 2>/dev/null || echo "  MaleWorkload 없음"

echo ""
echo -e "${CYAN}▶ RTContainer (Karmada):${NC}"
kubectl --kubeconfig="${KARMADA_KUBECONFIG}" get rtcontainers -n "${NAMESPACE}" 2>/dev/null || echo "  RTContainer 없음"

echo ""
echo -e "${CYAN}▶ ResourceBinding:${NC}"
kubectl --kubeconfig="${KARMADA_KUBECONFIG}" get resourcebinding -n "${NAMESPACE}" 2>/dev/null || echo "  ResourceBinding 없음"

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE} Edge Cluster 상태${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

for cluster in $CLUSTERS; do
    echo ""
    echo -e "${GREEN}▶ 클러스터: ${cluster}${NC}"

    if [ "$cluster" == "${EDGE_CLUSTER_NAME}" ]; then
        echo "  RTContainer:"
        ssh_edge "kubectl get rtcontainers -n ${NAMESPACE} 2>/dev/null" || echo "    접근 불가"

        echo "  Pods:"
        ssh_edge "kubectl get pods -n ${NAMESPACE} --no-headers 2>/dev/null | head -5" || echo "    접근 불가"
    fi
done

echo ""
echo -e "${CYAN}=====================================================${NC}"
echo -e "${GREEN} 테스트 완료!${NC}"
echo -e "${CYAN}=====================================================${NC}"
echo ""
echo "사용법:"
echo "  ./test-deployment_rt.sh                              # 기본 테스트"
echo "  ./test-deployment_rt.sh my-ns my-workload C 0.95     # 커스텀"
echo "  ./test-deployment_rt.sh my-ns my-workload auto 0.95  # Criticality 자동"
echo ""
echo "리소스 삭제:"
echo "  kubectl delete ns ${NAMESPACE}"
echo "  kubectl --kubeconfig=${KARMADA_KUBECONFIG} delete ns ${NAMESPACE}"
