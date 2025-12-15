#!/bin/bash

# MALE Controller 배포 및 테스트 스크립트
# 사용법: ./scripts/deploy-test.sh [옵션]

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 기본 설정
NAMESPACE="male-controller-system"
CONTROLLER_NAME="male-controller"
IMAGE_TAG=${IMAGE_TAG:-"latest"}
REGISTRY=${REGISTRY:-"localhost:5000"}
SKIP_BUILD=${SKIP_BUILD:-"false"}
SKIP_DEPLOY=${SKIP_DEPLOY:-"false"}
CLEANUP=${CLEANUP:-"false"}
ENABLE_MONITORING=${ENABLE_MONITORING:-"true"}
WEBHOOK_URL=${WEBHOOK_URL:-""}

# 로그 함수들
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 도움말 출력
show_help() {
    cat << EOF
MALE Controller 배포 및 테스트 스크립트

사용법:
    $0 [OPTIONS]

옵션:
    -h, --help              이 도움말 출력
    -n, --namespace NAME    Kubernetes 네임스페이스 (기본값: ${NAMESPACE})
    -r, --registry URL      이미지 레지스트리 (기본값: ${REGISTRY})
    -t, --tag TAG           이미지 태그 (기본값: ${IMAGE_TAG})
    --skip-build           이미지 빌드 건너뛰기
    --skip-deploy          배포 건너뛰기 (테스트만 실행)
    --cleanup              배포 정리 및 종료
    --no-monitoring        모니터링 비활성화
    --webhook-url URL      알림용 웹훅 URL

예시:
    $0                                    # 기본 설정으로 전체 배포 및 테스트
    $0 --skip-build                       # 빌드 없이 배포 및 테스트
    $0 --skip-deploy                      # 배포 없이 테스트만 실행
    $0 --cleanup                          # 모든 리소스 정리
    $0 --webhook-url "https://hooks.slack.com/..." # Slack 알림 활성화

EOF
}

# 명령행 인수 파싱
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -r|--registry)
                REGISTRY="$2"
                shift 2
                ;;
            -t|--tag)
                IMAGE_TAG="$2"
                shift 2
                ;;
            --skip-build)
                SKIP_BUILD="true"
                shift
                ;;
            --skip-deploy)
                SKIP_DEPLOY="true"
                shift
                ;;
            --cleanup)
                CLEANUP="true"
                shift
                ;;
            --no-monitoring)
                ENABLE_MONITORING="false"
                shift
                ;;
            --webhook-url)
                WEBHOOK_URL="$2"
                shift 2
                ;;
            *)
                log_error "알 수 없는 옵션: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# 필수 도구 확인
check_prerequisites() {
    log_info "필수 도구 확인 중..."
    
    local missing_tools=()
    
    command -v kubectl >/dev/null 2>&1 || missing_tools+=("kubectl")
    command -v docker >/dev/null 2>&1 || missing_tools+=("docker")
    command -v make >/dev/null 2>&1 || missing_tools+=("make")
    command -v go >/dev/null 2>&1 || missing_tools+=("go")
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "필수 도구가 설치되지 않았습니다: ${missing_tools[*]}"
        exit 1
    fi
    
    # Kubernetes 클러스터 연결 확인
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "Kubernetes 클러스터에 연결할 수 없습니다"
        exit 1
    fi
    
    log_success "모든 필수 도구가 준비되었습니다"
}

# 이미지 빌드
build_image() {
    if [ "$SKIP_BUILD" = "true" ]; then
        log_info "이미지 빌드 건너뛰기"
        return
    fi
    
    log_info "Docker 이미지 빌드 중..."
    
    local image_name="${REGISTRY}/${CONTROLLER_NAME}:${IMAGE_TAG}"
    
    # Go 모듈 다운로드
    go mod download
    go mod tidy
    
    # Docker 이미지 빌드
    make docker-build IMG="${image_name}"
    
    # 레지스트리에 푸시 (로컬 레지스트리가 아닌 경우)
    if [[ "$REGISTRY" != "localhost"* ]] && [[ "$REGISTRY" != "127.0.0.1"* ]]; then
        log_info "이미지를 레지스트리에 푸시 중..."
        make docker-push IMG="${image_name}"
    fi
    
    log_success "이미지 빌드 완료: ${image_name}"
}

# CRD 설치
install_crds() {
    log_info "CRD 설치 중..."
    
    make install
    
    # CRD가 준비될 때까지 대기
    timeout 60s bash -c 'until kubectl get crd malepolicies.opensdi.opensdi.io >/dev/null 2>&1; do sleep 2; done'
    
    log_success "CRD 설치 완료"
}

# 컨트롤러 배포
deploy_controller() {
    if [ "$SKIP_DEPLOY" = "true" ]; then
        log_info "컨트롤러 배포 건너뛰기"
        return
    fi
    
    log_info "MALE Controller 배포 중..."
    
    local image_name="${REGISTRY}/${CONTROLLER_NAME}:${IMAGE_TAG}"
    
    # 네임스페이스 생성
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # 매니페스트 배포
    make deploy IMG="${image_name}"
    
    # 웹훅 URL 설정 (제공된 경우)
    if [ -n "$WEBHOOK_URL" ]; then
        log_info "웹훅 URL 설정 중..."
        kubectl patch deployment controller-manager \
            -n "$NAMESPACE" \
            -p '{"spec":{"template":{"spec":{"containers":[{"name":"manager","args":["--webhook-url='$WEBHOOK_URL'"]}]}}}}'
    fi
    
    # Pod가 준비될 때까지 대기
    log_info "컨트롤러 Pod 준비 대기 중..."
    kubectl wait --for=condition=Ready pod -l control-plane=controller-manager -n "$NAMESPACE" --timeout=300s
    
    log_success "MALE Controller 배포 완료"
}

# 모니터링 설정
setup_monitoring() {
    if [ "$ENABLE_MONITORING" != "true" ]; then
        log_info "모니터링 비활성화됨"
        return
    fi
    
    log_info "모니터링 설정 중..."
    
    # ServiceMonitor 생성 (Prometheus Operator가 있는 경우)
    cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: male-controller-metrics
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: male-controller
spec:
  selector:
    matchLabels:
      control-plane: controller-manager
  endpoints:
  - port: https
    path: /metrics
    scheme: https
    tlsConfig:
      insecureSkipVerify: true
EOF
    
    log_success "모니터링 설정 완료"
}

# 헬스체크 테스트
test_health_endpoints() {
    log_info "헬스체크 엔드포인트 테스트 중..."
    
    # 컨트롤러 Pod 이름 가져오기
    local pod_name=$(kubectl get pods -n "$NAMESPACE" -l control-plane=controller-manager -o jsonpath='{.items[0].metadata.name}')
    
    if [ -z "$pod_name" ]; then
        log_error "컨트롤러 Pod을 찾을 수 없습니다"
        return 1
    fi
    
    # 포트 포워드 시작
    kubectl port-forward -n "$NAMESPACE" pod/"$pod_name" 8081:8081 8082:8082 &
    local port_forward_pid=$!
    
    # 포트 포워드가 준비될 때까지 대기
    sleep 5
    
    # 헬스체크 테스트
    local health_tests=(
        "http://localhost:8081/healthz|Kubernetes healthz"
        "http://localhost:8081/readyz|Kubernetes readyz"
        "http://localhost:8082/health|MALE health"
        "http://localhost:8082/health/live|MALE liveness"
        "http://localhost:8082/health/ready|MALE readiness"
    )
    
    local failed_tests=()
    
    for test in "${health_tests[@]}"; do
        IFS='|' read -r url description <<< "$test"
        
        if curl -s -f "$url" >/dev/null; then
            log_success "$description 테스트 통과"
        else
            log_error "$description 테스트 실패"
            failed_tests+=("$description")
        fi
    done
    
    # 포트 포워드 종료
    kill $port_forward_pid 2>/dev/null || true
    
    if [ ${#failed_tests[@]} -eq 0 ]; then
        log_success "모든 헬스체크 테스트 통과"
        return 0
    else
        log_error "실패한 테스트: ${failed_tests[*]}"
        return 1
    fi
}

# 정책 배포 및 테스트
test_policy_deployment() {
    log_info "MALE 정책 배포 및 테스트 중..."
    
    # 테스트 워크로드 배포
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-ml-workload
  namespace: default
  labels:
    app: test-ml-workload
    type: machine-learning
    environment: test
spec:
  replicas: 2
  selector:
    matchLabels:
      app: test-ml-workload
  template:
    metadata:
      labels:
        app: test-ml-workload
        type: machine-learning
        environment: test
    spec:
      containers:
      - name: ml-app
        image: nginx:latest
        ports:
        - containerPort: 80
        env:
        - name: APP_MODE
          value: "ml-inference"
EOF
    
    # MALE 정책 배포
    cat <<EOF | kubectl apply -f -
apiVersion: opensdi.opensdi.io/v1alpha1
kind: MALEPolicy
metadata:
  name: test-policy
  namespace: default
spec:
  accuracy: 800
  latency: 200
  energy: 600
  selector:
    type: "machine-learning"
    environment: "test"
  description: "Test policy for ML workloads"
EOF
    
    # 정책 적용 대기
    log_info "정책 적용 대기 중..."
    sleep 10
    
    # 정책 적용 확인
    local policy_status=$(kubectl get malepolicy test-policy -n default -o jsonpath='{.status.appliedWorkloads}')
    
    if [ "$policy_status" -gt 0 ]; then
        log_success "정책이 $policy_status 개의 워크로드에 적용됨"
    else
        log_error "정책이 어떤 워크로드에도 적용되지 않음"
        return 1
    fi
    
    # 워크로드에 MALE 값이 주입되었는지 확인
    local deployment_annotations=$(kubectl get deployment test-ml-workload -n default -o jsonpath='{.metadata.annotations}')
    
    if echo "$deployment_annotations" | grep -q "male-policy.opensdi.io"; then
        log_success "워크로드에 MALE 어노테이션이 적용됨"
    else
        log_error "워크로드에 MALE 어노테이션이 적용되지 않음"
        return 1
    fi
    
    log_success "정책 배포 및 테스트 완료"
}

# 메트릭 테스트
test_metrics() {
    log_info "메트릭 수집 테스트 중..."
    
    # 컨트롤러 Pod 이름 가져오기
    local pod_name=$(kubectl get pods -n "$NAMESPACE" -l control-plane=controller-manager -o jsonpath='{.items[0].metadata.name}')
    
    # 메트릭 엔드포인트 테스트
    kubectl port-forward -n "$NAMESPACE" pod/"$pod_name" 8080:8080 &
    local port_forward_pid=$!
    
    sleep 5
    
    # MALE 관련 메트릭 확인
    local metrics_output=$(curl -s http://localhost:8080/metrics | grep "male_")
    
    kill $port_forward_pid 2>/dev/null || true
    
    if [ -n "$metrics_output" ]; then
        log_success "MALE 메트릭이 수집되고 있습니다"
        echo "$metrics_output" | head -5
    else
        log_warning "MALE 메트릭을 찾을 수 없습니다"
    fi
}

# 스트레스 테스트
run_stress_test() {
    log_info "스트레스 테스트 실행 중..."
    
    # 여러 정책 생성
    for i in {1..5}; do
        cat <<EOF | kubectl apply -f -
apiVersion: opensdi.opensdi.io/v1alpha1
kind: MALEPolicy
metadata:
  name: stress-test-policy-$i
  namespace: default
spec:
  accuracy: $((600 + i * 50))
  latency: $((300 - i * 20))
  energy: $((500 + i * 30))
  selector:
    app: "stress-test-$i"
  description: "Stress test policy $i"
EOF
    done
    
    # 여러 워크로드 생성
    for i in {1..5}; do
        cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: stress-test-workload-$i
  namespace: default
  labels:
    app: stress-test-$i
spec:
  replicas: 1
  selector:
    matchLabels:
      app: stress-test-$i
  template:
    metadata:
      labels:
        app: stress-test-$i
    spec:
      containers:
      - name: app
        image: nginx:latest
EOF
    done
    
    # 정책 적용 대기
    sleep 15
    
    # 결과 확인
    local total_policies=$(kubectl get malepolicies -n default --no-headers | wc -l)
    local active_policies=$(kubectl get malepolicies -n default -o jsonpath='{range .items[*]}{.status.appliedWorkloads}{"\n"}{end}' | awk '{sum += $1} END {print sum}')
    
    log_success "스트레스 테스트 완료: $total_policies 개 정책, $active_policies 개 적용"
}

# 리소스 정리
cleanup_resources() {
    log_info "리소스 정리 중..."
    
    # 테스트 리소스 삭제 (시스템 컴포넌트 제외)
    kubectl delete deployment -l created-by=male-controller-test -A --ignore-not-found=true
    kubectl delete deployment -l app.kubernetes.io/managed-by=male-controller -A --ignore-not-found=true
    kubectl delete malepolicies --all -n default --ignore-not-found=true
    
    # 특정 테스트 워크로드만 삭제
    for deployment in test-ml-workload stress-test-workload quick-test-ml-app; do
        kubectl delete deployment $deployment -n default --ignore-not-found=true 2>/dev/null || true
    done
    
    if [ "$CLEANUP" = "true" ]; then
        log_info "컨트롤러 및 CRD 삭제 중..."
        
        # 컨트롤러 삭제
        make undeploy || true
        
        # CRD 삭제
        make uninstall || true
        
        # 네임스페이스 삭제
        kubectl delete namespace "$NAMESPACE" --ignore-not-found=true
        
        log_success "모든 리소스 정리 완료"
    else
        log_success "테스트 리소스 정리 완료"
    fi
}

# 전체 테스트 실행
run_full_test() {
    log_info "=== MALE Controller 배포 및 테스트 시작 ==="
    log_info "네임스페이스: $NAMESPACE"
    log_info "이미지: ${REGISTRY}/${CONTROLLER_NAME}:${IMAGE_TAG}"
    log_info "모니터링: $ENABLE_MONITORING"
    
    check_prerequisites
    build_image
    install_crds
    deploy_controller
    setup_monitoring
    
    sleep 10  # 컨트롤러가 완전히 시작될 때까지 대기
    
    test_health_endpoints
    test_policy_deployment
    test_metrics
    run_stress_test
    
    log_success "=== 모든 테스트 완료 ==="
    
    # 정리 여부 확인
    if [ "$CLEANUP" != "true" ]; then
        log_info "리소스를 유지합니다. 정리하려면 --cleanup 옵션을 사용하세요."
        log_info "컨트롤러 로그 확인: kubectl logs -n $NAMESPACE -l control-plane=controller-manager -f"
        log_info "헬스체크: kubectl port-forward -n $NAMESPACE svc/controller-manager-metrics-service 8082:8082"
    fi
}

# 메인 실행 로직
main() {
    parse_args "$@"
    
    # 트랩 설정 (스크립트 종료 시 정리)
    trap cleanup_resources EXIT
    
    if [ "$CLEANUP" = "true" ]; then
        cleanup_resources
        exit 0
    fi
    
    run_full_test
}

# 스크립트 실행
main "$@"