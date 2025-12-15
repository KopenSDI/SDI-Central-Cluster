# MALE Operator 프로젝트 구조

## 프로젝트 개요

MALE Operator는 Kubernetes 워크로드의 Accuracy, Latency, Energy 값을 기반으로 혼합 중요도 점수를 계산하고 PriorityClass를 자동 할당하는 오퍼레이터입니다.

## 디렉토리 구조

```
male-operator/
├── api/
│   └── v1alpha1/
│       ├── groupversion_info.go          # API 그룹 버전 정의
│       ├── malepolicy_types.go           # MalePolicy CRD 타입
│       ├── malepolicy_validation.go      # MalePolicy 검증 로직
│       ├── malepolicy_webhook.go         # MalePolicy 웹훅 설정
│       ├── maleworkload_types.go         # MaleWorkload CRD 타입
│       ├── maleworkload_webhook.go       # MaleWorkload 웹훅 설정
│       └── zz_generated.deepcopy.go      # 자동 생성 DeepCopy 메서드
├── controllers/
│   ├── malepolicy_controller.go          # MalePolicy 리컨사일러
│   └── maleworkload_controller.go        # MaleWorkload 리컨사일러
├── internal/
│   ├── policy/
│   │   ├── calculator.go                 # 점수 계산 로직
│   │   └── calculator_test.go           # 점수 계산 테스트
│   ├── override/
│   │   ├── configmap.go                  # ConfigMap override 파서
│   │   └── webhook.go                    # Webhook override 캐시
│   └── webhook/
│       ├── mutating.go                    # Pod Mutating Webhook
│       ├── validating.go                  # CRD Validating Webhook
│       └── override_handler.go            # Override HTTP 핸들러
├── config/
│   ├── crd/
│   │   ├── bases/                        # CRD YAML (생성됨)
│   │   └── kustomization.yaml
│   ├── rbac/
│   │   ├── role.yaml                     # ClusterRole
│   │   ├── role_binding.yaml             # ClusterRoleBinding
│   │   └── service_account.yaml          # ServiceAccount
│   ├── manager/
│   │   ├── manager.yaml                  # Deployment
│   │   └── kustomization.yaml
│   ├── webhook/
│   │   ├── mutatingwebhook.yaml          # MutatingWebhookConfiguration
│   │   ├── validatingwebhook.yaml       # ValidatingWebhookConfiguration
│   │   ├── service.yaml                  # Webhook Service
│   │   └── kustomization.yaml
│   ├── default/
│   │   └── kustomization.yaml            # 전체 배포 통합
│   └── samples/
│       ├── male_v1alpha1_malepolicy.yaml # 샘플 MalePolicy
│       ├── male_v1alpha1_maleworkload.yaml # 샘플 MaleWorkload
│       └── override-configmap.yaml       # 샘플 Override ConfigMap
├── main.go                               # 오퍼레이터 진입점
├── Makefile                              # 빌드/배포 스크립트
├── Dockerfile                            # 컨테이너 이미지 빌드
├── go.mod                                # Go 모듈 정의
├── README.md                             # 프로젝트 문서
└── PROJECT.md                            # 이 파일
```

## 주요 컴포넌트

### 1. CRD (Custom Resource Definitions)

- **MalePolicy** (Cluster-scoped): 점수 계산 정책, 가중치, 버킷 정의
- **MaleWorkload** (Namespaced): 워크로드별 A,L,E 값 지정

### 2. Controllers

- **MalePolicyReconciler**: PriorityClass 동기화, 정책 검증
- **MaleWorkloadReconciler**: 점수 계산, override 적용, 워크로드 업데이트

### 3. Webhooks

- **Mutating Webhook**: Pod 생성 시 priorityClassName 주입
- **Validating Webhook**: CRD 스키마 검증 (가중치 합=1, 버킷 중첩 금지 등)

### 4. Internal Packages

- **policy**: 점수 계산, 버킷 매핑, 검증 로직
- **override**: ConfigMap/Webhook override 처리
- **webhook**: 웹훅 핸들러 구현

## 빌드 및 배포

```bash
# 코드 생성 (DeepCopy, CRD 등)
make generate
make manifests

# 빌드
make build

# 테스트
make test

# 이미지 빌드 및 배포
make docker-build IMG=<registry>/male-operator:latest
make docker-push IMG=<registry>/male-operator:latest
make deploy IMG=<registry>/male-operator:latest
```

## 개발 워크플로우

1. CRD 타입 수정 → `make generate`
2. 컨트롤러 로직 수정 → `make build && make test`
3. 매니페스트 생성 → `make manifests`
4. 로컬 테스트 → `make run`
5. 배포 → `make deploy`

## 다음 단계

- [ ] CRD 베이스 파일 생성 (`make manifests`)
- [ ] 통합 테스트 작성 (envtest)
- [ ] 인증서 관리 (cert-manager 연동)
- [ ] 메트릭 수집 (Prometheus)
- [ ] 문서화 보완

