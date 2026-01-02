#!/bin/bash
#===============================================================================
# Analysis Engine - Debug & Logs Script
#
# 사용법: ./3-debug-logs.sh [OPTION]
# 옵션:
#   logs      - 실시간 로그 확인 (기본값)
#   status    - Pod/Service 상태 확인
#   describe  - Pod 상세 정보
#   exec      - Pod 내부 쉘 접속
#   restart   - Pod 재시작
#   test      - API 테스트
#   env       - 환경변수 확인
#   all       - 전체 디버그 정보
#===============================================================================

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 설정
NAMESPACE="default"
APP_LABEL="app=sdi-analysis-engine"
DEPLOYMENT_NAME="sdi-analysis-engine"
SERVICE_NAME="sdi-analysis-engine-service"

# Pod 이름 가져오기
get_pod_name() {
    kubectl get pods -n ${NAMESPACE} -l ${APP_LABEL} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}

# 헤더 출력
print_header() {
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  Analysis Engine Debug Tool${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""
}

# 상태 확인
show_status() {
    echo -e "${GREEN}[STATUS] Pod 상태${NC}"
    echo "-------------------------------------------"
    kubectl get pods -n ${NAMESPACE} -l ${APP_LABEL} -o wide
    echo ""

    echo -e "${GREEN}[STATUS] Service 상태${NC}"
    echo "-------------------------------------------"
    kubectl get svc ${SERVICE_NAME} -n ${NAMESPACE} 2>/dev/null || echo "Service not found"
    echo ""

    echo -e "${GREEN}[STATUS] Endpoints${NC}"
    echo "-------------------------------------------"
    kubectl get endpoints ${SERVICE_NAME} -n ${NAMESPACE} 2>/dev/null || echo "Endpoints not found"
    echo ""

    echo -e "${GREEN}[STATUS] ConfigMap${NC}"
    echo "-------------------------------------------"
    kubectl get configmap analysis-engine-config -n ${NAMESPACE} 2>/dev/null || echo "ConfigMap not found"
    echo ""
}

# 로그 확인
show_logs() {
    POD_NAME=$(get_pod_name)
    if [ -z "${POD_NAME}" ]; then
        echo -e "${RED}[ERROR] Pod를 찾을 수 없습니다${NC}"
        exit 1
    fi

    echo -e "${GREEN}[LOGS] Pod: ${POD_NAME}${NC}"
    echo -e "${YELLOW}Ctrl+C로 종료${NC}"
    echo "-------------------------------------------"
    kubectl logs -f ${POD_NAME} -n ${NAMESPACE}
}

# Pod 상세 정보
show_describe() {
    POD_NAME=$(get_pod_name)
    if [ -z "${POD_NAME}" ]; then
        echo -e "${RED}[ERROR] Pod를 찾을 수 없습니다${NC}"
        exit 1
    fi

    echo -e "${GREEN}[DESCRIBE] Pod: ${POD_NAME}${NC}"
    echo "-------------------------------------------"
    kubectl describe pod ${POD_NAME} -n ${NAMESPACE}
}

# Pod 쉘 접속
exec_shell() {
    POD_NAME=$(get_pod_name)
    if [ -z "${POD_NAME}" ]; then
        echo -e "${RED}[ERROR] Pod를 찾을 수 없습니다${NC}"
        exit 1
    fi

    echo -e "${GREEN}[EXEC] Pod 쉘 접속: ${POD_NAME}${NC}"
    echo -e "${YELLOW}'exit'으로 종료${NC}"
    echo "-------------------------------------------"
    kubectl exec -it ${POD_NAME} -n ${NAMESPACE} -- /bin/bash || \
    kubectl exec -it ${POD_NAME} -n ${NAMESPACE} -- /bin/sh
}

# Pod 재시작
restart_pod() {
    echo -e "${YELLOW}[RESTART] Deployment 재시작 중...${NC}"
    kubectl rollout restart deployment/${DEPLOYMENT_NAME} -n ${NAMESPACE}

    echo -e "${YELLOW}Rollout 상태 확인 중...${NC}"
    kubectl rollout status deployment/${DEPLOYMENT_NAME} -n ${NAMESPACE} --timeout=120s

    echo ""
    show_status
}

# API 테스트
test_api() {
    echo -e "${GREEN}[TEST] API 테스트${NC}"
    echo "-------------------------------------------"

    # NodePort 가져오기
    NODE_PORT=$(kubectl get svc ${SERVICE_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}' 2>/dev/null)

    if [ -z "${NODE_PORT}" ]; then
        echo -e "${RED}[ERROR] Service NodePort를 찾을 수 없습니다${NC}"
        return 1
    fi

    # 노드 IP 가져오기 (첫 번째 노드)
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)

    if [ -z "${NODE_IP}" ]; then
        NODE_IP="localhost"
    fi

    API_URL="http://${NODE_IP}:${NODE_PORT}"

    echo -e "${CYAN}API URL: ${API_URL}${NC}"
    echo ""

    # Health Check
    echo -e "${YELLOW}1. Health Check (/health)${NC}"
    curl -s "${API_URL}/health" | python3 -m json.tool 2>/dev/null || curl -s "${API_URL}/health"
    echo ""

    # Scores API
    echo -e "${YELLOW}2. Scores API (/api/scores)${NC}"
    curl -s "${API_URL}/api/scores" | python3 -m json.tool 2>/dev/null || curl -s "${API_URL}/api/scores"
    echo ""

    # Devices API
    echo -e "${YELLOW}3. Devices API (/api/devices)${NC}"
    curl -s "${API_URL}/api/devices" | python3 -m json.tool 2>/dev/null || curl -s "${API_URL}/api/devices"
    echo ""

    # ALE Weights API
    echo -e "${YELLOW}4. ALE Weights API (/api/ale-weights)${NC}"
    curl -s "${API_URL}/api/ale-weights" | python3 -m json.tool 2>/dev/null || curl -s "${API_URL}/api/ale-weights"
    echo ""
}

# 환경변수 확인
show_env() {
    POD_NAME=$(get_pod_name)
    if [ -z "${POD_NAME}" ]; then
        echo -e "${RED}[ERROR] Pod를 찾을 수 없습니다${NC}"
        exit 1
    fi

    echo -e "${GREEN}[ENV] Pod 환경변수${NC}"
    echo "-------------------------------------------"
    kubectl exec ${POD_NAME} -n ${NAMESPACE} -- env | sort
    echo ""

    echo -e "${GREEN}[ENV] ConfigMap 내용${NC}"
    echo "-------------------------------------------"
    kubectl get configmap analysis-engine-config -n ${NAMESPACE} -o yaml 2>/dev/null | grep -A 20 "data:" || echo "ConfigMap not found"
}

# 전체 디버그 정보
show_all() {
    show_status
    echo ""
    echo -e "${GREEN}[EVENTS] 최근 이벤트${NC}"
    echo "-------------------------------------------"
    kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp' | tail -20
    echo ""
    show_env
    echo ""
    echo -e "${GREEN}[LOGS] 최근 로그 (50줄)${NC}"
    echo "-------------------------------------------"
    POD_NAME=$(get_pod_name)
    if [ -n "${POD_NAME}" ]; then
        kubectl logs ${POD_NAME} -n ${NAMESPACE} --tail=50
    fi
}

# 메인
print_header

case "${1:-logs}" in
    logs)
        show_logs
        ;;
    status)
        show_status
        ;;
    describe)
        show_describe
        ;;
    exec)
        exec_shell
        ;;
    restart)
        restart_pod
        ;;
    test)
        test_api
        ;;
    env)
        show_env
        ;;
    all)
        show_all
        ;;
    *)
        echo "사용법: $0 [logs|status|describe|exec|restart|test|env|all]"
        echo ""
        echo "옵션:"
        echo "  logs      - 실시간 로그 확인 (기본값)"
        echo "  status    - Pod/Service 상태 확인"
        echo "  describe  - Pod 상세 정보"
        echo "  exec      - Pod 내부 쉘 접속"
        echo "  restart   - Pod 재시작"
        echo "  test      - REST API 테스트"
        echo "  env       - 환경변수 확인"
        echo "  all       - 전체 디버그 정보"
        ;;
esac
