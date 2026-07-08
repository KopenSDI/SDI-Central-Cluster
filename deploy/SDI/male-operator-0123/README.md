# MALE-Operator 실행 테스트

## 개요

MALE-Operator의 MC Criticality 재정의 기능을 실제 클러스터에서 테스트하기 위한 디플로이먼트 및 스크립트입니다.

## 폴더 구조

```
male-operator-0123/
├── 01-prerequisites/       # 사전 요구사항 (CRD, Namespace, Policy)
├── 02-operator/           # MALE-Operator 배포
├── 03-test-workloads/     # 테스트용 워크로드 (3가지 MALE Paper Case)
├── 04-test-scripts/       # 테스트 실행 스크립트
└── 05-cleanup/            # 정리 스크립트
```

## 빠른 시작

```bash
cd /root/KETI_SDI_Central_Cluster/deploy/SDI/male-operator-0123

# 1. 전체 배포 (CRD + Policy + Operator + Test Workloads)
./04-test-scripts/deploy-all.sh

# 2. 결과 확인
./04-test-scripts/verify-results.sh

# 3. 정리
./05-cleanup/cleanup-all.sh
```

## 단계별 실행

```bash
# Step 1: CRD 및 네임스페이스 생성
kubectl apply -f 01-prerequisites/

# Step 2: Operator 배포
kubectl apply -f 02-operator/

# Step 3: 테스트 워크로드 배포
kubectl apply -f 03-test-workloads/

# Step 4: 결과 확인
./04-test-scripts/verify-results.sh
```

## 테스트 케이스

| 이름 | ALE Values | User Crit | Expected | 설명 |
|------|------------|-----------|----------|------|
| autonomous-vehicle | A=0.6, L=0.3, E=0.1 | A | **C** | 자율주행 패턴 |
| realtime-robot | A=0.1, L=0.7, E=0.2 | A | **B** | 실시간 로봇 |
| iot-sensor | A=0.2, L=0.1, E=0.7 | C | **A** | IoT 센서 |

## Operator 이미지

```
Image: ketidevit2/male-operator:v2-mc
```
