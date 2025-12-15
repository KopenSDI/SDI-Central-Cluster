# MALE Controller
**Machine Learning Acceleration and Latency Enhancement** Policy Controller for Kubernetes

## Description

MALE Controller는 KETI-SDI(한국전자통신연구원 소프트웨어 정의 인프라) 프로젝트의 일부로, Kubernetes 환경에서 머신러닝 워크로드의 성능 요구사항을 동적으로 관리하는 Custom Resource Definition(CRD) 기반 컨트롤러입니다.

머신러닝 워크로드의 **정확도(Accuracy)**, **지연시간(Latency)**, **전력효율성(Energy)** 요구사항을 정책으로 정의하고, 이를 실행 중인 워크로드에 자동으로 적용합니다.

## 주요 기능

### 🎯 **MALE 정책 관리**
- **Accuracy**: 정확도 요구 수준 (0-1000)
- **Latency**: 지연 민감도 (0-1000)  
- **Energy**: 전력 효율 요구사항 (0-1000)

### 🔍 **다양한 워크로드 선택 방식**
- **특정 워크로드 직접 지정**: 이름과 네임스페이스로 정확한 타겟팅
- **라벨 셀렉터 기반**: 라벨 조건에 따른 동적 선택
- **네임스페이스별 정책**: 특정 네임스페이스 내 워크로드만 대상
- **글로벌 기본 정책**: 다른 정책이 없는 모든 워크로드 대상

### 📊 **실시간 정책 적용**
- Kubernetes Deployment에 어노테이션으로 정책 정보 저장
- Pod 환경변수를 통한 MALE 값 주입 (`MALE_ACCURACY`, `MALE_LATENCY`, `MALE_ENERGY`)
- 정책 변경 시 자동으로 워크로드에 반영
- 적용 상태 추적 및 모니터링

## 구현된 기능

### ✅ **핵심 기능**
- [x] MALEPolicy CRD 정의 및 관리
- [x] 워크로드 변경 감지 및 정책 적용
- [x] 라벨 셀렉터 기반 워크로드 매칭
- [x] 특정 워크로드 직접 지정 기능
- [x] 네임스페이스별 정책 분리
- [x] 정책 적용 상태 추적
- [x] 환경변수 및 어노테이션을 통한 MALE 값 주입

### ✅ **고급 기능**
- [x] 다중 라벨 조건 지원
- [x] 정책 우선순위 시스템 (TargetWorkloads > Selector > GlobalDefault)
- [x] 실시간 정책 변경 및 롤백
- [x] 워크로드별 세밀한 정책 제어

### 🌐 **Karmada 다중 클러스터 통합**
- [x] Karmada Work 리소스 자동 감지 및 정책 적용
- [x] 클러스터별 하드웨어 특성 자동 인식 및 분류
- [x] 클러스터 타입별 MALE 값 자동 조정 (GPU/Edge/CPU 클러스터)
- [x] 실제 클러스터 환경 기반 동적 정책 최적화
- [x] 멀티 클러스터 환경에서 워크로드별 정책 차별화

## 사용 예시

### 1. 특정 워크로드 직접 지정
```yaml
apiVersion: opensdi.opensdi.io/v1alpha1
kind: MALEPolicy
metadata:
  name: high-performance-policy
spec:
  accuracy: 950
  latency: 50
  energy: 400
  targetWorkloads:
  - name: critical-ai-model
    namespace: default
    kind: Deployment
  - name: ml-inference-service
    namespace: default
    kind: Deployment
  description: "Critical ML services with high performance requirements"
```

### 2. 라벨 셀렉터 기반 정책
```yaml
apiVersion: opensdi.opensdi.io/v1alpha1
kind: MALEPolicy
metadata:
  name: ml-development-policy
spec:
  accuracy: 700
  latency: 300
  energy: 800
  selector:
    type: "machine-learning"
    environment: "development"
  targetNamespaces:
  - "dev-ml"
  - "staging"
  description: "Development ML workloads with energy efficiency focus"
```

### 3. 글로벌 기본 정책
```yaml
apiVersion: opensdi.opensdi.io/v1alpha1
kind: MALEPolicy
metadata:
  name: global-default-policy
spec:
  accuracy: 600
  latency: 500
  energy: 700
  globalDefault: true
  description: "Default MALE policy for all workloads"
```

## 빠른 시작

### Prerequisites
- go version v1.24.0+
- kubectl version v1.11.3+
- Access to a Kubernetes cluster

### 설치 및 실행

1. **CRD 설치**
```bash
make install
```

2. **Controller 로컬 실행**
```bash
go run cmd/main.go --zap-log-level=info
```

3. **샘플 워크로드 배포**
```bash
kubectl apply -f test-workload.yaml
```

4. **MALEPolicy 적용**
```bash
kubectl apply -f config/samples/opensdi_v1alpha1_malepolicy.yaml
```

5. **정책 적용 결과 확인**
```bash
# 워크로드에 적용된 MALE 값 확인
kubectl get deployment ml-inference-service -o yaml | grep male-policy

# Pod 환경변수 확인
kubectl get pods -l app=ml-inference -o yaml | grep MALE

# 정책 상태 확인
kubectl get malepolicy -o yaml
```

### 실시간 정책 변경
```bash
# 정확도와 지연시간 값 변경
kubectl patch malepolicy malepolicy-sample --type='merge' \
  -p='{"spec":{"accuracy":900,"latency":100}}'

# 특정 워크로드 추가
kubectl patch malepolicy malepolicy-sample --type='merge' \
  -p='{"spec":{"targetWorkloads":[{"name":"new-ml-service","namespace":"default","kind":"Deployment"}]}}'
```

## 배포 및 운영

### 클러스터 배포
**Build and push your image:**
```sh
make docker-build docker-push IMG=<some-registry>/male-controller:tag
```

**Deploy to cluster:**
```sh
make deploy IMG=<some-registry>/male-controller:tag
```

## 예시 파일

프로젝트에는 다양한 사용 시나리오를 위한 예시 파일들이 포함되어 있습니다:

### 📁 **config/samples/**
- `opensdi_v1alpha1_malepolicy.yaml` - 기본 MALEPolicy 샘플

### 📁 **examples/**
- `specific-workload-policy.yaml` - 다양한 정책 적용 방식 예시
- `advanced-workloads.yaml` - 테스트용 고급 워크로드 예시

### 📁 **karmada-integration/**
- `test-real-cluster.yaml` - 실제 edge-cluster 대상 정책 테스트
- `auto-cluster-discovery.yaml` - 클러스터 자동 인식 설정 예시
- `test-multi-cluster-deployment.yaml` - 멀티 클러스터 배포 테스트
- `cluster-specific-policies.yaml` - 클러스터별 정책 차별화 예시

### 📁 **test files/**
- `test-workload.yaml` - 기본 테스트 워크로드
- `test-specific-policy.yaml` - 특정 워크로드 대상 정책

## API 참조

### MALEPolicySpec 필드

| 필드 | 타입 | 설명 | 범위 |
|-----|------|------|------|
| `accuracy` | int32 | 정확도 요구 수준 | 0-1000 |
| `latency` | int32 | 지연 민감도 | 0-1000 |
| `energy` | int32 | 전력 효율 요구사항 | 0-1000 |
| `selector` | map[string]string | 라벨 셀렉터 | optional |
| `targetWorkloads` | []WorkloadTarget | 직접 지정할 워크로드 목록 | optional |
| `targetNamespaces` | []string | 대상 네임스페이스 | optional |
| `globalDefault` | bool | 글로벌 기본 정책 여부 | optional |
| `description` | string | 정책 설명 | optional |

### 워크로드별 적용 결과

정책이 적용된 워크로드에서 확인할 수 있는 정보:

**Deployment Annotations:**
- `male-policy.opensdi.io/accuracy`: 적용된 정확도 값
- `male-policy.opensdi.io/latency`: 적용된 지연시간 값  
- `male-policy.opensdi.io/energy`: 적용된 전력효율 값
- `male-policy.opensdi.io/policy-name`: 적용된 정책 이름
- `male-policy.opensdi.io/applied-at`: 적용 시각

**Pod Environment Variables:**
- `MALE_ACCURACY`: 정확도 값
- `MALE_LATENCY`: 지연시간 값
- `MALE_ENERGY`: 전력효율 값

## 고급 사용법

### 정책 우선순위 시스템
1. **TargetWorkloads** (최우선): 특정 워크로드 이름으로 직접 지정
2. **Selector**: 라벨 조건에 따른 매칭
3. **GlobalDefault**: 다른 조건이 없을 때 모든 워크로드

### Karmada 다중 클러스터 통합

MALE Controller는 Karmada 환경에서 다중 클러스터 정책 적용을 지원합니다:

#### 🔧 **클러스터 자동 인식**
```yaml
# 실제 클러스터 하드웨어 정보를 기반으로 자동 분류
- edge-cluster: 40 CPU 코어, 128GB 메모리, K3s → "high-resource-edge" 타입으로 분류
- gpu-cluster: GPU가 있는 클러스터 → "gpu" 타입으로 분류
- cpu-cluster: 일반 CPU 클러스터 → "cpu" 타입으로 분류
```

#### 📊 **클러스터별 MALE 값 자동 조정**
```bash
# GPU 클러스터: 고성능 우선
accuracy: +100, latency: -50, energy: -100

# Edge 클러스터: 전력효율 우선  
accuracy: -100, latency: +100, energy: +200

# CPU 클러스터: 균형 유지
accuracy: 0, latency: 0, energy: +50
```

#### 🚀 **멀티 클러스터 테스트**
```bash
# 실제 edge-cluster에 정책 적용
kubectl apply -f karmada-integration/test-real-cluster.yaml

# 클러스터별 차별화된 정책 적용
kubectl apply -f karmada-integration/cluster-specific-policies.yaml

# 분산 ML 워크로드 배포
kubectl apply -f karmada-integration/test-multi-cluster-deployment.yaml
```

### 다중 정책 적용
```bash
# 여러 정책을 동시에 적용 (우선순위에 따라 처리)
kubectl apply -f examples/specific-workload-policy.yaml
```

### 정책 모니터링
```bash
# 모든 정책 상태 확인
kubectl get malepolicies -o wide

# 특정 정책 상세 정보
kubectl describe malepolicy <policy-name>

# 정책 적용 로그 확인
kubectl logs deployment/male-controller-controller-manager -n male-controller-system

# Karmada Work 리소스 확인
kubectl get works.work.karmada.io -A
```

## 제거

### 리소스 정리
```bash
# MALEPolicy 리소스 삭제
kubectl delete malepolicies --all

# CRD 삭제
make uninstall

# Controller 제거 (클러스터 배포된 경우)
make undeploy
```

## 기여하기

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)  
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### 개발 환경 설정
```bash
git clone <repository-url>
cd male-controller
make install    # CRD 설치
go run cmd/main.go --zap-log-level=debug  # 개발 모드 실행
```

**NOTE:** Run `make help` for more information on all potential `make` targets

More information can be found via the [Kubebuilder Documentation](https://book.kubebuilder.io/introduction.html)

## License

Copyright 2025.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

