# CRD (Custom Resource Definitions) 설명

## 개요

MALE-Operator는 두 가지 주요 CRD를 사용합니다:
1. **MaleWorkload** - 워크로드의 ALE 중요도와 MC 파라미터 정의
2. **MalePolicy** - 클러스터 전체 정책 (가중치, 범위, 우선순위 버킷)

## MaleWorkload CRD 구조

```yaml
apiVersion: male.keti.dev/v1alpha1
kind: MaleWorkload
metadata:
  name: example-workload
  namespace: default
spec:
  # ─────────────────────────────────────────────
  # 1. 타겟 워크로드 참조
  # ─────────────────────────────────────────────
  targetRef:
    apiVersion: apps/v1
    kind: Deployment          # Deployment, StatefulSet, Job, Pod 지원
    name: my-deployment

  # ─────────────────────────────────────────────
  # 2. 미션 설명 (선택)
  # ─────────────────────────────────────────────
  mission: "autonomous-driving-perception"

  # ─────────────────────────────────────────────
  # 3. ALE 중요도 값 (0~1) - MALE Paper 핵심
  # ─────────────────────────────────────────────
  importance:
    accuracy: 0.6    # A - 정확도 중요도
    latency: 0.3     # L - 지연시간 중요도
    energy: 0.1      # E - 에너지 효율 중요도

  # ─────────────────────────────────────────────
  # 4. MC (Mixed-Criticality) 스펙 - RT 스케줄링용
  # ─────────────────────────────────────────────
  mcSpec:
    criticality: "A"     # 사용자 지정 (A/B/C) - 재정의될 수 있음
    rtPeriod: 100        # 태스크 주기 (ms)
    rtWcet: 30           # WCET (ms)
    rtDeadline: 100      # 데드라인 (ms), 기본값=rtPeriod
    missionId: "mission-1"  # 미션 그룹 ID

  # ─────────────────────────────────────────────
  # 5. 정책 오버라이드 허용 여부
  # ─────────────────────────────────────────────
  allowPolicyOverride: true   # true면 중요도 기반 재정의 허용

  # ─────────────────────────────────────────────
  # 6. 스케줄링 힌트 (선택)
  # ─────────────────────────────────────────────
  schedulingHints:
    addLabels:
      custom-label: "value"
    addAnnotations:
      custom-annotation: "value"

status:
  # ─────────────────────────────────────────────
  # Operator가 계산/결정한 값들
  # ─────────────────────────────────────────────
  effectiveImportance:        # 오버라이드 적용 후 최종 중요도
    accuracy: 0.6
    latency: 0.3
    energy: 0.1

  effectiveMcSpec:            # 재정의된 MC 스펙
    criticality: "C"          # ← A에서 C로 재정의됨!
    missionType: "accuracy-critical"
    overrideReason: "Accuracy-critical mission with moderate latency..."
    rtPeriod: 100
    rtWcet: 30
    rtDeadline: 100

  mixedScore: 0.45            # MALE Score = wA*A + wL*L + wE*E
  priorityClassName: "male-high"
  lastEvaluationTime: "2024-01-15T10:30:00Z"

  conditions:
    - type: Ready
      status: "True"
      reason: Evaluated
      message: "Score: 0.450, PriorityClass: male-high, Criticality: C"
```

## MalePolicy CRD 구조

```yaml
apiVersion: male.keti.dev/v1alpha1
kind: MalePolicy
metadata:
  name: default-policy
spec:
  # ─────────────────────────────────────────────
  # 1. ALE 가중치 (합계 = 1.0)
  # ─────────────────────────────────────────────
  weights:
    accuracy: 0.4    # wA
    latency: 0.4     # wL
    energy: 0.2      # wE
    # MixedScore = 0.4*A + 0.4*L + 0.2*E

  # ─────────────────────────────────────────────
  # 2. 값 범위 제한
  # ─────────────────────────────────────────────
  bounds:
    accuracy:
      min: 0.0
      max: 1.0
    latency:
      min: 0.0
      max: 1.0
    energy:
      min: 0.0
      max: 1.0

  # ─────────────────────────────────────────────
  # 3. 우선순위 버킷 (MixedScore 기반)
  # ─────────────────────────────────────────────
  priorityBuckets:
    - name: male-critical
      min: 0.8
      max: 1.0
    - name: male-high
      min: 0.5
      max: 0.8
    - name: male-medium
      min: 0.2
      max: 0.5
    - name: male-low
      min: 0.0
      max: 0.2

  # ─────────────────────────────────────────────
  # 4. 오버라이드 설정 (선택)
  # ─────────────────────────────────────────────
  override:
    enabled: true
    source:
      type: ConfigMap
      namespace: male-system
      name: male-policy-overrides
```

## 핵심 필드 설명

### ImportanceValues (ALE)

| 필드 | 범위 | 설명 | 예시 |
|------|------|------|------|
| `accuracy` | 0.0~1.0 | 정확도 중요도 | 자율주행: 0.6 |
| `latency` | 0.0~1.0 | 지연시간 중요도 | 실시간 로봇: 0.7 |
| `energy` | 0.0~1.0 | 에너지 효율 중요도 | IoT 센서: 0.7 |

### MCSpec (Mixed-Criticality)

| 필드 | 값 | 설명 |
|------|------|------|
| `criticality` | A, B, C | MC 레벨 (C > B > A) |
| `rtPeriod` | ms | 태스크 실행 주기 |
| `rtWcet` | ms | 최악 실행 시간 |
| `rtDeadline` | ms | 데드라인 (기본값=period) |
| `missionId` | string | 미션 그룹 식별자 |

### EffectiveMCSpec (결과)

| 필드 | 설명 |
|------|------|
| `criticality` | 최종 결정된 MC 레벨 |
| `missionType` | 감지된 미션 유형 (accuracy-critical, latency-critical, energy-critical, balanced) |
| `overrideReason` | 재정의 이유 설명 |
