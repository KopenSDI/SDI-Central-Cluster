#!/bin/bash

echo "=========================================="
echo "MALE Operator 동작 상태 확인"
echo "=========================================="
echo ""

# 1. 오퍼레이터 Pod 상태 확인
echo "1️⃣ 오퍼레이터 Pod 상태:"
kubectl get pods -n male-operator-system
echo ""

# 2. PriorityClass 생성 확인
echo "2️⃣ PriorityClass 생성 확인:"
kubectl get priorityclass | grep male || echo "⚠ PriorityClass가 없습니다"
echo ""

# 3. MalePolicy 상태 확인
echo "3️⃣ MalePolicy 상태:"
kubectl get malepolicy
if kubectl get malepolicy default-male-policy &>/dev/null; then
    echo ""
    echo "   가중치:"
    kubectl get malepolicy default-male-policy -o jsonpath='{.spec.weights}' | jq . 2>/dev/null || kubectl get malepolicy default-male-policy -o jsonpath='{.spec.weights}'
    echo ""
fi
echo ""

# 4. MaleWorkload 상태 확인
echo "4️⃣ MaleWorkload 상태:"
kubectl get maleworkload --all-namespaces
echo ""

if kubectl get maleworkload llm-inference-workload -n default &>/dev/null; then
    echo "   중요도 값:"
    kubectl get maleworkload llm-inference-workload -n default -o jsonpath='{.spec.importance}' | jq . 2>/dev/null || kubectl get maleworkload llm-inference-workload -n default -o jsonpath='{.spec.importance}'
    echo ""
    echo "   계산된 점수:"
    kubectl get maleworkload llm-inference-workload -n default -o jsonpath='{.status.mixedScore}' 2>/dev/null || echo "   ⚠ 아직 계산되지 않음"
    echo ""
    echo "   할당된 PriorityClass:"
    kubectl get maleworkload llm-inference-workload -n default -o jsonpath='{.status.priorityClassName}' 2>/dev/null || echo "   ⚠ 아직 할당되지 않음"
    echo ""
fi
echo ""

# 5. Deployment 라벨 확인
echo "5️⃣ Deployment 라벨 확인:"
if kubectl get deployment my-llm -n default &>/dev/null; then
    echo "   MALE 라벨:"
    kubectl get deployment my-llm -n default -o jsonpath='{.spec.template.metadata.labels.male\.keti\.dev/workload}' 2>/dev/null || echo "   ⚠ 라벨 없음"
    echo ""
    kubectl get deployment my-llm -n default -o jsonpath='{.spec.template.metadata.labels.male\.keti\.dev/mission}' 2>/dev/null || echo "   ⚠ 라벨 없음"
    echo ""
else
    echo "   ⚠ Deployment 'my-llm'을 찾을 수 없습니다"
fi
echo ""

# 6. Pod의 priorityClassName 확인
echo "6️⃣ Pod의 priorityClassName 확인:"
POD_NAME=$(kubectl get pods -n default -l app=llm-inference -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$POD_NAME" ]; then
    echo "   Pod: $POD_NAME"
    kubectl get pod $POD_NAME -n default -o jsonpath='{.spec.priorityClassName}' 2>/dev/null || echo "   ⚠ priorityClassName 없음"
    echo ""
else
    echo "   ⚠ Pod를 찾을 수 없습니다"
fi
echo ""

# 7. 오퍼레이터 로그 확인 (최근 5줄)
echo "7️⃣ 오퍼레이터 최근 로그:"
kubectl logs -n male-operator-system -l control-plane=controller-manager --tail=5 2>/dev/null || echo "   ⚠ 로그를 가져올 수 없습니다"
echo ""

echo "=========================================="
echo "확인 완료"
echo "=========================================="

