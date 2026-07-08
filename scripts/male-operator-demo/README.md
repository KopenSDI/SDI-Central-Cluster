# MALE-Operator MC Criticality 재정의 데모

## 개요

이 데모는 MALE-Operator의 **MC (Mixed-Criticality) Criticality 자동 재정의** 기능을 설명합니다.

MALE Paper에서 정의한 ALE (Accuracy, Latency, Energy) 중요도 값을 기반으로,
사용자가 지정한 Criticality 레벨을 자동으로 재정의하여 최적의 RT 스케줄링을 지원합니다.

## 전체 아키텍처

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              USER                                           │
│                                │                                            │
│                                ▼                                            │
│                    ┌─────────────────────┐                                  │
│                    │   MaleWorkload YAML │                                  │
│                    │   ─────────────────  │                                  │
│                    │   importance:        │                                  │
│                    │     A: 0.6, L: 0.3   │                                  │
│                    │   mcSpec:            │                                  │
│                    │     criticality: A   │  ◀─ 사용자 지정                 │
│                    └──────────┬──────────┘                                  │
│                               │ kubectl apply                               │
└───────────────────────────────┼─────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         CENTRAL CLUSTER                                     │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                        MALE-Operator                                  │  │
│  │                                                                       │  │
│  │   ┌─────────────┐    ┌─────────────┐    ┌─────────────────────────┐  │  │
│  │   │ 1. Watch    │───▶│ 2. Analyze  │───▶│ 3. Determine Criticality│  │  │
│  │   │ MaleWorkload│    │ ALE Values  │    │    (MALE Paper Rules)   │  │  │
│  │   └─────────────┘    └─────────────┘    └───────────┬─────────────┘  │  │
│  │                                                      │                │  │
│  │                                                      ▼                │  │
│  │                            ┌──────────────────────────────────────┐   │  │
│  │                            │ Rules Applied:                       │   │  │
│  │                            │                                      │   │  │
│  │                            │ IF L >= 0.9           → C            │   │  │
│  │                            │ IF L >= 0.7 && A >= 0.5 → C          │   │  │
│  │                            │ IF A >= 0.6 && L >= 0.3 → C ◀── 매칭!│   │  │
│  │                            │ IF A + L >= 0.9       → C            │   │  │
│  │                            │ IF L >= 0.5           → B            │   │  │
│  │                            │ IF E >= 0.5 && L < 0.5 → A           │   │  │
│  │                            └──────────────────────────────────────┘   │  │
│  │                                                      │                │  │
│  │                                                      ▼                │  │
│  │   ┌─────────────────────────────────────────────────────────────┐    │  │
│  │   │ 4. Update MaleWorkload Status                                │    │  │
│  │   │    ─────────────────────────────────────────────────────────  │    │  │
│  │   │    effectiveMcSpec:                                          │    │  │
│  │   │      criticality: C         ◀─ 재정의됨 (A → C)              │    │  │
│  │   │      missionType: accuracy-critical                          │    │  │
│  │   │      overrideReason: "Autonomous Vehicles pattern"           │    │  │
│  │   └─────────────────────────────────────────────────────────────┘    │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                │
                                │ Karmada Propagation
                                ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           EDGE CLUSTER                                      │
│                                                                             │
│  ┌─────────────────┐                    ┌─────────────────────────────┐    │
│  │   RTContainer   │◀───────────────────│       SDI-Scheduler         │    │
│  │   ─────────────  │                    │                             │    │
│  │   criticality: C │                    │   MC-aware scheduling:      │    │
│  │   rtPeriod: 100  │                    │   - C: Safety-Critical      │    │
│  │   rtWcet: 30     │                    │   - B: Mission-Critical     │    │
│  │   rtDeadline:100 │                    │   - A: Best-Effort RT       │    │
│  └─────────────────┘                    └─────────────────────────────┘    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 데이터 플로우 상세

```
┌────────────────────────────────────────────────────────────────────────────┐
│                          DATA FLOW DIAGRAM                                  │
└────────────────────────────────────────────────────────────────────────────┘

    ┌─────────────────────────────────────────────────────────────────────┐
    │                         INPUT (User YAML)                            │
    │  ─────────────────────────────────────────────────────────────────   │
    │  spec:                                                               │
    │    importance:                                                       │
    │      accuracy: 0.6  ──┐                                              │
    │      latency:  0.3  ──┼── ALE Values (MALE Paper)                   │
    │      energy:   0.1  ──┘                                              │
    │    mcSpec:                                                           │
    │      criticality: "A"  ◀── 사용자가 "낮음"으로 판단                  │
    │      rtPeriod: 100                                                   │
    │      rtWcet: 30                                                      │
    └───────────────────────────────────┬─────────────────────────────────┘
                                        │
                                        │ Reconcile Event
                                        ▼
    ┌─────────────────────────────────────────────────────────────────────┐
    │                     PROCESSING (MALE-Operator)                       │
    │  ─────────────────────────────────────────────────────────────────   │
    │                                                                      │
    │  Step 1: DetectMissionType(A=0.6, L=0.3, E=0.1)                     │
    │          └─▶ "accuracy-critical" (자율주행 패턴)                     │
    │                                                                      │
    │  Step 2: DetermineCriticality()                                      │
    │          ├─ Check: L >= 0.9?        ✗ (0.3 < 0.9)                   │
    │          ├─ Check: L >= 0.7 && A >= 0.5?  ✗ (0.3 < 0.7)             │
    │          ├─ Check: A >= 0.6 && L >= 0.3?  ✓ (0.6 >= 0.6, 0.3 >= 0.3)│
    │          └─▶ Criticality = C (Safety-Critical)                       │
    │                                                                      │
    │  Step 3: CompareWithUserValue()                                      │
    │          ├─ User: "A"                                                │
    │          ├─ Calculated: "C"                                          │
    │          └─▶ WasOverridden = true                                    │
    │                                                                      │
    └───────────────────────────────────┬─────────────────────────────────┘
                                        │
                                        │ Status Update
                                        ▼
    ┌─────────────────────────────────────────────────────────────────────┐
    │                       OUTPUT (Status)                                │
    │  ─────────────────────────────────────────────────────────────────   │
    │  status:                                                             │
    │    effectiveMcSpec:                                                  │
    │      criticality: "C"        ◀── 재정의됨!                          │
    │      missionType: "accuracy-critical"                                │
    │      overrideReason: "Accuracy-critical mission with moderate..."    │
    │      rtPeriod: 100                                                   │
    │      rtWcet: 30                                                      │
    │      rtDeadline: 100                                                 │
    │    mixedScore: 0.350                                                 │
    │    priorityClassName: "male-medium"                                  │
    │    conditions:                                                       │
    │      - type: Ready                                                   │
    │        status: "True"                                                │
    │        reason: Evaluated                                             │
    │        message: "Score: 0.350, PriorityClass: male-medium, Crit: C"  │
    └─────────────────────────────────────────────────────────────────────┘
```

## MC Criticality 재정의 규칙

```
┌────────────────────────────────────────────────────────────────────────────┐
│                    CRITICALITY DETERMINATION RULES                         │
│                    (MALE Paper Section IV 기반)                            │
└────────────────────────────────────────────────────────────────────────────┘

우선순위 (위에서 아래로 평가):

┌──────┬────────────────────────────────┬─────────────┬─────────────────────┐
│ Rule │ Condition                      │ Criticality │ Use Case            │
├──────┼────────────────────────────────┼─────────────┼─────────────────────┤
│  1   │ L >= 0.9                       │      C      │ Ultra-low-latency   │
│      │                                │             │ (Boston Dynamics)   │
├──────┼────────────────────────────────┼─────────────┼─────────────────────┤
│  2   │ L >= 0.7 AND A >= 0.5          │      C      │ Safety systems      │
│      │                                │             │ (perception+control)│
├──────┼────────────────────────────────┼─────────────┼─────────────────────┤
│  3   │ A >= 0.6 AND L >= 0.3          │      C      │ Autonomous Vehicles │
│      │                                │             │ (MALE Paper Case 1) │
├──────┼────────────────────────────────┼─────────────┼─────────────────────┤
│  4   │ A + L >= 0.9                   │      C      │ Combined high-req   │
│      │                                │             │ workloads           │
├──────┼────────────────────────────────┼─────────────┼─────────────────────┤
│  5   │ L >= 0.5                       │      B      │ Real-Time Robotics  │
│      │                                │             │ (MALE Paper Case 2) │
├──────┼────────────────────────────────┼─────────────┼─────────────────────┤
│  6   │ E >= 0.5 AND L < 0.5           │      A      │ IoT Sensors         │
│      │                                │             │ (MALE Paper Case 3) │
├──────┼────────────────────────────────┼─────────────┼─────────────────────┤
│  7   │ Default                        │      A      │ Best-Effort RT      │
└──────┴────────────────────────────────┴─────────────┴─────────────────────┘

Criticality Levels:
  ┌─────────────────────────────────────────────────────────────────────────┐
  │  C (Safety-Critical)   │ 데드라인 미스 = 재앙적 결과                   │
  │                        │ 예: 충돌 회피, 로봇 팔 제어                   │
  ├────────────────────────┼───────────────────────────────────────────────┤
  │  B (Mission-Critical)  │ 데드라인 미스 = 성능 저하                     │
  │                        │ 예: SLAM, 센서 융합                           │
  ├────────────────────────┼───────────────────────────────────────────────┤
  │  A (Best-Effort RT)    │ 데드라인 미스 = 허용 가능                     │
  │                        │ 예: 로깅, 모니터링                            │
  └────────────────────────┴───────────────────────────────────────────────┘
```

## MALE Paper 산업 사례

```
┌────────────────────────────────────────────────────────────────────────────┐
│                     MALE PAPER INDUSTRIAL CASES                            │
└────────────────────────────────────────────────────────────────────────────┘

Case 1: Autonomous Vehicles (자율주행)
══════════════════════════════════════════════════════════════════════════════
┌──────────────────────────────────────────────────────────────────────────┐
│  ALE Values:                                                              │
│    Accuracy: 0.6  ████████████░░░░░░░░  (높음 - 객체 인식)                │
│    Latency:  0.3  ██████░░░░░░░░░░░░░░  (중간 - 실시간 응답)              │
│    Energy:   0.1  ██░░░░░░░░░░░░░░░░░░  (낮음 - 차량 전원)                │
│                                                                           │
│  User Specified: A (Best-Effort)                                          │
│  MALE Result:    C (Safety-Critical)  ◀── 재정의!                        │
│                                                                           │
│  Reason: A >= 0.6 && L >= 0.3 → 자율주행 패턴 감지                        │
└──────────────────────────────────────────────────────────────────────────┘

Case 2: Real-Time Robotics (실시간 로봇)
══════════════════════════════════════════════════════════════════════════════
┌──────────────────────────────────────────────────────────────────────────┐
│  ALE Values:                                                              │
│    Accuracy: 0.1  ██░░░░░░░░░░░░░░░░░░  (낮음 - 기본 동작)                │
│    Latency:  0.7  ██████████████░░░░░░  (높음 - 즉시 응답)                │
│    Energy:   0.2  ████░░░░░░░░░░░░░░░░  (낮음)                            │
│                                                                           │
│  User Specified: A (Best-Effort)                                          │
│  MALE Result:    B (Mission-Critical)  ◀── 재정의!                       │
│                                                                           │
│  Reason: Latency-critical mission (L >= 0.7)                              │
└──────────────────────────────────────────────────────────────────────────┘

Case 3: IoT Sensor Networks (IoT 센서)
══════════════════════════════════════════════════════════════════════════════
┌──────────────────────────────────────────────────────────────────────────┐
│  ALE Values:                                                              │
│    Accuracy: 0.2  ████░░░░░░░░░░░░░░░░  (낮음 - 대략적 데이터)            │
│    Latency:  0.1  ██░░░░░░░░░░░░░░░░░░  (낮음 - 지연 허용)                │
│    Energy:   0.7  ██████████████░░░░░░  (높음 - 배터리 수명)              │
│                                                                           │
│  User Specified: C (Safety-Critical)                                      │
│  MALE Result:    A (Best-Effort RT)    ◀── 재정의!                       │
│                                                                           │
│  Reason: Energy-critical mission (E >= 0.5 && L < 0.5)                    │
└──────────────────────────────────────────────────────────────────────────┘
```

## 폴더 구조

```
scripts/male-operator-demo/
├── README.md                          # 이 파일
├── 01-architecture/
│   └── README.md                      # 아키텍처 다이어그램 및 설명
├── 02-crd/
│   ├── README.md                      # CRD 구조 설명
│   ├── example-autonomous-vehicle.yaml # Case 1 예제
│   ├── example-realtime-robot.yaml    # Case 2 예제
│   ├── example-iot-sensor.yaml        # Case 3 예제
│   └── example-policy.yaml            # MalePolicy 예제
├── 03-operator/
│   └── README.md                      # Operator 내부 구조 설명
├── 04-test/
│   ├── README.md                      # 테스트 가이드
│   ├── 01-deploy-prerequisites.sh     # 필수 리소스 배포
│   ├── 02-test-cases.sh               # MALE Paper 테스트 케이스
│   └── 03-verify-status.sh            # 상태 확인
└── 05-cleanup/
    ├── README.md                      # 정리 가이드
    ├── cleanup-test-resources.sh      # 테스트 리소스 정리
    └── cleanup-all.sh                 # 전체 정리
```

## 빠른 시작

```bash
cd /root/KETI_SDI_Central_Cluster/scripts/male-operator-demo

# 1. 필수 리소스 배포
chmod +x 04-test/*.sh 05-cleanup/*.sh
./04-test/01-deploy-prerequisites.sh

# 2. 테스트 실행
./04-test/02-test-cases.sh

# 3. 상태 확인
./04-test/03-verify-status.sh

# 4. 정리
./05-cleanup/cleanup-test-resources.sh
```

## Operator 이미지

```
Image: ketidevit2/male-operator:v2-mc
Registry: Docker Hub
```

## 참고 자료

- MALE Paper: "Multi-Objective Evaluation Method for AI Mobility Services across the Cloud-Edge-Device Continuum"
- Operator 소스: `/root/KETI_SDI_Central_Cluster/deploy/SDI/male-operator/`
- Demo 프로그램: `/root/KETI_SDI_Central_Cluster/deploy/SDI/male-operator/cmd/demo/main.go`
