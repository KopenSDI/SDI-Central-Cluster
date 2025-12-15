# MALE Operator

**MALE (Mixed Importance: Accuracy, Latency, Energy) Operator**는 Kubernetes 워크로드에 대해 A(Accuracy), L(Latency), E(Energy) 값을 기반으로 혼합 중요도 점수를 계산하고, 이를 PriorityClass로 자동 매핑하여 워크로드 우선순위를 자동으로 결정·주입하는 Kubernetes 오퍼레이터입니다.

---

## 📑 목차

- [개요](#개요)
- [아키텍처 및 동작 원리](#아키텍처-및-동작-원리)
- [빠른 시작](#빠른-시작)
- [상세 설치 가이드](#상세-설치-가이드)
- [사용 방법](#사용-방법)
- [동작 흐름 상세 설명](#동작-흐름-상세-설명)
- [Override 메커니즘](#override-메커니즘)
- [트러블슈팅](#트러블슈팅)
- [참고 자료](#참고-자료)

---

## 📖 개요

### MALE Operator란?

MALE Operator는 AI/ML 워크로드의 **Accuracy(정확도)**, **Latency(지연시간)**, **Energy(에너지)** 세 가지 차원의 중요도를 종합하여 워크로드의 우선순위를 자동으로 결정하는 Kubernetes 오퍼레이터입니다.

### 주요 기능

✅ **자동 우선순위 결정**: A, L, E 값을 기반으로 혼합 중요도 점수를 계산하고 PriorityClass를 자동 할당  
✅ **정책 엔진 Override**: ConfigMap 또는 Webhook을 통한 동적 중요도 값 보정  
✅ **자동 PriorityClass 관리**: 정책에 정의된 버킷에 따라 PriorityClass를 자동 생성/업데이트  
✅ **Pod 자동 주입**: Mutating Webhook을 통한 Pod 생성 시점 priorityClassName 자동 주입  
✅ **유연한 정책 관리**: 클러스터 단위의 정책 설정으로 일관된 우선순위 관리

### 혼합 중요도 점수 계산

MALE Operator는 다음 수식을 사용하여 혼합 중요도 점수를 계산합니다:

```
MixedImportance = wA × A + wL × L + wE × E
```

**변수 설명:**
- `wA`, `wL`, `wE`: 정책에서 정의된 가중치 (합이 1.0이어야 함)
- `A`, `L`, `E`: 워크로드의 중요도 값 (0~1 범위)
- 결과값: 0~1 범위의 점수

**예시:**
```
가중치: wA=0.5, wL=0.3, wE=0.2
중요도: A=0.7, L=0.8, E=0.2
점수: 0.5×0.7 + 0.3×0.8 + 0.2×0.2 = 0.35 + 0.24 + 0.04 = 0.63
```

점수는 0~1 범위로 계산되며, 정책에 정의된 Priority 버킷에 따라 PriorityClass가 할당됩니다.

---

## 🏗️ 아키텍처 및 동작 원리

### 전체 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────┐         ┌──────────────────┐            │
│  │   MalePolicy     │────────▶│  PriorityClass   │            │
│  │  (Cluster-scoped)│         │   (Auto-gen)     │            │
│  │                  │         │                  │            │
│  │ - Weights        │         │ - male-low       │            │
│  │ - Bounds         │         │ - male-medium    │            │
│  │ - Buckets        │         │ - male-high      │            │
│  │ - Override Config│         │ - male-critical  │            │
│  └────────┬─────────┘         └──────────────────┘            │
│           │                                                     │
│           │                                                     │
│           ▼                                                     │
│  ┌──────────────────┐         ┌──────────────────┐            │
│  │  MaleWorkload    │────────▶│   Deployment     │            │
│  │  (Namespaced)    │         │   /StatefulSet   │            │
│  │                  │         │   /Job           │            │
│  │ - TargetRef      │         │                  │            │
│  │ - Importance     │         │ - Labels         │            │
│  │ - Override Flag  │         │ - Annotations    │            │
│  └────────┬─────────┘         └────────┬─────────┘            │
│           │                             │                       │
│           │                             ▼                       │
│           │                    ┌──────────────┐                 │
│           │                    │     Pod      │                 │
│           │                    │              │                 │
│           │                    │ - Labels     │                 │
│           │                    │ - Annotations│                 │
│           └────────────────────┼──────────────┼─────────────────┘
│                                │              │                 │
│                                ▼              ▼                 │
│                    ┌──────────────────────────────────┐        │
│                    │     Mutating Webhook             │        │
│                    │  (priorityClassName 주입)        │        │
│                    └──────────────────────────────────┘        │
│                                                                 │
│  ┌──────────────────────────────────────────────┐             │
│  │         Override Sources                     │             │
│  │  ┌──────────────┐  ┌──────────────────┐   │             │
│  │  │  ConfigMap   │  │  Webhook API     │   │             │
│  │  │  (kube-system│  │  (/override)     │   │             │
│  │  │  /male-...)  │  │                  │   │             │
│  │  └──────────────┘  └──────────────────┘   │             │
│  └──────────────────────────────────────────────┘             │
└─────────────────────────────────────────────────────────────────┘
```

### 컴포넌트 구조

#### 1. **CRD (Custom Resource Definitions)**

- **MalePolicy** (Cluster-scoped)
  - 클러스터 전체에 적용되는 정책 정의
  - 가중치, 경계값, Priority 버킷, Override 설정 포함

- **MaleWorkload** (Namespaced)
  - 특정 워크로드에 대한 중요도 값 지정
  - 타겟 리소스(Deployment/StatefulSet/Job) 참조

#### 2. **Controllers**

- **MalePolicyReconciler**
  - MalePolicy 변경 감지
  - PriorityClass 자동 생성/업데이트
  - 정책 검증 및 상태 업데이트

- **MaleWorkloadReconciler**
  - MaleWorkload 변경 감지
  - 중요도 값 수집 및 Override 적용
  - 혼합 점수 계산 및 Priority 버킷 매핑
  - 타겟 워크로드에 라벨/애노테이션 주입

#### 3. **Webhooks**

- **Mutating Webhook**
  - Pod 생성 시점에 priorityClassName 자동 주입
  - 라벨/애노테이션 추가

- **Validating Webhook**
  - MalePolicy/MaleWorkload 스키마 검증
  - 가중치 합=1 검증, 버킷 중첩 금지 등

#### 4. **Internal Packages**

- **policy**: 점수 계산, 버킷 매핑, 검증 로직
- **override**: ConfigMap/Webhook override 처리
- **webhook**: 웹훅 핸들러 구현

---

## 🚀 빠른 시작

### 1. 사전 요구사항

```bash
# Kubernetes 클러스터 확인
kubectl cluster-info

# Go 1.22+ 설치 확인
go version

# controller-gen, kustomize 설치 (자동 설치됨)
make controller-gen
make kustomize
```

### 2. 프로젝트 클론 및 빌드

```bash
cd /root/KETI_SDI_Central_Cluster/deploy/SDI/male-operator

# 의존성 설치
go mod tidy

# 코드 생성 및 매니페스트 생성
make generate
make manifests

# 빌드
make build
```

### 3. CRD 설치

```bash
# CRD 설치
make install

# 확인
kubectl get crd | grep male
```

### 4. 샘플 리소스 적용

```bash
# MalePolicy 생성
kubectl apply -f config/samples/male_v1alpha1_malepolicy.yaml

# MaleWorkload 생성 (Deployment 포함)
kubectl apply -f config/samples/male_v1alpha1_maleworkload.yaml

# 확인
kubectl get malepolicy
kubectl get maleworkload
```

### 5. 오퍼레이터 실행

**옵션 1: 로컬 실행 (개발용)**
```bash
make run
```

**옵션 2: 클러스터 배포**
```bash
# 이미지 빌드 및 푸시
make docker-build IMG=<your-registry>/male-operator:latest
make docker-push IMG=<your-registry>/male-operator:latest

# 배포
make deploy IMG=<your-registry>/male-operator:latest
```

---

## 📚 상세 설치 가이드

### 단계 1: 프로젝트 준비

```bash
# 프로젝트 디렉토리로 이동
cd /root/KETI_SDI_Central_Cluster/deploy/SDI/male-operator

# Go 모듈 의존성 다운로드
go mod download

# 코드 생성 (DeepCopy 메서드 등)
make generate
```

**예상 출력:**
```
controller-gen object:headerFile="hack/boilerplate.go.txt" paths="./..."
```

### 단계 2: CRD 및 RBAC 매니페스트 생성

```bash
# CRD, RBAC, Webhook 매니페스트 생성
make manifests
```

**생성되는 파일:**
- `config/crd/bases/male.keti.dev_malepolicies.yaml`
- `config/crd/bases/male.keti.dev_maleworkloads.yaml`
- `config/rbac/role.yaml`
- `config/rbac/role_binding.yaml`
- `config/webhook/` 디렉토리의 웹훅 매니페스트

### 단계 3: CRD 설치

```bash
# CRD 설치
kubectl apply -f config/crd/bases/

# 설치 확인
kubectl get crd malepolicies.male.keti.dev
kubectl get crd maleworkloads.male.keti.dev
```

**예상 출력:**
```
NAME                              CREATED AT
malepolicies.male.keti.dev       2025-12-09T02:20:02Z
maleworkloads.male.keti.dev      2025-12-09T02:20:02Z
```

### 단계 4: RBAC 설치

```bash
# 네임스페이스 생성
kubectl create namespace male-operator-system

# RBAC 설치
kubectl apply -f config/rbac/service_account.yaml
kubectl apply -f config/rbac/role.yaml
kubectl apply -f config/rbac/role_binding.yaml
```

### 단계 5: 오퍼레이터 배포

**방법 A: 로컬 실행 (개발/테스트용)**

```bash
# 로컬에서 실행 (백그라운드)
make run

# 또는 직접 실행
go run ./main.go
```

**방법 B: 클러스터 배포 (프로덕션용)**

```bash
# 1. 이미지 빌드
docker build -t <your-registry>/male-operator:latest .

# 2. 이미지 푸시
docker push <your-registry>/male-operator:latest

# 3. Deployment 매니페스트 수정
cd config/manager
kustomize edit set image controller=<your-registry>/male-operator:latest

# 4. 배포
cd ../..
kubectl apply -k config/default/

# 5. 배포 확인
kubectl get pods -n male-operator-system
kubectl logs -f deployment/male-operator-controller-manager -n male-operator-system
```

### 단계 6: 웹훅 인증서 설정 (선택사항)

웹훅을 사용하려면 인증서가 필요합니다. cert-manager를 사용하는 경우:

```bash
# cert-manager 설치 (없는 경우)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# 인증서 발급 대기
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s
```

---

## 📖 사용 방법

### 1. MalePolicy 생성

MalePolicy는 클러스터 범위 리소스로, 점수 계산 방식과 Priority 버킷을 정의합니다.

**기본 예시:**

```yaml
apiVersion: male.keti.dev/v1alpha1
kind: MalePolicy
metadata:
  name: default-male-policy
spec:
  # 가중치 설정 (합이 1.0이어야 함)
  weights:
    accuracy: 0.5  # 정확도 가중치
    latency: 0.3   # 지연시간 가중치
    energy: 0.2    # 에너지 가중치
  
  # 중요도 값의 경계 설정
  bounds:
    accuracy: {min: 0.0, max: 1.0}
    latency: {min: 0.0, max: 1.0}
    energy: {min: 0.0, max: 1.0}
  
  # Override 설정
  override:
    enabled: true
    source:
      type: ConfigMap
      name: male-policy-overrides
      namespace: kube-system
  
  # Priority 버킷 정의
  priorityBuckets:
    - name: male-low
      min: 0.0
      max: 0.29
      priorityValue: 100
    - name: male-medium
      min: 0.30
      max: 0.59
      priorityValue: 1000
    - name: male-high
      min: 0.60
      max: 0.79
      priorityValue: 10000
    - name: male-critical
      min: 0.80
      max: 1.0
      priorityValue: 100000
```

**적용:**

```bash
kubectl apply -f config/samples/male_v1alpha1_malepolicy.yaml
```

**확인:**

```bash
# MalePolicy 확인
kubectl get malepolicy default-male-policy -o yaml

# 생성된 PriorityClass 확인
kubectl get priorityclass | grep male
```

### 2. MaleWorkload 생성

MaleWorkload는 네임스페이스 범위 리소스로, 특정 워크로드에 A, L, E 값을 지정합니다.

**기본 예시:**

```yaml
apiVersion: male.keti.dev/v1alpha1
kind: MaleWorkload
metadata:
  name: llm-inference-workload
  namespace: default
spec:
  # 타겟 워크로드 지정
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-llm
  
  # 워크로드 미션 이름
  mission: "llm-inference"
  
  # 중요도 값 (0~1 범위)
  importance:
    accuracy: 0.7  # 정확도 중요도
    latency: 0.8   # 지연시간 중요도
    energy: 0.2    # 에너지 중요도
  
  # 정책 Override 허용 여부
  allowPolicyOverride: true
  
  # 스케줄링 힌트
  schedulingHints:
    addLabels:
      "male.keti.dev/mission": "llm-inference"
    addAnnotations:
      "male.keti.dev/score-source": "operator"
```

**적용:**

```bash
kubectl apply -f config/samples/male_v1alpha1_maleworkload.yaml
```

**확인:**

```bash
# MaleWorkload 확인
kubectl get maleworkload llm-inference-workload -n default -o yaml

# 계산된 점수 확인
kubectl get maleworkload llm-inference-workload -n default -o jsonpath='{.status.mixedScore}'

# 할당된 PriorityClass 확인
kubectl get maleworkload llm-inference-workload -n default -o jsonpath='{.status.priorityClassName}'
```

### 3. 워크로드 확인

**Deployment 확인:**

```bash
# 라벨 및 애노테이션 확인
kubectl get deployment my-llm -n default -o yaml | grep -A 10 "labels:"
kubectl get deployment my-llm -n default -o yaml | grep -A 10 "annotations:"
```

**Pod 확인:**

```bash
# Pod의 priorityClassName 확인
kubectl get pod -l app=llm-inference -n default -o jsonpath='{.items[0].spec.priorityClassName}'

# Pod의 라벨 확인
kubectl get pod -l app=llm-inference -n default -o jsonpath='{.items[0].metadata.labels}'
```

---

## 🔄 동작 흐름 상세 설명

### 전체 동작 흐름

```
1. 사용자가 MalePolicy 생성
   ↓
2. MalePolicyReconciler가 감지
   ↓
3. PriorityClass 자동 생성 (male-low, male-medium, male-high, male-critical)
   ↓
4. 사용자가 MaleWorkload 생성
   ↓
5. MaleWorkloadReconciler가 감지
   ↓
6. MalePolicy에서 가중치 및 버킷 정보 로드
   ↓
7. Override 소스 확인 (ConfigMap 또는 Webhook)
   ↓
8. 중요도 값에 Override 적용 (있는 경우)
   ↓
9. Bounds로 값 클램핑
   ↓
10. 혼합 점수 계산: MixedScore = wA×A + wL×L + wE×E
   ↓
11. Priority 버킷 매핑 (점수 범위에 따라)
   ↓
12. 타겟 워크로드(Deployment)에 라벨/애노테이션 주입
   ↓
13. MaleWorkload Status 업데이트 (mixedScore, priorityClassName)
   ↓
14. Pod 생성 시 Mutating Webhook이 priorityClassName 주입
```

### 상세 단계 설명

#### 단계 1-3: MalePolicy 처리

```bash
# 1. MalePolicy 생성
kubectl apply -f config/samples/male_v1alpha1_malepolicy.yaml

# 2. Controller가 감지하고 처리
# - 가중치 검증 (합=1.0)
# - 버킷 검증 (중첩 없음)
# - PriorityClass 생성

# 3. 확인
kubectl get priorityclass | grep male
```

**예상 출력:**
```
NAME            VALUE    GLOBAL-DEFAULT   AGE
male-low        100      false            10s
male-medium     1000     false            10s
male-high       10000    false            10s
male-critical   100000   false            10s
```

#### 단계 4-13: MaleWorkload 처리

```bash
# 4. MaleWorkload 생성
kubectl apply -f config/samples/male_v1alpha1_maleworkload.yaml

# 5-13. Controller가 자동 처리
# - 중요도 값 수집
# - Override 적용
# - 점수 계산
# - 버킷 매핑
# - 워크로드 업데이트
# - Status 업데이트
```

**점수 계산 예시:**

```
입력:
  - 중요도: A=0.7, L=0.8, E=0.2
  - 가중치: wA=0.5, wL=0.3, wE=0.2

계산:
  MixedScore = 0.5×0.7 + 0.3×0.8 + 0.2×0.2
            = 0.35 + 0.24 + 0.04
            = 0.63

버킷 매핑:
  0.63 ∈ [0.60, 0.79] → male-high (value: 10000)
```

**확인:**

```bash
# Status 확인
kubectl get maleworkload llm-inference-workload -n default -o yaml | grep -A 10 "status:"

# 예상 출력:
# status:
#   effectiveImportance:
#     accuracy: 0.7
#     latency: 0.8
#     energy: 0.2
#   mixedScore: 0.63
#   priorityClassName: male-high
#   lastEvaluationTime: "2025-12-09T02:30:00Z"
```

#### 단계 14: Pod 생성 시 Webhook 처리

```bash
# Pod 생성 (Deployment에 의해 자동 생성됨)
kubectl get pods -l app=llm-inference -n default

# Mutating Webhook이 자동으로 priorityClassName 주입
kubectl get pod <pod-name> -n default -o jsonpath='{.spec.priorityClassName}'
# 출력: male-high
```

---

## 🔧 Override 메커니즘

### ConfigMap Override

정책 엔진이 ConfigMap에서 override 값을 읽어 중요도를 보정할 수 있습니다.

#### ConfigMap 생성

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: male-policy-overrides
  namespace: kube-system
data:
  # 특정 워크로드 Override: <namespace>.<maleworkload-name>.json
  default.llm-inference-workload.json: |
    {
      "accuracy": 0.75,
      "latency": 0.9,
      "energy": 0.1,
      "reason": "night-traffic-peak"
    }
  
  # 공용 Override: <maleworkload-name>.json
  # example-workload.json: |
  #   {
  #     "accuracy": 0.8,
  #     "latency": 0.7,
  #     "energy": 0.3
  #   }
```

**키 형식:**
- 특정 워크로드: `<namespace>.<maleworkload-name>.json`
- 공용: `<maleworkload-name>.json`

**적용:**

```bash
kubectl apply -f config/samples/override-configmap.yaml
```

**동작:**
1. MaleWorkloadReconciler가 ConfigMap을 읽음
2. 해당 워크로드의 override 값이 있으면 적용
3. Bounds로 클램핑
4. 새로운 점수 계산 및 버킷 매핑
5. 워크로드 및 Status 업데이트

### Webhook Override

HTTP POST 요청을 통해 override 값을 설정할 수 있습니다.

**요청 예시:**

```bash
curl -X POST https://male-operator-webhook:9443/override \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "default",
    "name": "llm-inference-workload",
    "accuracy": 0.75,
    "latency": 0.9,
    "energy": 0.1,
    "ttlSeconds": 3600
  }'
```

**응답:**

```json
{
  "status": "success",
  "namespace": "default",
  "name": "llm-inference-workload",
  "expiresAt": "2025-12-09T03:30:00Z"
}
```

**동작:**
1. Webhook이 override 값을 받아 메모리 캐시에 저장
2. TTL(Time To Live) 설정으로 자동 만료
3. MaleWorkloadReconciler가 캐시에서 값을 읽어 적용
4. ConfigMap보다 우선순위가 높음

**Override 우선순위:**
1. Webhook Override (최우선)
2. ConfigMap Override
3. 기본값 (MaleWorkload.spec.importance)

---

## 🏷️ 라벨 및 애노테이션

### Pod 라벨

MALE Operator가 자동으로 추가하는 라벨:

- `male.keti.dev/workload`: 워크로드 식별자 (`<namespace>.<name>`)
  ```yaml
  labels:
    male.keti.dev/workload: "default.llm-inference-workload"
  ```

- `male.keti.dev/mission`: 워크로드 미션 이름
  ```yaml
  labels:
    male.keti.dev/mission: "llm-inference"
  ```

- `male.keti.dev/force`: "true"로 설정 시 기존 priorityClassName을 덮어씀
  ```yaml
  labels:
    male.keti.dev/force: "true"
  ```

### Pod 애노테이션

MALE Operator가 자동으로 추가하는 애노테이션:

- `male.keti.dev/priority-class`: 할당된 PriorityClass 이름
  ```yaml
  annotations:
    male.keti.dev/priority-class: "male-high"
  ```

- `male.keti.dev/mixed-score`: 계산된 혼합 중요도 점수
  ```yaml
  annotations:
    male.keti.dev/mixed-score: "0.630"
  ```

- `male.keti.dev/score-source`: 점수 소스
  ```yaml
  annotations:
    male.keti.dev/score-source: "operator"
  ```

### 확인 방법

```bash
# Deployment의 Pod 템플릿 확인
kubectl get deployment my-llm -n default -o yaml | grep -A 20 "template:"

# Pod의 라벨/애노테이션 확인
kubectl get pod <pod-name> -n default -o yaml | grep -A 10 "labels:"
kubectl get pod <pod-name> -n default -o yaml | grep -A 10 "annotations:"
```

---

## 🧪 테스트

### 유닛 테스트

```bash
# 모든 테스트 실행
make test

# 특정 패키지 테스트
go test ./internal/policy/... -v

# 커버리지 확인
go test ./... -coverprofile cover.out
go tool cover -html=cover.out
```

### 통합 테스트

```bash
# 통합 테스트 스크립트 실행
./test_integration.sh

# 수동 테스트
go run test_manual.go
```

### 수동 테스트

```bash
# 1. CRD 설치
make install

# 2. 샘플 리소스 적용
kubectl apply -f config/samples/male_v1alpha1_malepolicy.yaml
kubectl apply -f config/samples/male_v1alpha1_maleworkload.yaml

# 3. 오퍼레이터 실행 (다른 터미널)
make run

# 4. 상태 확인
kubectl get malepolicy default-male-policy -o yaml
kubectl get maleworkload llm-inference-workload -n default -o yaml
kubectl get priorityclass | grep male
kubectl get deployment my-llm -n default -o yaml
```

---

## 🔍 트러블슈팅

### 문제 1: CRD가 설치되지 않음

**증상:**
```bash
$ kubectl get crd | grep male
# 출력 없음
```

**해결:**
```bash
# 매니페스트 재생성
make manifests

# CRD 재설치
kubectl apply -f config/crd/bases/

# 확인
kubectl get crd malepolicies.male.keti.dev
```

### 문제 2: 오퍼레이터가 리소스를 처리하지 않음

**증상:**
- MaleWorkload의 status가 업데이트되지 않음
- PriorityClass가 생성되지 않음

**해결:**
```bash
# 오퍼레이터 로그 확인
kubectl logs -f deployment/male-operator-controller-manager -n male-operator-system

# 오퍼레이터 재시작
kubectl rollout restart deployment/male-operator-controller-manager -n male-operator-system

# RBAC 확인
kubectl get clusterrole male-operator-manager-role -o yaml
```

### 문제 3: Validating Webhook 오류

**증상:**
```bash
$ kubectl apply -f config/samples/male_v1alpha1_malepolicy.yaml
Error from server: error when creating "male_v1alpha1_malepolicy.yaml": 
admission webhook "vmalepolicy.kb.io" denied the request: weights must sum to 1.0
```

**해결:**
- 가중치의 합이 정확히 1.0인지 확인
- YAML 파일의 값 확인

### 문제 4: Pod에 priorityClassName이 주입되지 않음

**증상:**
```bash
$ kubectl get pod <pod-name> -o jsonpath='{.spec.priorityClassName}'
# 출력 없음
```

**해결:**
```bash
# Mutating Webhook 확인
kubectl get mutatingwebhookconfiguration mmalepolicy.kb.io -o yaml

# Pod 라벨 확인 (워크로드 식별자 필요)
kubectl get pod <pod-name> -o jsonpath='{.metadata.labels.male\.keti\.dev/workload}'

# Webhook 로그 확인
kubectl logs -f deployment/male-operator-controller-manager -n male-operator-system | grep webhook
```

### 문제 5: Override가 적용되지 않음

**증상:**
- ConfigMap에 override 값을 설정했지만 적용되지 않음

**해결:**
```bash
# ConfigMap 확인
kubectl get configmap male-policy-overrides -n kube-system -o yaml

# 키 형식 확인 (<namespace>.<name>.json)
kubectl get configmap male-policy-overrides -n kube-system -o jsonpath='{.data}'

# MalePolicy의 Override 설정 확인
kubectl get malepolicy default-male-policy -o jsonpath='{.spec.override}'

# MaleWorkload의 allowPolicyOverride 확인
kubectl get maleworkload <name> -n <namespace> -o jsonpath='{.spec.allowPolicyOverride}'
```

---

## 📊 모니터링 및 디버깅

### 로그 확인

```bash
# 오퍼레이터 로그
kubectl logs -f deployment/male-operator-controller-manager -n male-operator-system

# 특정 리소스 이벤트 확인
kubectl describe malepolicy default-male-policy
kubectl describe maleworkload llm-inference-workload -n default
```

### 상태 확인

```bash
# MalePolicy 상태
kubectl get malepolicy default-male-policy -o jsonpath='{.status}'

# MaleWorkload 상태
kubectl get maleworkload llm-inference-workload -n default -o jsonpath='{.status}'

# Conditions 확인
kubectl get malepolicy default-male-policy -o jsonpath='{.status.conditions}'
```

### 디버깅 팁

1. **오퍼레이터가 리소스를 감지하는지 확인**
   ```bash
   kubectl get malepolicy --watch
   kubectl get maleworkload --watch
   ```

2. **점수 계산 확인**
   ```bash
   kubectl get maleworkload <name> -n <namespace> -o jsonpath='{.status.mixedScore}'
   ```

3. **Priority 버킷 매핑 확인**
   ```bash
   kubectl get maleworkload <name> -n <namespace> -o jsonpath='{.status.priorityClassName}'
   ```

---

## ⚠️ 한계 및 주의사항

### 현재 한계

1. **단일 정책만 지원**: 현재는 첫 번째 MalePolicy만 사용됩니다. 향후 라벨 기반 선택 지원 예정
2. **Override 우선순위**: Webhook > ConfigMap > 기본값 순서로 적용됩니다
3. **Pod 재시작 필요**: 기존 Pod는 재생성되어야 priorityClassName이 적용됩니다
4. **Float 타입 사용**: CRD에서 float64 타입 사용 시 `allowDangerousTypes=true` 옵션 필요

### 주의사항

1. **가중치 합 검증**: 가중치의 합이 정확히 1.0이어야 합니다 (부동소수점 오차 허용: ±0.001)
2. **버킷 중첩 금지**: Priority 버킷은 서로 겹치지 않아야 합니다
3. **네임스페이스**: MalePolicy는 Cluster-scoped이므로 클러스터당 하나만 권장됩니다

---

## 🗺️ 향후 로드맵

- [ ] 스케줄러 플러그인 연계 (Kubernetes Scheduler Framework)
- [ ] 다중 정책 지원 및 라벨 기반 선택
- [ ] 메트릭 수집 및 대시보드 (Prometheus/Grafana)
- [ ] 실시간 점수 모니터링 및 알림
- [ ] 워크로드 히스토리 및 트렌드 분석
- [ ] 자동 튜닝 (AutoML 기반 가중치 최적화)
- [ ] 웹 UI 대시보드

---

## 📝 참고 자료

### 관련 문서

- [Kubernetes Operator Pattern](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/)
- [Kubebuilder Documentation](https://book.kubebuilder.io/)
- [controller-runtime](https://pkg.go.dev/sigs.k8s.io/controller-runtime)
- [PriorityClass](https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/)

### 프로젝트 구조

```
male-operator/
├── api/v1alpha1/          # CRD 타입 정의
├── controllers/           # 리컨사일러 구현
├── internal/              # 내부 패키지
│   ├── policy/           # 점수 계산 로직
│   ├── override/         # Override 처리
│   └── webhook/          # 웹훅 핸들러
├── config/               # 배포 매니페스트
│   ├── crd/             # CRD 정의
│   ├── rbac/            # RBAC 설정
│   ├── manager/         # Deployment
│   └── samples/         # 샘플 리소스
└── main.go              # 진입점
```

### 유용한 명령어

```bash
# 프로젝트 빌드
make build

# 테스트 실행
make test

# 매니페스트 생성
make manifests

# CRD 설치/제거
make install
make uninstall

# 배포/제거
make deploy IMG=<image>
make undeploy
```

---

## 📄 라이선스

Apache License 2.0

---

## 👥 기여

이슈 및 PR을 환영합니다!

**문의사항이나 문제가 있으면 이슈를 등록해주세요.**
