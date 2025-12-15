# MALE Controller 배포 및 운영 가이드

## 🚀 빠른 시작

### 1. 로컬 개발 테스트
```bash
# 프로젝트 루트에서 실행
cd /root/KETI-SDI/male-controller

# 빠른 테스트 (5분 내외)
./scripts/quick-test.sh
```

### 2. 전체 배포 테스트
```bash
# 전체 배포 및 테스트 (15-20분)
./scripts/deploy-test.sh
```

### 3. 프로덕션 배포
```bash
# 이미지 빌드 및 배포
./scripts/deploy-test.sh \
  --registry your-registry.com \
  --tag v1.0.0 \
  --webhook-url "https://hooks.slack.com/your-webhook"
```

## 📋 사전 요구사항

### 필수 도구
- **kubectl** (v1.11.3+)
- **docker** (이미지 빌드용)
- **go** (v1.24.0+)
- **make**

### Kubernetes 클러스터
- Kubernetes 1.20+
- RBAC 활성화
- Custom Resource Definition 지원

## 🛠️ 상세 배포 과정

### 1단계: 환경 준비
```bash
# 필수 도구 설치 확인
kubectl version --client
docker version
go version
make --version

# Kubernetes 클러스터 연결 확인
kubectl cluster-info
```

### 2단계: 프로젝트 설정
```bash
# 프로젝트 클론 (이미 있다면 생략)
git clone <repository-url>
cd male-controller

# Go 모듈 다운로드
go mod download
go mod tidy
```

### 3단계: CRD 설치
```bash
# MALE Policy CRD 설치
make install

# CRD 설치 확인
kubectl get crd malepolicies.opensdi.opensdi.io
```

### 4단계: 컨트롤러 배포

#### 옵션 A: 로컬 실행 (개발용)
```bash
# 컨트롤러 로컬 실행
go run cmd/main.go \
  --zap-log-level=info \
  --health-bind-address=:8082 \
  --webhook-url="https://your-webhook-url"
```

#### 옵션 B: 클러스터 배포 (운영용)
```bash
# 이미지 빌드
make docker-build IMG=your-registry/male-controller:latest

# 이미지 푸시
make docker-push IMG=your-registry/male-controller:latest

# 클러스터에 배포
make deploy IMG=your-registry/male-controller:latest
```

### 5단계: 배포 확인
```bash
# 컨트롤러 Pod 상태 확인
kubectl get pods -n male-controller-system

# 로그 확인
kubectl logs -n male-controller-system -l control-plane=controller-manager -f

# 헬스체크 확인
kubectl port-forward -n male-controller-system svc/controller-manager-metrics-service 8082:8082 &
curl http://localhost:8082/health
```

## 🧪 테스트 시나리오

### 기본 정책 테스트
```bash
# 1. 테스트 워크로드 배포
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-ml-app
  labels:
    app: ml-inference
    type: machine-learning
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ml-inference
  template:
    metadata:
      labels:
        app: ml-inference
        type: machine-learning
    spec:
      containers:
      - name: ml-container
        image: nginx:latest
        ports:
        - containerPort: 80
EOF

# 2. MALE 정책 적용
kubectl apply -f - <<EOF
apiVersion: opensdi.opensdi.io/v1alpha1
kind: MALEPolicy
metadata:
  name: test-policy
spec:
  accuracy: 800
  latency: 200
  energy: 600
  selector:
    type: "machine-learning"
  description: "Test policy for ML workloads"
EOF

# 3. 적용 결과 확인
kubectl get malepolicy test-policy -o yaml
kubectl get deployment test-ml-app -o jsonpath='{.metadata.annotations}'
```

### 고급 시나리오 테스트
```bash
# 전체 E2E 테스트 실행
./scripts/run-e2e-tests.sh

# 스트레스 테스트
./scripts/deploy-test.sh --skip-build
```

## 📊 모니터링 설정

### Prometheus 메트릭
```bash
# 메트릭 확인
kubectl port-forward -n male-controller-system svc/controller-manager-metrics-service 8080:8080 &
curl http://localhost:8080/metrics | grep male_
```

### Grafana 대시보드
```bash
# 대시보드 Import
cat config/monitoring/grafana-dashboard.json
# Grafana UI에서 Import 사용
```

### Prometheus 알림 규칙
```bash
# 알림 규칙 적용
kubectl apply -f config/monitoring/prometheus-rules.yaml
```

## 🚨 문제 해결

### 일반적인 문제들

#### 1. CRD 설치 실패
```bash
# 원인: RBAC 권한 부족
# 해결: 클러스터 관리자 권한으로 실행
kubectl auth can-i create customresourcedefinitions

# 또는 수동 CRD 설치
kubectl apply -f config/crd/bases/
```

#### 2. 컨트롤러 Pod 시작 실패
```bash
# 로그 확인
kubectl logs -n male-controller-system -l control-plane=controller-manager

# 일반적인 원인들:
# - 이미지 pull 실패
# - RBAC 권한 부족
# - 리소스 부족
```

#### 3. 정책이 적용되지 않음
```bash
# 컨트롤러 로그 확인
kubectl logs -n male-controller-system -l control-plane=controller-manager | grep "MALEPolicy"

# 정책 상태 확인
kubectl get malepolicy -o yaml

# 워크로드 라벨 확인
kubectl get deployment -o yaml | grep -A5 labels
```

#### 4. 헬스체크 실패
```bash
# 포트 포워딩 확인
kubectl port-forward -n male-controller-system pod/controller-manager-xxx 8081:8081 8082:8082

# 각 엔드포인트 테스트
curl http://localhost:8081/healthz  # Kubernetes health
curl http://localhost:8082/health   # MALE health
curl http://localhost:8082/health/live
curl http://localhost:8082/health/ready
```

### 로그 레벨 조정
```bash
# 상세한 디버그 로그
kubectl patch deployment controller-manager -n male-controller-system -p '{"spec":{"template":{"spec":{"containers":[{"name":"manager","args":["--zap-log-level=debug"]}]}}}}'

# 운영용 로그 레벨
kubectl patch deployment controller-manager -n male-controller-system -p '{"spec":{"template":{"spec":{"containers":[{"name":"manager","args":["--zap-log-level=error"]}]}}}}'
```

## 🔧 고급 설정

### 환경 변수 설정
```yaml
# config/manager/manager.yaml에 추가
env:
- name: WEBHOOK_URL
  value: "https://hooks.slack.com/your-webhook"
- name: HEALTH_CHECK_INTERVAL
  value: "30s"
- name: POLICY_VALIDATION_STRICT
  value: "true"
```

### 리소스 제한 설정
```yaml
# config/manager/manager.yaml
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi
```

### 다중 클러스터 (Karmada) 설정
```bash
# Karmada 환경에서 실행
kubectl apply -f karmada-integration/auto-cluster-discovery.yaml
kubectl apply -f karmada-integration/cluster-specific-policies.yaml
```

## 🚮 정리

### 테스트 리소스 정리
```bash
# 테스트 리소스만 정리
kubectl delete deployment --all --all-namespaces --selector=created-by=male-controller-test
kubectl delete malepolicy --all --all-namespaces
```

### 완전 제거
```bash
# 컨트롤러 제거
make undeploy

# CRD 제거
make uninstall

# 또는 스크립트 사용
./scripts/deploy-test.sh --cleanup
```

## 📞 지원 및 문의

### 로그 수집
```bash
# 지원 요청 시 다음 정보 제공
kubectl version
kubectl get nodes
kubectl get pods -n male-controller-system -o yaml
kubectl logs -n male-controller-system -l control-plane=controller-manager --tail=100
kubectl get malepolicy --all-namespaces -o yaml
```

### 유용한 명령어들
```bash
# 전체 상태 확인
kubectl get all -n male-controller-system

# 메트릭 확인
kubectl top pods -n male-controller-system

# 이벤트 확인
kubectl get events -n male-controller-system --sort-by='.lastTimestamp'

# 리소스 사용량 확인
kubectl describe node | grep -A5 "Allocated resources"
```

---
