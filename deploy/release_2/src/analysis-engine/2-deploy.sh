#!/bin/bash
#===============================================================================
# Analysis Engine - Kubernetes Deploy Script
#
# 사용법: ./2-deploy.sh [VERSION]
# 예시:   ./2-deploy.sh v0.2.0
#===============================================================================

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 기본 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SRC_DIR="${PROJECT_ROOT}/deploy/release_2/src/analysis-engine"

# 배포 설정
NAMESPACE="default"
DEPLOYMENT_NAME="sdi-analysis-engine"
SERVICE_NAME="sdi-analysis-engine-service"
VERSION="${1:-v0.2.0}"

# InfluxDB 설정 (Central Cluster)
# TODO: 실제 환경에 맞게 수정 필요
INFLUX_URL="http://influxdb.tbot-monitoring.svc.cluster.local:8086"
INFLUX_ORG="keti"
INFLUX_BUCKET="turtlebot"
# INFLUX_TOKEN은 Secret에서 관리

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Analysis Engine Kubernetes Deploy${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

#-------------------------------------------------------------------------------
# 1. 환경 확인
#-------------------------------------------------------------------------------
echo -e "${GREEN}[1/5] 환경 확인...${NC}"

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}[ERROR] kubectl이 설치되어 있지 않습니다${NC}"
    exit 1
fi

# 클러스터 연결 확인
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}[ERROR] Kubernetes 클러스터에 연결할 수 없습니다${NC}"
    exit 1
fi

echo -e "${CYAN}  클러스터:${NC} $(kubectl config current-context)"
echo -e "${CYAN}  네임스페이스:${NC} ${NAMESPACE}"
echo -e "${CYAN}  배포 버전:${NC} ${VERSION}"
echo ""

#-------------------------------------------------------------------------------
# 2. ConfigMap 생성/업데이트
#-------------------------------------------------------------------------------
echo -e "${GREEN}[2/5] ConfigMap 생성...${NC}"

kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: analysis-engine-config
  namespace: ${NAMESPACE}
  labels:
    app: sdi-analysis-engine
data:
  # InfluxDB 설정
  INFLUX_URL: "${INFLUX_URL}"
  INFLUX_ORG: "${INFLUX_ORG}"
  INFLUX_BUCKET: "${INFLUX_BUCKET}"

  # 서버 설정
  GRPC_PORT: "50051"
  REST_PORT: "5000"

  # 로깅
  LOG_LEVEL: "INFO"

  # TODO: 동적 BOT 조회가 구현되면 이 값은 사용 안 함
  # 현재는 하드코딩 대체용
  DEFAULT_BOTS: "TURTLEBOT3-Burger-1,TURTLEBOT3-Burger-2"
EOF

echo -e "${CYAN}  ConfigMap 'analysis-engine-config' 생성됨${NC}"

#-------------------------------------------------------------------------------
# 3. Secret 확인 (InfluxDB Token)
#-------------------------------------------------------------------------------
echo -e "${GREEN}[3/5] Secret 확인...${NC}"

if ! kubectl get secret influxdb-token -n ${NAMESPACE} &> /dev/null; then
    echo -e "${YELLOW}[WARN] influxdb-token Secret이 없습니다.${NC}"
    echo -e "${YELLOW}       수동으로 생성하거나 기존 YAML의 Secret을 사용하세요.${NC}"
    echo ""
    echo "  예시:"
    echo "  kubectl create secret generic influxdb-token \\"
    echo "    --from-literal=INFLUX_TOKEN='your-token-here' \\"
    echo "    -n ${NAMESPACE}"
    echo ""
else
    echo -e "${CYAN}  Secret 'influxdb-token' 존재 확인됨${NC}"
fi

#-------------------------------------------------------------------------------
# 4. Deployment 배포
#-------------------------------------------------------------------------------
echo -e "${GREEN}[4/5] Deployment 배포...${NC}"

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${DEPLOYMENT_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: sdi-analysis-engine
    version: ${VERSION}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sdi-analysis-engine
  template:
    metadata:
      labels:
        app: sdi-analysis-engine
        version: ${VERSION}
    spec:
      containers:
      - name: analysis-engine
        image: ketidevit2/sdi-analysis-engine:${VERSION}
        imagePullPolicy: Always
        args: ["--both", "--grpc-port", "50051", "--rest-port", "5000"]

        ports:
        - containerPort: 50051
          name: grpc
          protocol: TCP
        - containerPort: 5000
          name: http
          protocol: TCP

        # 환경변수 - ConfigMap에서 주입
        envFrom:
        - configMapRef:
            name: analysis-engine-config

        env:
        - name: PYTHONUNBUFFERED
          value: "1"
        # InfluxDB Token - Secret에서 주입
        - name: INFLUX_TOKEN
          valueFrom:
            secretKeyRef:
              name: influxdb-token
              key: INFLUX_TOKEN
              optional: true

        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"

        livenessProbe:
          httpGet:
            path: /health
            port: 5000
          initialDelaySeconds: 30
          periodSeconds: 10

        readinessProbe:
          httpGet:
            path: /health
            port: 5000
          initialDelaySeconds: 5
          periodSeconds: 5

      restartPolicy: Always
---
apiVersion: v1
kind: Service
metadata:
  name: ${SERVICE_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: sdi-analysis-engine
spec:
  type: NodePort
  ports:
  - name: http
    port: 5000
    targetPort: 5000
    nodePort: 30050
    protocol: TCP
  - name: grpc
    port: 50051
    targetPort: 50051
    nodePort: 30051
    protocol: TCP
  selector:
    app: sdi-analysis-engine
EOF

echo -e "${CYAN}  Deployment '${DEPLOYMENT_NAME}' 배포됨${NC}"
echo -e "${CYAN}  Service '${SERVICE_NAME}' 생성됨${NC}"

#-------------------------------------------------------------------------------
# 5. 배포 상태 확인
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[5/5] 배포 상태 확인...${NC}"
echo ""

echo -e "${YELLOW}Rollout 대기 중... (최대 120초)${NC}"
kubectl rollout status deployment/${DEPLOYMENT_NAME} -n ${NAMESPACE} --timeout=120s || true

echo ""
echo -e "${CYAN}Pod 상태:${NC}"
kubectl get pods -n ${NAMESPACE} -l app=sdi-analysis-engine -o wide

echo ""
echo -e "${CYAN}Service 정보:${NC}"
kubectl get svc ${SERVICE_NAME} -n ${NAMESPACE}

echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${GREEN}  배포 완료!${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo "접속 정보:"
echo "  - REST API: http://<NODE_IP>:30050/health"
echo "  - gRPC:     <NODE_IP>:30051"
echo ""
echo "로그 확인: ./3-debug-logs.sh"
