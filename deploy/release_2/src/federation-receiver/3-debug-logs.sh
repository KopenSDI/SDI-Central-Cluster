#!/bin/bash
# Federation Receiver 디버그/로그 스크립트

NAMESPACE="tbot-monitoring"
APP_LABEL="app=federation-receiver"

echo "=============================================="
echo "Federation Receiver 디버그 정보"
echo "=============================================="

# Pod 상태
echo ""
echo "[1] Pod 상태:"
kubectl get pods -n $NAMESPACE -l $APP_LABEL -o wide

# Pod 상세 정보
echo ""
echo "[2] Pod 상세 (최근 이벤트):"
POD_NAME=$(kubectl get pods -n $NAMESPACE -l $APP_LABEL -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$POD_NAME" ]; then
    kubectl describe pod $POD_NAME -n $NAMESPACE | tail -20
else
    echo "Pod을 찾을 수 없습니다."
fi

# 로그
echo ""
echo "[3] 로그 (최근 50줄):"
if [ -n "$POD_NAME" ]; then
    kubectl logs $POD_NAME -n $NAMESPACE --tail=50
else
    echo "Pod을 찾을 수 없습니다."
fi

# 서비스 상태
echo ""
echo "[4] 서비스 상태:"
kubectl get svc -n $NAMESPACE -l $APP_LABEL

# 헬스 체크 테스트
echo ""
echo "[5] 헬스 체크 테스트:"
if [ -n "$POD_NAME" ]; then
    kubectl exec $POD_NAME -n $NAMESPACE -- curl -s http://localhost:8080/health 2>/dev/null || \
    echo "헬스 체크 실패 또는 curl 미설치"
fi

# Federation 상태 확인
echo ""
echo "[6] Federation 상태:"
if [ -n "$POD_NAME" ]; then
    kubectl exec $POD_NAME -n $NAMESPACE -- curl -s http://localhost:8080/api/v1/federation/status 2>/dev/null || \
    echo "상태 조회 실패"
fi

# 등록된 클러스터 확인
echo ""
echo "[7] 등록된 클러스터:"
if [ -n "$POD_NAME" ]; then
    kubectl exec $POD_NAME -n $NAMESPACE -- curl -s http://localhost:8080/api/v1/federation/clusters 2>/dev/null || \
    echo "클러스터 조회 실패"
fi

echo ""
echo "=============================================="
echo "실시간 로그 보기: kubectl logs -f $POD_NAME -n $NAMESPACE"
echo "=============================================="
