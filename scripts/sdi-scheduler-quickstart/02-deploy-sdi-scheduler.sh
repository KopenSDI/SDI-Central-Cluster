#!/bin/bash
# ==============================================================
# 02-deploy-sdi-scheduler.sh
# SDI 스케줄러 배포 또는 이미지 업데이트
#
# kubectl 대상:
#   KL (로컬 클러스터) — Deployment / ConfigMap / RBAC / Secret
#   KM (Karmada API)  — 확인 용도만 (clusters)
#
# 사용법:
#   ./02-deploy-sdi-scheduler.sh                        # 현재 이미지로 배포
#   SDI_IMAGE=ketidevit2/sdi-scheduler:v3 ./02-deploy-sdi-scheduler.sh
# ==============================================================

set -euo pipefail

KARMADA_CFG="/etc/karmada/karmada-apiserver.config"
SDI_IMAGE="${SDI_IMAGE:-ketidevit2/sdi-scheduler:v2-iac}"
DEFAULT_ALGORITHM="${DEFAULT_ALGORITHM:-intent-driven}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

ok()   { echo -e "${GREEN}  ✓ $*${NC}"; }
warn() { echo -e "${YELLOW}  ! $*${NC}"; }
err()  { echo -e "${RED}  ✗ $*${NC}"; exit 1; }
hdr()  { echo -e "\n${BLUE}━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
step() { echo -e "${CYAN}  → $*${NC}"; }

KL="kubectl"
KM="kubectl --kubeconfig=${KARMADA_CFG}"

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════╗"
echo "║       SDI Scheduler 배포                         ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "  이미지: ${SDI_IMAGE}"
echo "  기본 알고리즘: ${DEFAULT_ALGORITHM}"
echo ""

# ────────────────────────────────────────────────────────────
hdr "1. 연결 확인"
# ────────────────────────────────────────────────────────────
${KL} get nodes &>/dev/null || err "로컬 클러스터 연결 실패"
ok "로컬 클러스터 연결 정상"

[ -f "${KARMADA_CFG}" ] || err "Karmada kubeconfig 없음: ${KARMADA_CFG}"
${KM} get clusters &>/dev/null || err "Karmada API 연결 실패"
ok "Karmada API 연결 정상"

# ────────────────────────────────────────────────────────────
hdr "2. 이미 실행 중인 스케줄러 확인"
# ────────────────────────────────────────────────────────────
EXISTING=$(${KL} get deployment sdi-scheduler -n karmada-system \
    --no-headers 2>/dev/null | head -1 || echo "")

if [ -n "${EXISTING}" ]; then
    CURRENT_IMAGE=$(${KL} get deployment sdi-scheduler -n karmada-system \
        -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
    warn "SDI 스케줄러 이미 배포됨: ${CURRENT_IMAGE}"

    if [ "${CURRENT_IMAGE}" == "${SDI_IMAGE}" ]; then
        ok "동일한 이미지 — 이미지 업데이트 없음"
    else
        echo -e "  이미지 업데이트: ${YELLOW}${CURRENT_IMAGE}${NC} → ${GREEN}${SDI_IMAGE}${NC}"
        step "이미지 업데이트..."
        ${KL} set image deployment/sdi-scheduler \
            sdi-scheduler="${SDI_IMAGE}" \
            -n karmada-system
        ok "이미지 업데이트 완료"
        step "재시작 대기..."
        ${KL} rollout status deployment/sdi-scheduler -n karmada-system --timeout=60s
        ok "재시작 완료"
    fi

    # 알고리즘 업데이트 여부 확인
    CURRENT_ALGO=$(${KL} get deployment sdi-scheduler -n karmada-system \
        -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="SDI_DEFAULT_ALGORITHM")].value}' \
        2>/dev/null || echo "")
    if [ -n "${CURRENT_ALGO}" ] && [ "${CURRENT_ALGO}" != "${DEFAULT_ALGORITHM}" ]; then
        echo ""
        warn "알고리즘 변경은 03-switch-algorithm.sh 사용"
        echo "  현재: ${CURRENT_ALGO}"
        echo "  ./03-switch-algorithm.sh ${DEFAULT_ALGORITHM}"
    fi

    echo ""
    echo -e "${GREEN}━━━ 확인 완료 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "로그:"
    echo "  kubectl logs -n karmada-system -l app=sdi-scheduler -f"
    echo ""
    echo "알고리즘 전환:"
    echo "  ./03-switch-algorithm.sh"
    exit 0
fi

# ────────────────────────────────────────────────────────────
# 신규 배포
# ────────────────────────────────────────────────────────────
hdr "3. RBAC 설정"
# ────────────────────────────────────────────────────────────
step "ServiceAccount, ClusterRole, ClusterRoleBinding 생성..."

${KL} apply -f - <<EOF
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: sdi-scheduler
  namespace: karmada-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: sdi-scheduler
rules:
- apiGroups: ["cluster.karmada.io"]
  resources: ["clusters"]
  verbs: ["get","list","watch"]
- apiGroups: ["work.karmada.io"]
  resources: ["resourcebindings","clusterresourcebindings"]
  verbs: ["get","list","watch","update","patch"]
- apiGroups: ["work.karmada.io"]
  resources: ["resourcebindings/status","clusterresourcebindings/status"]
  verbs: ["update","patch"]
- apiGroups: ["policy.karmada.io"]
  resources: ["propagationpolicies","clusterpropagationpolicies"]
  verbs: ["get","list","watch"]
- apiGroups: ["coordination.k8s.io"]
  resources: ["leases"]
  verbs: ["get","list","watch","create","update","patch","delete"]
- apiGroups: [""]
  resources: ["events","configmaps","secrets","services"]
  verbs: ["get","list","watch","create","patch","update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: sdi-scheduler
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: sdi-scheduler
subjects:
- kind: ServiceAccount
  name: sdi-scheduler
  namespace: karmada-system
EOF
ok "RBAC 설정 완료"

# ────────────────────────────────────────────────────────────
hdr "4. ConfigMap"
# ────────────────────────────────────────────────────────────
step "sdi-scheduler-env ConfigMap 생성..."

${KL} apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: sdi-scheduler-env
  namespace: karmada-system
data:
  MALE_ACCURACY: "90"
  MALE_LATENCY:  "100"
  MALE_ENERGY:   "100"
  SERVICE_TYPE:  "inference"
EOF
ok "ConfigMap 생성 완료"

# ────────────────────────────────────────────────────────────
hdr "5. SDI Scheduler Deployment"
# ────────────────────────────────────────────────────────────
step "Deployment 생성: ${SDI_IMAGE}"

${KL} apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sdi-scheduler
  namespace: karmada-system
  labels:
    app: sdi-scheduler
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sdi-scheduler
  template:
    metadata:
      labels:
        app: sdi-scheduler
    spec:
      serviceAccountName: sdi-scheduler
      tolerations:
      - key: node-role.kubernetes.io/master
        operator: Exists
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
      containers:
      - name: sdi-scheduler
        image: ${SDI_IMAGE}
        imagePullPolicy: Always
        command: ["/bin/sdi-scheduler"]
        args:
        - --kubeconfig=/etc/karmada/config/karmada.config
        - --scheduler-name=sdi-scheduler
        - --enable-scheduler-estimator=false
        - --feature-gates=AllAlpha=true,AllBeta=true
        - --logging-format=json
        - --v=4
        env:
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        - name: SDI_DEFAULT_ALGORITHM
          value: "${DEFAULT_ALGORITHM}"
        - name: SDI_DEBUG
          value: "true"
        envFrom:
        - configMapRef:
            name: sdi-scheduler-env
        ports:
        - containerPort: 10351
          name: health
        livenessProbe:
          httpGet:
            path: /healthz
            port: 10351
          initialDelaySeconds: 15
          periodSeconds: 15
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
        volumeMounts:
        - name: karmada-config
          mountPath: /etc/karmada/config
          readOnly: true
        - name: karmada-cert
          mountPath: /etc/karmada/pki
          readOnly: true
      volumes:
      - name: karmada-config
        secret:
          secretName: sdi-scheduler-config
      - name: karmada-cert
        secret:
          secretName: karmada-cert
EOF
ok "Deployment 생성 완료"

# ────────────────────────────────────────────────────────────
hdr "6. 배포 완료 대기"
# ────────────────────────────────────────────────────────────
${KL} rollout status deployment/sdi-scheduler -n karmada-system --timeout=60s \
    && ok "SDI 스케줄러 Ready" \
    || warn "타임아웃 - 로그 확인: kubectl logs -n karmada-system -l app=sdi-scheduler"

echo ""
echo -e "${GREEN}━━━ 배포 완료 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "로그:"
echo "  kubectl logs -n karmada-system -l app=sdi-scheduler -f"
echo ""
echo "알고리즘 전환:"
echo "  ./03-switch-algorithm.sh"
echo ""
echo "워크로드 배포:"
echo "  ./04-deploy-workload.sh intent-driven"
