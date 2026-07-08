#!/bin/bash
# ============================================================
# KETI SDI Karmada 설정 파일
# ============================================================
# 이 파일을 수정하여 환경에 맞게 설정하세요.
# ============================================================

# ─────────────────────────────────────────────────────────────
# Karmada 설정
# ─────────────────────────────────────────────────────────────
export KARMADA_KUBECONFIG="/etc/karmada/karmada-apiserver.config"

# ─────────────────────────────────────────────────────────────
# Edge 클러스터 설정
# ─────────────────────────────────────────────────────────────
# Edge 클러스터 접속 정보 (여러 개일 경우 배열로 확장 가능)
export EDGE_CLUSTER_NAME="edge-cluster"
export EDGE_CLUSTER_IP="10.0.0.39"
export EDGE_CLUSTER_USER="root"
# 주의: 프로덕션에서는 SSH 키 인증 사용 권장
export EDGE_CLUSTER_SSH_KEY="${HOME}/.ssh/id_rsa"

# SSH 비밀번호 (개발/테스트용, 프로덕션에서는 SSH 키 사용)
# 이 값은 환경변수로 설정하거나 ~/.keti-secrets에서 읽어옴
if [ -f "${HOME}/.keti-secrets" ]; then
    source "${HOME}/.keti-secrets"
fi
export EDGE_SSH_PASSWORD="${EDGE_SSH_PASSWORD:-}"

# ─────────────────────────────────────────────────────────────
# 테스트 기본값
# ─────────────────────────────────────────────────────────────
export DEFAULT_NAMESPACE="rt-test"
export DEFAULT_WORKLOAD_NAME="slam-processor"
export DEFAULT_RTCONTAINER_NAME="slam-rt"

# ─────────────────────────────────────────────────────────────
# MALE 기본값 (importance)
# ─────────────────────────────────────────────────────────────
export DEFAULT_ACCURACY="0.8"
export DEFAULT_LATENCY="0.5"
export DEFAULT_ENERGY="0.5"

# ─────────────────────────────────────────────────────────────
# MC (Mixed-Criticality) 기본값
# ─────────────────────────────────────────────────────────────
export DEFAULT_CRITICALITY="A"        # A: Best-Effort, B: Mission-Critical, C: Safety-Critical
export DEFAULT_RT_PERIOD="100"        # ms
export DEFAULT_RT_WCET="30"           # ms
export DEFAULT_RT_DEADLINE=""         # 빈값이면 rtPeriod와 동일

# ─────────────────────────────────────────────────────────────
# Container 기본값
# ─────────────────────────────────────────────────────────────
export DEFAULT_IMAGE="nginx:alpine"
export DEFAULT_CPU_REQUEST="100m"
export DEFAULT_CPU_LIMIT="500m"
export DEFAULT_MEMORY_REQUEST="128Mi"
export DEFAULT_MEMORY_LIMIT="256Mi"
export DEFAULT_REPLICAS="1"

# ─────────────────────────────────────────────────────────────
# Criticality 매핑 임계값
# MALE importance → MC criticality 자동 변환 기준
# ─────────────────────────────────────────────────────────────
export CRITICALITY_C_THRESHOLD="0.9"  # latency >= 0.9 → C (Safety-Critical)
export CRITICALITY_B_THRESHOLD="0.7"  # latency >= 0.7 → B (Mission-Critical)
                                       # latency < 0.7  → A (Best-Effort)

# ─────────────────────────────────────────────────────────────
# 유틸리티 함수
# ─────────────────────────────────────────────────────────────

# Edge 클러스터에 SSH 명령 실행
ssh_edge() {
    local cmd="$1"
    if [ -n "${EDGE_SSH_PASSWORD}" ]; then
        sshpass -p "${EDGE_SSH_PASSWORD}" ssh -o StrictHostKeyChecking=no \
            "${EDGE_CLUSTER_USER}@${EDGE_CLUSTER_IP}" "$cmd"
    elif [ -f "${EDGE_CLUSTER_SSH_KEY}" ]; then
        ssh -i "${EDGE_CLUSTER_SSH_KEY}" -o StrictHostKeyChecking=no \
            "${EDGE_CLUSTER_USER}@${EDGE_CLUSTER_IP}" "$cmd"
    else
        echo "Error: SSH 인증 방법이 설정되지 않았습니다."
        echo "EDGE_SSH_PASSWORD를 설정하거나 SSH 키를 생성하세요."
        return 1
    fi
}

# Criticality 자동 결정 (latency 기반)
get_criticality() {
    local latency="$1"
    if (( $(echo "$latency >= $CRITICALITY_C_THRESHOLD" | bc -l) )); then
        echo "C"
    elif (( $(echo "$latency >= $CRITICALITY_B_THRESHOLD" | bc -l) )); then
        echo "B"
    else
        echo "A"
    fi
}

# rtDeadline 기본값 설정
get_rt_deadline() {
    local deadline="$1"
    local period="$2"
    if [ -z "$deadline" ] || [ "$deadline" == "0" ]; then
        echo "$period"
    else
        echo "$deadline"
    fi
}

echo "[CONFIG] KETI SDI Karmada 설정 로드됨"
echo "  - Karmada: ${KARMADA_KUBECONFIG}"
echo "  - Edge: ${EDGE_CLUSTER_USER}@${EDGE_CLUSTER_IP}"
echo "  - Default Criticality: ${DEFAULT_CRITICALITY}"
