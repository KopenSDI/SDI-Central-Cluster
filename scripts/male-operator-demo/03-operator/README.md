# MALE-Operator 내부 구조

## 개요

MALE-Operator는 Kubernetes Operator 패턴을 사용하여 MaleWorkload 리소스를 관리합니다.
핵심 기능은 ALE 중요도 값을 기반으로 MC Criticality를 자동 재정의하는 것입니다.

## 소스 코드 구조

```
deploy/SDI/male-operator/
├── api/
│   └── v1alpha1/
│       ├── maleworkload_types.go     # MaleWorkload CRD 타입 정의
│       ├── malepolicy_types.go       # MalePolicy CRD 타입 정의
│       └── groupversion_info.go
├── controllers/
│   └── maleworkload_controller.go    # 메인 Reconcile 로직
├── internal/
│   ├── policy/
│   │   ├── criticality.go            # MC Criticality 재정의 핵심 로직
│   │   ├── criticality_test.go       # 단위 테스트
│   │   └── calculator.go             # MixedScore 계산
│   └── override/
│       ├── configmap.go              # ConfigMap 오버라이드
│       └── webhook.go                # Webhook 오버라이드
├── cmd/
│   ├── main.go                       # Operator 엔트리포인트
│   └── demo/
│       └── main.go                   # 데모 프로그램
└── config/
    ├── crd/                          # CRD 매니페스트
    ├── manager/                      # Operator 배포 매니페스트
    └── samples/                      # 예제 YAML
```

## 핵심 컴포넌트

### 1. MaleWorkloadReconciler (maleworkload_controller.go)

```go
// Reconcile 루프의 주요 단계:

func (r *MaleWorkloadReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    // 1. MaleWorkload 조회
    workload := &malev1alpha1.MaleWorkload{}
    r.Get(ctx, req.NamespacedName, workload)

    // 2. MalePolicy 조회
    policyList := &malev1alpha1.MalePolicyList{}
    r.List(ctx, policyList)

    // 3. Override 적용 (선택적)
    effectiveImportance := workload.Spec.Importance
    if workload.Spec.AllowPolicyOverride && activePolicy.Spec.Override.Enabled {
        // WebhookCache 또는 ConfigMap에서 오버라이드 값 적용
    }

    // 4. 값 범위 클램핑
    effectiveImportance = policy.ClampValues(effectiveImportance, activePolicy.Spec.Bounds)

    // 5. MixedScore 계산
    mixedScore, _ = policy.CalculateMixedScore(activePolicy.Spec.Weights, effectiveImportance)

    // 6. Priority Bucket 찾기
    bucket, _ = policy.FindPriorityBucket(mixedScore, activePolicy.Spec.PriorityBuckets)

    // 7. ★ MC Criticality 결정 (핵심!)
    criticalityResult := policy.DetermineCriticality(
        effectiveImportance,
        userCriticality,
        workload.Spec.AllowPolicyOverride,
    )

    // 8. EffectiveMCSpec 생성
    effectiveMCSpec := r.buildEffectiveMCSpec(workload, criticalityResult)

    // 9. Target Workload 업데이트 (레이블/어노테이션)
    r.updateTargetWorkload(ctx, workload, bucket.Name)

    // 10. Status 업데이트
    workload.Status.EffectiveImportance = &effectiveImportance
    workload.Status.EffectiveMCSpec = effectiveMCSpec
    workload.Status.MixedScore = &mixedScore
    r.Status().Update(ctx, workload)
}
```

### 2. DetermineCriticality (criticality.go)

```go
// MC Criticality 결정의 핵심 알고리즘

func DetermineCriticality(
    importance malev1alpha1.ImportanceValues,
    userCriticality string,
    allowOverride bool,
) CriticalityResult {
    thresholds := DefaultCriticalityThresholds()

    // 1. Mission Type 감지
    missionType := DetectMissionType(importance, thresholds)

    // 2. Criticality 결정
    criticality, reason := determineCriticalityFromImportance(importance, missionType, thresholds)

    // 3. Override 확인
    if !allowOverride && userCriticality != "" {
        // 사용자 값 유지
        return CriticalityResult{
            Criticality: CriticalityLevel(userCriticality),
            Reason:      "User-specified criticality (override disabled)",
        }
    }

    // 4. 재정의 여부 기록
    if userCriticality != "" && userCriticality != string(criticality) {
        result.WasOverridden = true
    }

    return result
}
```

### 3. Criticality 결정 규칙 (determineCriticalityFromImportance)

```go
func determineCriticalityFromImportance(
    importance malev1alpha1.ImportanceValues,
    missionType MissionType,
    thresholds CriticalityThresholds,
) (CriticalityLevel, string) {
    A := importance.Accuracy
    L := importance.Latency

    // Rule 1: Very high latency → C
    if L >= 0.9 {
        return CriticalityC, "Very high latency importance (>=0.9)"
    }

    // Rule 2: High latency + moderate accuracy → C
    if L >= 0.7 && A >= 0.5 {
        return CriticalityC, "High latency with moderate accuracy"
    }

    // Rule 3: Autonomous Vehicles pattern → C
    if A >= 0.6 && L >= 0.3 {
        return CriticalityC, "Autonomous Vehicles pattern (A>=0.6, L>=0.3)"
    }

    // Rule 4: Combined threshold → C
    if A+L >= 0.9 {
        return CriticalityC, "Combined A+L threshold (>=0.9)"
    }

    // Rule 5: Mission-type based
    switch missionType {
    case MissionTypeLatencyCritical:
        if L >= 0.5 {
            return CriticalityB, "Latency-critical mission"
        }
    case MissionTypeEnergyCritical:
        return CriticalityA, "Energy-critical mission"
    }

    return CriticalityA, "Default best-effort"
}
```

## Operator 이미지

```
이미지: ketidevit2/male-operator:v2-mc
레지스트리: Docker Hub
```

## 배포 방법

```bash
# 1. CRD 설치
kubectl apply -f config/crd/bases/

# 2. Operator 배포
kubectl apply -f config/manager/

# 3. 확인
kubectl get pods -n male-system
kubectl logs -n male-system -l control-plane=controller-manager
```
