#!/bin/bash

# E2E 테스트 실행 스크립트

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 테스트 환경 준비
setup_test_env() {
    log "테스트 환경 준비 중..."
    
    # CRD 설치
    make install
    
    # 기존 컨트롤러가 실행 중인지 확인
    if lsof -t -i:8081 >/dev/null 2>&1; then
        log "포트 8081이 이미 사용 중입니다. 기존 프로세스를 종료합니다."
        kill -9 $(lsof -t -i:8081) 2>/dev/null || true
        sleep 2
    fi
    
    # 기존 male-controller deployment 삭제
    kubectl delete deployment -n male-controller-system male-controller-controller-manager --ignore-not-found=true
    sleep 5
    
    # 컨트롤러 백그라운드 실행
    go run cmd/main.go --zap-log-level=debug &
    CONTROLLER_PID=$!
    
    # 컨트롤러가 시작될 때까지 대기
    sleep 15
    
    log "컨트롤러 시작됨 (PID: $CONTROLLER_PID)"
}

# E2E 테스트 실행
run_e2e_tests() {
    log "E2E 테스트 실행 중..."
    
    # Ginkgo 설치 확인
    if ! command -v ginkgo &> /dev/null; then
        log "Ginkgo 설치 중..."
        go install github.com/onsi/ginkgo/v2/ginkgo@latest
    fi
    
    # 테스트 실행 (기존 클러스터 환경에서)
    CERT_MANAGER_INSTALL_SKIP=true go test -v ./test/e2e/... -timeout=20m
}

# 정리
cleanup() {
    log "테스트 환경 정리 중..."
    
    if [ -n "$CONTROLLER_PID" ]; then
        kill $CONTROLLER_PID 2>/dev/null || true
    fi
    
    # 테스트 리소스 정리
    kubectl delete malepolicies --all --all-namespaces --ignore-not-found=true
    kubectl delete deployments -l created-by=male-controller-test --all-namespaces --ignore-not-found=true
    kubectl delete deployments -l test=e2e --all-namespaces --ignore-not-found=true
    
    # 테스트 네임스페이스 정리
    kubectl get namespaces | grep "e2e-test-" | awk '{print $1}' | xargs -r kubectl delete namespace
    
    success "정리 완료"
}

# 트랩 설정
trap cleanup EXIT

# 메인 실행
main() {
    log "=== MALE Controller E2E 테스트 시작 ==="
    
    setup_test_env
    run_e2e_tests
    
    success "=== E2E 테스트 완료 ==="
}

main "$@"