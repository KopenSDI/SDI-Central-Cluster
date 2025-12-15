#!/bin/bash

# MALE 정책 실시간 조정 스크립트
# 사용법: ./adjust-male-policy.sh <정책명> <accuracy> <latency> <energy>

set -e

POLICY_NAME=${1:-""}
ACCURACY=${2:-""}
LATENCY=${3:-""}
ENERGY=${4:-""}

usage() {
    echo "MALE 정책 실시간 조정 스크립트"
    echo ""
    echo "사용법:"
    echo "  $0 <정책명> <accuracy> <latency> <energy>"
    echo ""
    echo "예시:"
    echo "  $0 my-policy 900 100 500          # 기본 조정"
    echo "  $0 my-policy high-performance     # 프리셋 사용"
    echo "  $0 my-policy energy-efficient     # 프리셋 사용"
    echo ""
    echo "프리셋:"
    echo "  high-performance: accuracy=950, latency=50, energy=400"
    echo "  energy-efficient: accuracy=600, latency=400, energy=900"
    echo "  balanced: accuracy=750, latency=250, energy=650"
    echo ""
}

if [ -z "$POLICY_NAME" ]; then
    usage
    exit 1
fi

# 프리셋 처리
case "$ACCURACY" in
    "high-performance")
        ACCURACY=950
        LATENCY=50
        ENERGY=400
        echo "고성능 프리셋 적용: accuracy=$ACCURACY, latency=$LATENCY, energy=$ENERGY"
        ;;
    "energy-efficient")
        ACCURACY=600
        LATENCY=400
        ENERGY=900
        echo "전력효율 프리셋 적용: accuracy=$ACCURACY, latency=$LATENCY, energy=$ENERGY"
        ;;
    "balanced")
        ACCURACY=750
        LATENCY=250
        ENERGY=650
        echo "균형 프리셋 적용: accuracy=$ACCURACY, latency=$LATENCY, energy=$ENERGY"
        ;;
esac

# 값 검증
if [ -z "$ACCURACY" ] || [ -z "$LATENCY" ] || [ -z "$ENERGY" ]; then
    echo "오류: 모든 MALE 값을 제공해야 합니다."
    usage
    exit 1
fi

# 범위 검증 (0-1000)
for value in $ACCURACY $LATENCY $ENERGY; do
    if [ "$value" -lt 0 ] || [ "$value" -gt 1000 ]; then
        echo "오류: MALE 값은 0-1000 범위여야 합니다. 잘못된 값: $value"
        exit 1
    fi
done

echo "MALE 정책 조정 중..."
echo "정책명: $POLICY_NAME"
echo "Accuracy: $ACCURACY"
echo "Latency: $LATENCY"
echo "Energy: $ENERGY"

# 정책 존재 확인
if ! kubectl get malepolicy "$POLICY_NAME" >/dev/null 2>&1; then
    echo "오류: 정책 '$POLICY_NAME'을 찾을 수 없습니다."
    echo "현재 정책 목록:"
    kubectl get malepolicies -A
    exit 1
fi

# 현재 정책 값 출력
echo ""
echo "=== 현재 정책 값 ==="
kubectl get malepolicy "$POLICY_NAME" -o jsonpath='{.spec.accuracy},{.spec.latency},{.spec.energy}' | awk -F',' '{print "Current - Accuracy: " $1 ", Latency: " $2 ", Energy: " $3}'

# 정책 업데이트
kubectl patch malepolicy "$POLICY_NAME" --type='merge' \
  -p="{\"spec\":{\"accuracy\":$ACCURACY,\"latency\":$LATENCY,\"energy\":$ENERGY}}"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ 정책 조정 완료!"
    
    # 잠시 대기 후 적용 결과 확인
    sleep 3
    
    echo ""
    echo "=== 업데이트된 정책 값 ==="
    kubectl get malepolicy "$POLICY_NAME" -o jsonpath='{.spec.accuracy},{.spec.latency},{.spec.energy}' | awk -F',' '{print "Updated - Accuracy: " $1 ", Latency: " $2 ", Energy: " $3}'
    
    echo ""
    echo "=== 적용된 워크로드 수 ==="
    kubectl get malepolicy "$POLICY_NAME" -o jsonpath='{.status.appliedWorkloads}' | awk '{print "Applied to " $1 " workloads"}'
    
    echo ""
    echo "=== 정책 상태 확인 ==="
    kubectl describe malepolicy "$POLICY_NAME" | grep -A 10 "Status:"
    
else
    echo "❌ 정책 조정 실패"
    exit 1
fi