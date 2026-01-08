#!/bin/bash
# Federation Receiver 빌드 스크립트
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

IMAGE_NAME="ketidevit2/federation-receiver"
IMAGE_TAG="${1:-v1.0.0}"

echo "=============================================="
echo "Federation Receiver Docker 이미지 빌드"
echo "=============================================="
echo "이미지: ${IMAGE_NAME}:${IMAGE_TAG}"
echo ""

# Docker 이미지 빌드
echo "[1/2] Docker 이미지 빌드 중..."
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" .

# Kind 클러스터에 이미지 로드
echo "[2/2] Kind 클러스터에 이미지 로드 중..."
if command -v kind &> /dev/null; then
    kind load docker-image "${IMAGE_NAME}:${IMAGE_TAG}" --name sdi-central-cluster 2>/dev/null || \
    echo "Kind 클러스터 로드 실패 - containerd로 시도..."
fi

# containerd로 직접 로드 (Kind 노드 내부)
echo "containerd로 이미지 임포트 중..."
docker save "${IMAGE_NAME}:${IMAGE_TAG}" | ctr -n k8s.io images import -

echo ""
echo "=============================================="
echo "빌드 완료: ${IMAGE_NAME}:${IMAGE_TAG}"
echo "=============================================="

# 이미지 확인
echo ""
echo "로드된 이미지 확인:"
ctr -n k8s.io images ls | grep federation-receiver || echo "이미지 확인 필요"
