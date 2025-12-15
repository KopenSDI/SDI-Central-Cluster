#!/bin/bash

# MALE Controller 빠른 테스트 스크립트
# 로컬 개발 환경에서 빠르게 테스트하기 위한 스크립트

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
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

# 현재 디렉토리가 male-controller인지 확인
if [ ! -f "PROJECT" ] || [ ! -d "api/v1alpha1" ]; then
    error "male-controller 디렉토리에서 실행해주세요"
    exit 1
fi

log "=== MALE Controller 빠른 테스트 시작 ==="

# 1. CRD 설치
log "1. CRD 설치 중..."
make install

# 2. 컨트롤러 백그라운드 실행
log "2. 컨트롤러 로컬 실행 중..."
go run cmd/main.go --zap-log-level=info &
CONTROLLER_PID=$!

# 컨트롤러가 시작될 때까지 대기
sleep 5

# 3. 테스트 워크로드 배포
log "3. 테스트 워크로드 배포 중..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: quick-test-ml-app
  namespace: default
  labels:
    app: quick-test-ml-app
    type: machine-learning
    tier: inference
spec:
  replicas: 1
  selector:
    matchLabels:
      app: quick-test-ml-app
  template:
    metadata:
      labels:
        app: quick-test-ml-app
        type: machine-learning
        tier: inference
    spec:
      containers:
      - name: ml-container
        image: nginx:latest
        ports:
        - containerPort: 80
        env:
        - name: MODEL_NAME
          value: "test-model"
EOF

# 4. MALE 정책 배포
log "4. MALE 정책 배포 중..."
cat <<EOF | kubectl apply -f -
apiVersion: opensdi.opensdi.io/v1alpha1
kind: MALEPolicy
metadata:
  name: quick-test-policy
  namespace: default
spec:
  accuracy: 750
  latency: 150
  energy: 650
  selector:
    type: "machine-learning"
    tier: "inference"
  description: "Quick test policy for ML inference workloads"
EOF

# 5. 결과 확인을 위해 잠시 대기
log "5. 정책 적용 대기 중..."
sleep 8

# 6. 결과 확인
log "6. 테스트 결과 확인 중..."

echo ""
echo "=== MALE 정책 상태 ==="
kubectl get malepolicy quick-test-policy -o yaml

echo ""
echo "=== 워크로드 어노테이션 확인 ==="
kubectl get deployment quick-test-ml-app -o jsonpath='{.metadata.annotations}' | jq . 2>/dev/null || kubectl get deployment quick-test-ml-app -o jsonpath='{.metadata.annotations}'

echo ""
echo "=== Pod 환경변수 확인 ==="
POD_NAME=$(kubectl get pods -l app=quick-test-ml-app -o jsonpath='{.items[0].metadata.name}')
if [ -n "$POD_NAME" ]; then
    kubectl get pod $POD_NAME -o jsonpath='{.spec.containers[0].env}' | jq . 2>/dev/null || kubectl get pod $POD_NAME -o jsonpath='{.spec.containers[0].env}'
fi

# 정리 함수
cleanup() {
    log "테스트 리소스 정리 중..."
    
    # 컨트롤러 프로세스 종료
    if [ -n "$CONTROLLER_PID" ]; then
        kill $CONTROLLER_PID 2>/dev/null || true
    fi
    
    # 테스트 리소스 삭제
    kubectl delete deployment quick-test-ml-app --ignore-not-found=true
    kubectl delete malepolicy quick-test-policy --ignore-not-found=true
    
    success "정리 완료"
}

# 트랩 설정
trap cleanup EXIT

echo ""
success "=== 빠른 테스트 완료 ==="
echo ""
echo "결과 해석:"
echo "1. MALE 정책의 status.appliedWorkloads가 1이면 성공"
echo "2. Deployment에 male-policy.opensdi.io/* 어노테이션이 있으면 성공"
echo "3. Pod에 MALE_ACCURACY, MALE_LATENCY, MALE_ENERGY 환경변수가 있으면 성공"
echo ""
echo "컨트롤러 로그를 확인하려면 별도 터미널에서:"
echo "kubectl logs -l control-plane=controller-manager -f"
echo ""
echo "정리하려면 Ctrl+C를 누르세요..."

# 사용자가 Ctrl+C를 누를 때까지 대기
read -p "Press Enter to cleanup and exit..."