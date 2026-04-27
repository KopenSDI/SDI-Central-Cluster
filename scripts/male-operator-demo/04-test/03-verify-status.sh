#!/bin/bash
#
# MaleWorkload 상태 확인 스크립트
#
# 모든 MaleWorkload의 상태를 자세히 표시합니다.
#

echo "============================================================"
echo " MaleWorkload Status Verification"
echo "============================================================"
echo ""

# 모든 MaleWorkload 조회
WORKLOADS=$(kubectl get maleworkload -o name 2>/dev/null)

if [ -z "$WORKLOADS" ]; then
    echo "No MaleWorkload resources found."
    exit 0
fi

for wl in $WORKLOADS; do
    NAME=$(echo $wl | cut -d'/' -f2)

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "MaleWorkload: $NAME"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Spec 정보
    echo ""
    echo "[Spec - 사용자 입력]"
    echo "─────────────────────────────────────────────────────────"

    A=$(kubectl get maleworkload $NAME -o jsonpath='{.spec.importance.accuracy}')
    L=$(kubectl get maleworkload $NAME -o jsonpath='{.spec.importance.latency}')
    E=$(kubectl get maleworkload $NAME -o jsonpath='{.spec.importance.energy}')
    USER_CRIT=$(kubectl get maleworkload $NAME -o jsonpath='{.spec.mcSpec.criticality}')

    echo "  importance:"
    echo "    accuracy: $A"
    echo "    latency:  $L"
    echo "    energy:   $E"
    echo "  mcSpec.criticality: $USER_CRIT"

    # Status 정보
    echo ""
    echo "[Status - Operator 결과]"
    echo "─────────────────────────────────────────────────────────"

    EFF_CRIT=$(kubectl get maleworkload $NAME -o jsonpath='{.status.effectiveMcSpec.criticality}')
    MISSION_TYPE=$(kubectl get maleworkload $NAME -o jsonpath='{.status.effectiveMcSpec.missionType}')
    OVERRIDE_REASON=$(kubectl get maleworkload $NAME -o jsonpath='{.status.effectiveMcSpec.overrideReason}')
    MIXED_SCORE=$(kubectl get maleworkload $NAME -o jsonpath='{.status.mixedScore}')
    PRIORITY_CLASS=$(kubectl get maleworkload $NAME -o jsonpath='{.status.priorityClassName}')
    LAST_EVAL=$(kubectl get maleworkload $NAME -o jsonpath='{.status.lastEvaluationTime}')

    echo "  effectiveMcSpec:"
    echo "    criticality:    $EFF_CRIT"
    echo "    missionType:    $MISSION_TYPE"
    echo "    overrideReason: $OVERRIDE_REASON"
    echo "  mixedScore:       $MIXED_SCORE"
    echo "  priorityClassName: $PRIORITY_CLASS"
    echo "  lastEvaluationTime: $LAST_EVAL"

    # 재정의 확인
    echo ""
    if [ "$USER_CRIT" != "$EFF_CRIT" ]; then
        echo "  ⚠️  Criticality 재정의됨: $USER_CRIT → $EFF_CRIT"
    else
        echo "  ✓  Criticality 유지됨: $EFF_CRIT"
    fi

    # Condition 정보
    echo ""
    echo "[Conditions]"
    echo "─────────────────────────────────────────────────────────"
    kubectl get maleworkload $NAME -o jsonpath='{range .status.conditions[*]}  - {.type}: {.status} ({.reason}){"\n"}{end}'

    echo ""
done

echo "============================================================"
echo " Full YAML Output (optional)"
echo "============================================================"
echo ""
echo "각 워크로드의 전체 YAML을 보려면:"
echo "  kubectl get maleworkload <name> -o yaml"
echo ""
