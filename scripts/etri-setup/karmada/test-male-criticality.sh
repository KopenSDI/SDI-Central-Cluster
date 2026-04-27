#!/bin/bash
# ============================================================
# MALE MC Criticality 재정의 테스트 스크립트
# ============================================================
#
# 데이터 플로우:
#   User YAML (importance A,L,E)
#         ↓
#   MALE-Operator (criticality.go)
#         ↓
#   effectiveMcSpec (재정의된 criticality)
#         ↓
#   RTContainer → Edge Cluster
#
# 사용법:
#   ./test-male-criticality.sh
#
# ============================================================

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

NAMESPACE="male-test"

echo -e "${CYAN}============================================================${NC}"
echo -e "${CYAN} MALE MC Criticality 재정의 테스트${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""

# ─────────────────────────────────────────────────────────────
# 0. 네임스페이스 준비
# ─────────────────────────────────────────────────────────────
echo -e "${YELLOW}[0/4] 테스트 환경 준비${NC}"
kubectl create ns ${NAMESPACE} 2>/dev/null || true
echo -e "${GREEN}✓ Namespace: ${NAMESPACE}${NC}"
echo ""

# ─────────────────────────────────────────────────────────────
# 1. 테스트 케이스 1: 자율주행 패턴 (A=0.6, L=0.3, E=0.1)
#    사용자가 criticality: A 지정 → C로 재정의 예상
# ─────────────────────────────────────────────────────────────
echo -e "${YELLOW}[1/4] 테스트 케이스 1: 자율주행 패턴${NC}"
echo -e "${BLUE}     입력: accuracy=0.6, latency=0.3, energy=0.1${NC}"
echo -e "${BLUE}     사용자 지정: criticality=A${NC}"
echo -e "${BLUE}     예상 결과: criticality=C (Safety-Critical)${NC}"
echo ""

cat <<EOF | kubectl apply -f -
apiVersion: male.keti.dev/v1alpha1
kind: MaleWorkload
metadata:
  name: autonomous-vehicle
  namespace: ${NAMESPACE}
spec:
  importance:
    accuracy: 0.6
    latency: 0.3
    energy: 0.1
  mcSpec:
    criticality: "A"
    rtPeriod: 100
    rtWcet: 30
  container:
    image: nginx:alpine
  replicas: 1
  allowPolicyOverride: true
  targetRef:
    apiVersion: rt.keti.re.kr/v1
    kind: RTContainer
    name: autonomous-vehicle-rt
EOF

echo -e "${GREEN}✓ MaleWorkload 'autonomous-vehicle' 생성${NC}"
echo ""

# ─────────────────────────────────────────────────────────────
# 2. 테스트 케이스 2: 실시간 로봇 패턴 (A=0.1, L=0.7, E=0.2)
#    예상: criticality=B (Mission-Critical)
# ─────────────────────────────────────────────────────────────
echo -e "${YELLOW}[2/4] 테스트 케이스 2: 실시간 로봇 패턴${NC}"
echo -e "${BLUE}     입력: accuracy=0.1, latency=0.7, energy=0.2${NC}"
echo -e "${BLUE}     사용자 지정: criticality=A${NC}"
echo -e "${BLUE}     예상 결과: criticality=B (Mission-Critical)${NC}"
echo ""

cat <<EOF | kubectl apply -f -
apiVersion: male.keti.dev/v1alpha1
kind: MaleWorkload
metadata:
  name: realtime-robot
  namespace: ${NAMESPACE}
spec:
  importance:
    accuracy: 0.1
    latency: 0.7
    energy: 0.2
  mcSpec:
    criticality: "A"
    rtPeriod: 50
    rtWcet: 15
  container:
    image: nginx:alpine
  replicas: 1
  allowPolicyOverride: true
  targetRef:
    apiVersion: rt.keti.re.kr/v1
    kind: RTContainer
    name: realtime-robot-rt
EOF

echo -e "${GREEN}✓ MaleWorkload 'realtime-robot' 생성${NC}"
echo ""

# ─────────────────────────────────────────────────────────────
# 3. 테스트 케이스 3: IoT 센서 패턴 (A=0.2, L=0.1, E=0.7)
#    예상: criticality=A (Best-Effort)
# ─────────────────────────────────────────────────────────────
echo -e "${YELLOW}[3/4] 테스트 케이스 3: IoT 센서 패턴${NC}"
echo -e "${BLUE}     입력: accuracy=0.2, latency=0.1, energy=0.7${NC}"
echo -e "${BLUE}     사용자 지정: criticality=C${NC}"
echo -e "${BLUE}     예상 결과: criticality=A (Best-Effort) - 재정의됨${NC}"
echo ""

cat <<EOF | kubectl apply -f -
apiVersion: male.keti.dev/v1alpha1
kind: MaleWorkload
metadata:
  name: iot-sensor
  namespace: ${NAMESPACE}
spec:
  importance:
    accuracy: 0.2
    latency: 0.1
    energy: 0.7
  mcSpec:
    criticality: "C"
    rtPeriod: 1000
    rtWcet: 100
  container:
    image: nginx:alpine
  replicas: 1
  allowPolicyOverride: true
  targetRef:
    apiVersion: rt.keti.re.kr/v1
    kind: RTContainer
    name: iot-sensor-rt
EOF

echo -e "${GREEN}✓ MaleWorkload 'iot-sensor' 생성${NC}"
echo ""

# ─────────────────────────────────────────────────────────────
# 4. 결과 확인 (10초 대기)
# ─────────────────────────────────────────────────────────────
echo -e "${YELLOW}[4/4] 결과 확인 (MALE-Operator 처리 대기 중...)${NC}"
sleep 5

echo ""
echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${MAGENTA} 데이터 플로우 결과${NC}"
echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

for workload in autonomous-vehicle realtime-robot iot-sensor; do
    echo ""
    echo -e "${CYAN}▶ ${workload}${NC}"
    echo -e "${BLUE}─────────────────────────────────────────────${NC}"

    # 입력값 출력
    echo -e "${YELLOW}[입력] spec.importance:${NC}"
    kubectl get maleworkload ${workload} -n ${NAMESPACE} -o jsonpath='  accuracy: {.spec.importance.accuracy}
  latency:  {.spec.importance.latency}
  energy:   {.spec.importance.energy}
' 2>/dev/null || echo "  (데이터 없음)"

    echo ""
    echo -e "${YELLOW}[입력] spec.mcSpec.criticality:${NC}"
    kubectl get maleworkload ${workload} -n ${NAMESPACE} -o jsonpath='  {.spec.mcSpec.criticality}' 2>/dev/null || echo "  (없음)"
    echo ""

    echo ""
    echo -e "${GREEN}[출력] status.effectiveMcSpec:${NC}"
    kubectl get maleworkload ${workload} -n ${NAMESPACE} -o jsonpath='  criticality:    {.status.effectiveMcSpec.criticality}
  missionType:    {.status.effectiveMcSpec.missionType}
  overrideReason: {.status.effectiveMcSpec.overrideReason}
  rtPeriod:       {.status.effectiveMcSpec.rtPeriod}
  rtWcet:         {.status.effectiveMcSpec.rtWcet}
' 2>/dev/null || echo "  (MALE-Operator 미실행 - status 없음)"

    echo ""
done

echo ""
echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${MAGENTA} 전체 MaleWorkload 목록${NC}"
echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
kubectl get maleworkloads -n ${NAMESPACE} -o wide 2>/dev/null || echo "MaleWorkload 없음"

echo ""
echo -e "${CYAN}============================================================${NC}"
echo -e "${GREEN} 테스트 완료!${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""
echo "상세 확인:"
echo "  kubectl get maleworkload autonomous-vehicle -n ${NAMESPACE} -o yaml"
echo "  kubectl get maleworkload realtime-robot -n ${NAMESPACE} -o yaml"
echo "  kubectl get maleworkload iot-sensor -n ${NAMESPACE} -o yaml"
echo ""
echo "정리:"
echo "  kubectl delete ns ${NAMESPACE}"
