#!/bin/bash
set -e

echo "=== MALE Operator Integration Test ==="
echo ""

# Test 1: Check CRDs
echo "1. Checking CRDs..."
kubectl get crd malepolicies.male.keti.dev -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' | grep -q "True" && echo "✓ MalePolicy CRD is established" || echo "✗ MalePolicy CRD not established"
kubectl get crd maleworkloads.male.keti.dev -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' | grep -q "True" && echo "✓ MaleWorkload CRD is established" || echo "✗ MaleWorkload CRD not established"
echo ""

# Test 2: Check MalePolicy
echo "2. Checking MalePolicy..."
if kubectl get malepolicy default-male-policy &>/dev/null; then
    echo "✓ MalePolicy exists"
    WEIGHTS=$(kubectl get malepolicy default-male-policy -o jsonpath='{.spec.weights}')
    echo "  Weights: $WEIGHTS"
else
    echo "✗ MalePolicy not found"
fi
echo ""

# Test 3: Check PriorityClasses (should be created by controller)
echo "3. Checking PriorityClasses..."
PRIORITY_CLASSES=$(kubectl get priorityclass -o jsonpath='{.items[*].metadata.name}' | grep -o "male-[a-z]*" || echo "")
if [ -n "$PRIORITY_CLASSES" ]; then
    echo "✓ PriorityClasses found: $PRIORITY_CLASSES"
else
    echo "⚠ PriorityClasses not yet created (controller may not be running)"
fi
echo ""

# Test 4: Check MaleWorkload
echo "4. Checking MaleWorkload..."
if kubectl get maleworkload llm-inference-workload -n default &>/dev/null; then
    echo "✓ MaleWorkload exists"
    IMPORTANCE=$(kubectl get maleworkload llm-inference-workload -n default -o jsonpath='{.spec.importance}')
    echo "  Importance: $IMPORTANCE"
    MIXED_SCORE=$(kubectl get maleworkload llm-inference-workload -n default -o jsonpath='{.status.mixedScore}' 2>/dev/null || echo "not set")
    echo "  Mixed Score: $MIXED_SCORE"
    PRIORITY_CLASS=$(kubectl get maleworkload llm-inference-workload -n default -o jsonpath='{.status.priorityClassName}' 2>/dev/null || echo "not set")
    echo "  PriorityClass: $PRIORITY_CLASS"
else
    echo "✗ MaleWorkload not found"
fi
echo ""

# Test 5: Check Deployment labels/annotations
echo "5. Checking Deployment labels/annotations..."
if kubectl get deployment my-llm -n default &>/dev/null; then
    echo "✓ Deployment exists"
    WORKLOAD_LABEL=$(kubectl get deployment my-llm -n default -o jsonpath='{.spec.template.metadata.labels.male\.keti\.dev/workload}' 2>/dev/null || echo "not set")
    echo "  Workload label: $WORKLOAD_LABEL"
    PRIORITY_ANNOTATION=$(kubectl get deployment my-llm -n default -o jsonpath='{.spec.template.metadata.annotations.male\.keti\.dev/priority-class}' 2>/dev/null || echo "not set")
    echo "  Priority annotation: $PRIORITY_ANNOTATION"
else
    echo "✗ Deployment not found"
fi
echo ""

# Test 6: Validate policy weights
echo "6. Validating policy weights..."
ACCURACY=$(kubectl get malepolicy default-male-policy -o jsonpath='{.spec.weights.accuracy}')
LATENCY=$(kubectl get malepolicy default-male-policy -o jsonpath='{.spec.weights.latency}')
ENERGY=$(kubectl get malepolicy default-male-policy -o jsonpath='{.spec.weights.energy}')
SUM=$(echo "$ACCURACY + $LATENCY + $ENERGY" | bc)
echo "  Weights sum: $SUM (should be 1.0)"
if (( $(echo "$SUM == 1.0" | bc -l) )); then
    echo "✓ Weights sum is correct"
else
    echo "✗ Weights sum is incorrect"
fi
echo ""

echo "=== Test Complete ==="

