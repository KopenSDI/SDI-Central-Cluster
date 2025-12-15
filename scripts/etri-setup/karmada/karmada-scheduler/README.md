# SDI Karmada Scheduler - ETRI 설치 가이드

## 📦 설치 파일

```
/root/KETI_SDI_Central_Cluster/scripts/etri-setup/karmada/karmada-scheduler/
├── sdi-scheduler-deployment.yaml    # SDI 스케줄러 배포 파일
└── README.md                         # 이 파일
```

## 🚀 빠른 설치

### 사전 요구사항

- Karmada가 설치되어 있어야 함
- `karmada-system` 네임스페이스 존재
- `karmada-cert` Secret 존재

### 설치 명령

```bash
# 1. SDI 스케줄러 배포
kubectl apply -f sdi-scheduler-deployment.yaml

# 2. 배포 확인
kubectl get pods -n karmada-system -l app=sdi-scheduler

# 3. 로그 확인
kubectl logs -n karmada-system -l app=sdi-scheduler --tail=50
```

## 📋 설치 검증

### 1. 파드 상태 확인

```bash
kubectl get pods -n karmada-system -l app=sdi-scheduler
# NAME                            READY   STATUS    RESTARTS   AGE
# sdi-scheduler-xxx-yyy           1/1     Running   0          30s
```

### 2. SDI 플러그인 활성화 확인

```bash
kubectl logs -n karmada-system -l app=sdi-scheduler --tail=50 | grep SDI
# 출력 예시:
# {"msg":"Enable Scheduler plugin \"SDIScheduler\""}
# [SDI] analysis engine fetch failed... (정상 - fallback 모드)
```

### 3. Health Check

```bash
kubectl exec -n karmada-system -l app=sdi-scheduler -- \
  wget -qO- http://localhost:10351/healthz
# 출력: ok
```

## 🎯 사용 방법

### PropagationPolicy에서 SDI 스케줄러 지정

```yaml
apiVersion: policy.karmada.io/v1alpha1
kind: PropagationPolicy
metadata:
  name: my-policy
  namespace: default
spec:
  schedulerName: sdi-scheduler  # SDI 스케줄러 사용!
  resourceSelectors:
    - apiVersion: apps/v1
      kind: Deployment
      name: my-app
  placement:
    clusterAffinity:
      clusterNames:
        - member1
        - member2
```

## ⚙️ 설정 변경

### 환경 변수 (ALE 파라미터) 수정

```bash
# ConfigMap 수정
kubectl edit configmap sdi-scheduler-env -n karmada-system

# 또는 직접 업데이트
kubectl patch configmap sdi-scheduler-env -n karmada-system --type merge -p '
data:
  MALE_ACCURACY: "95"
  MALE_LATENCY: "50"
  MALE_ENERGY: "30"
'

# 스케줄러 재시작
kubectl rollout restart deployment sdi-scheduler -n karmada-system
```

### 로그 레벨 변경

```bash
kubectl edit deployment sdi-scheduler -n karmada-system
# args에서 --v=4를 원하는 레벨로 변경 (2, 4, 6 등)

# 또는 직접 패치
kubectl patch deployment sdi-scheduler -n karmada-system --type json -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/args/5",
    "value": "--v=6"
  }
]'
```

## 🔧 문제 해결

### 파드가 시작되지 않는 경우

```bash
# 상세 정보 확인
kubectl describe pod -n karmada-system -l app=sdi-scheduler

# 일반적인 문제:
# 1. karmada-cert Secret 없음
kubectl get secret karmada-cert -n karmada-system

# 2. 이미지를 가져올 수 없음
# - Docker Hub 로그인 확인
# - imagePullSecrets 필요 시 추가
```

### Secret 관련 에러

```bash
# karmada-cert Secret이 없는 경우
# Karmada 설치 시 생성된 Secret을 사용해야 함

# 확인
kubectl get secret -n karmada-system | grep karmada
```

### Analysis Engine 연결

기본적으로 Analysis Engine 연결 실패는 정상입니다. (Fallback 모드)

환경 변수로 ALE 파라미터를 설정할 수 있습니다:
- `MALE_ACCURACY`: 정확도 목표 (%)
- `MALE_LATENCY`: 지연시간 예산 (ms)
- `MALE_ENERGY`: 전력 예산 (Watt)
- `SERVICE_TYPE`: 서비스 타입

## 🗑️ 제거

```bash
kubectl delete -f sdi-scheduler-deployment.yaml
```

## 📊 모니터링

### 메트릭 확인

```bash
# 메트릭 서비스 포트포워딩
kubectl port-forward -n karmada-system svc/sdi-scheduler-metrics 8080:8080

# 메트릭 조회
curl http://localhost:8080/metrics | grep scheduler
```

### 로그 모니터링

```bash
# 실시간 로그
kubectl logs -n karmada-system -l app=sdi-scheduler --tail=100 -f

# SDI 관련 로그만
kubectl logs -n karmada-system -l app=sdi-scheduler --tail=200 | grep -i sdi

# 에러 로그
kubectl logs -n karmada-system -l app=sdi-scheduler --tail=200 | grep -i error
```

## 📚 추가 정보

### Docker 이미지

- **이미지**: `ketidevit2/karmada-multicluster-scheduler:0.0.1`
- **Registry**: Docker Hub
- **Pull Policy**: Always

### SDI 스케줄링 알고리즘

1. **Intent-driven**: 사용자 의도 기반 스케줄링
2. **Predictive Context**: 예측 기반 스케줄링
3. **Collaborative Swarm**: 협업 기반 스케줄링

### 리소스 요구사항

- **CPU**: 100m (request), 500m (limit)
- **Memory**: 256Mi (request), 512Mi (limit)

---

**설치 문의**: KETI SDI 팀
**작성일**: 2025-11-27












