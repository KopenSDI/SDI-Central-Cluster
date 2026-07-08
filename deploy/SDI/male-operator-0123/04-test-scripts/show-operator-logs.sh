#!/bin/bash
#
# Operator 로그 확인 스크립트
#

LINES=${1:-50}

echo "============================================================"
echo " MALE-Operator 로그 (최근 $LINES 줄)"
echo "============================================================"
echo ""
echo "사용법: $0 [lines]"
echo "예시:   $0 100"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

kubectl logs -n male-system -l control-plane=controller-manager --tail=$LINES

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "실시간 로그 확인:"
echo "  kubectl logs -n male-system -l control-plane=controller-manager -f"
