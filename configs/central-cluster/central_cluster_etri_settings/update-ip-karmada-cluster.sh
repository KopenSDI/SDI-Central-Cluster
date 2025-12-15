#!/bin/bash

# ==============================================================================
# Karmada 클러스터 API Endpoint 업데이트 자동화 스크립트
# - ~/.bashrc의 alias 설정을 반영한 버전
# ==============================================================================

### ▼▼▼▼▼ 여기 클러스터 이름과 IP 주소만 수정해서 사용하세요 ▼▼▼▼▼ ###
CLUSTER_NAME="edge-cluster"
NEW_IP="10.0.4.44"
### ▲▲▲▲▲ 여기 클러스터 이름과 IP 주소만 수정해서 사용하세요 ▲▲▲▲▲ ###


# --- (이 아래는 수정할 필요 없습니다) ---

# alias 대신 사용할 kubectl 명령어 전체 정의
# 사용자의 .bashrc에 있던 설정과 동일합니다.
KARMADA_KUBECTL_CMD="kubectl --kubeconfig /etc/karmada/karmada-apiserver.config"

# 변수가 비어있는지 확인
if [ -z "$CLUSTER_NAME" ] || [ -z "$NEW_IP" ]; then
  echo "오류: 스크립트 상단의 CLUSTER_NAME 또는 NEW_IP 변수가 비어있습니다."
  exit 1
fi

# kubectl 명령어가 존재하는지 확인
if ! command -v kubectl &> /dev/null; then
    echo "오류: 'kubectl' 명령어를 찾을 수 없습니다."
    echo "이 스크립트는 Karmada 컨트롤 플레인(central-cluster)에서 실행해야 합니다."
    exit 1
fi

# 새 apiEndpoint URL 생성
NEW_API_ENDPOINT="https://${NEW_IP}:6443"

echo "클러스터 '${CLUSTER_NAME}'의 apiEndpoint를 '${NEW_API_ENDPOINT}' (으)로 변경합니다..."

# 정의된 kubectl 명령어를 사용하여 클러스터 정보를 업데이트
$KARMADA_KUBECTL_CMD patch cluster "${CLUSTER_NAME}" --type=merge -p "{\"spec\":{\"apiEndpoint\":\"${NEW_API_ENDPOINT}\"}}"

# 명령어 실행 결과 확인
if [ $? -eq 0 ]; then
    echo "======================================================"
    echo "✅ 2단계가 성공적으로 완료되었습니다."
    echo "잠시 후 '${KARMADA_KUBECTL_CMD} get cluster' 명령어로 상태를 확인해보세요."
    echo "======================================================"
else
    echo "======================================================"
    echo "❌ 오류: 클러스터 정보 업데이트에 실패했습니다."
    echo "'${KARMADA_KUBECTL_CMD} get cluster ${CLUSTER_NAME}' 명령어로 클러스터가 존재하는지 확인해주세요."
    echo "======================================================"
fi