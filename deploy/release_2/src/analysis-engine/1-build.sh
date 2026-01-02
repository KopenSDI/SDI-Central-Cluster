#!/bin/bash
#===============================================================================
# Analysis Engine - Docker Build Script
#
# 사용법: ./1-build.sh [VERSION]
# 예시:   ./1-build.sh v0.2.0
#===============================================================================

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 기본 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SRC_DIR="${PROJECT_ROOT}/deploy/release_2/src/analysis-engine"

# Docker 이미지 설정
DOCKER_REGISTRY="ketidevit2"
IMAGE_NAME="sdi-analysis-engine"
VERSION="${1:-v0.2.0}"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Analysis Engine Docker Build${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# 디렉토리 확인
if [ ! -d "${SRC_DIR}" ]; then
    echo -e "${RED}[ERROR] 소스 디렉토리를 찾을 수 없습니다: ${SRC_DIR}${NC}"
    exit 1
fi

echo -e "${YELLOW}[INFO] 설정 정보:${NC}"
echo "  - 소스 디렉토리: ${SRC_DIR}"
echo "  - 이미지: ${DOCKER_REGISTRY}/${IMAGE_NAME}:${VERSION}"
echo ""

# Dockerfile 확인
if [ ! -f "${SRC_DIR}/Dockerfile" ]; then
    echo -e "${RED}[ERROR] Dockerfile을 찾을 수 없습니다${NC}"
    exit 1
fi

# requirements.txt 확인
if [ ! -f "${SRC_DIR}/requirements.txt" ]; then
    echo -e "${YELLOW}[WARN] requirements.txt가 없습니다. 기본 파일 생성...${NC}"
    cat > "${SRC_DIR}/requirements.txt" << 'EOF'
flask>=2.0.0
flask-cors>=3.0.0
influxdb-client>=1.30.0
grpcio>=1.62.0
grpcio-tools>=1.62.0
protobuf>=4.21.0
requests>=2.28.0
EOF
fi

echo -e "${GREEN}[1/3] Docker 이미지 빌드 시작...${NC}"
cd "${SRC_DIR}"

docker build \
    --no-cache \
    -t "${DOCKER_REGISTRY}/${IMAGE_NAME}:${VERSION}" \
    -t "${DOCKER_REGISTRY}/${IMAGE_NAME}:latest" \
    .

echo ""
echo -e "${GREEN}[2/3] 빌드 완료. 이미지 확인:${NC}"
docker images | grep "${IMAGE_NAME}" | head -5

echo ""
echo -e "${YELLOW}[3/3] Docker Hub에 Push 하시겠습니까? (y/N)${NC}"
read -r PUSH_CONFIRM

if [[ "${PUSH_CONFIRM}" =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}[PUSH] Docker Hub에 업로드 중...${NC}"
    docker push "${DOCKER_REGISTRY}/${IMAGE_NAME}:${VERSION}"
    docker push "${DOCKER_REGISTRY}/${IMAGE_NAME}:latest"
    echo -e "${GREEN}[DONE] Push 완료!${NC}"
else
    echo -e "${YELLOW}[SKIP] Push 건너뜀${NC}"
fi

echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${GREEN}  빌드 완료!${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo "다음 단계: ./2-deploy.sh ${VERSION}"