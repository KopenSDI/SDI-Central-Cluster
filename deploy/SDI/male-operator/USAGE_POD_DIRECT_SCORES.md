# Pod에 직접 점수 붙이기 사용법

## 개요

MALE 오퍼레이터는 이제 Pod에 직접 점수를 붙여서 사용할 수 있습니다. MaleWorkload 리소스를 생성하지 않아도 Pod의 라벨이나 애노테이션에 점수를 지정하면 자동으로 처리됩니다.

## 사용 방법

### 방법 1: 라벨로 점수 지정

```bash
kubectl run my-pod --image=nginx:latest \
  --labels="male.keti.dev/accuracy=0.8,male.keti.dev/latency=0.9,male.keti.dev/energy=0.3"
```

### 방법 2: 애노테이션으로 점수 지정

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
  annotations:
    male.keti.dev/accuracy: "0.7"
    male.keti.dev/latency: "0.8"
    male.keti.dev/energy: "0.2"
spec:
  containers:
  - name: app
    image: nginx:latest
```

### 방법 3: YAML 파일로 생성

```bash
kubectl apply -f config/samples/pod-with-direct-scores.yaml
```

## 점수 형식

- **키**: `male.keti.dev/accuracy`, `male.keti.dev/latency`, `male.keti.dev/energy`
- **값**: 0.0 ~ 1.0 사이의 숫자 (문자열로 지정 가능)
- **필수**: 세 가지 값 모두 지정해야 함

## 우선순위

1. **Pod 라벨/애노테이션의 직접 점수** (최우선)
2. MaleWorkload 리소스의 점수
3. Override 값 (ConfigMap/Webhook)

## 동작 확인

```bash
# Pod 생성
kubectl apply -f config/samples/pod-with-direct-scores.yaml

# priorityClassName 확인
kubectl get pod test-pod-with-scores -n default -o jsonpath='{.spec.priorityClassName}'

# 계산된 점수 확인
kubectl get pod test-pod-with-scores -n default -o jsonpath='{.metadata.annotations.male\.keti\.dev/mixed-score}'

# 전체 정보 확인
kubectl get pod test-pod-with-scores -n default -o yaml | grep -E "priorityClassName|male.keti.dev"
```

## 예시

### 입력
```yaml
labels:
  male.keti.dev/accuracy: "0.8"
  male.keti.dev/latency: "0.9"
  male.keti.dev/energy: "0.3"
```

### 계산 과정
```
가중치: wA=0.5, wL=0.3, wE=0.2
점수: 0.5×0.8 + 0.3×0.9 + 0.2×0.3 = 0.40 + 0.27 + 0.06 = 0.73
버킷: 0.73 ∈ [0.60, 0.79] → male-high
```

### 결과
- `priorityClassName`: `male-high`
- `mixed-score`: `0.730`

## 주의사항

1. 세 가지 값(accuracy, latency, energy)을 모두 지정해야 합니다
2. 값은 0.0 ~ 1.0 범위여야 합니다 (범위를 벗어나면 bounds로 클램핑됨)
3. MalePolicy가 클러스터에 존재해야 합니다
4. Mutating Webhook이 활성화되어 있어야 합니다

