# 테스트 스크립트

## 개요

이 폴더에는 MALE-Operator의 MC Criticality 재정의 기능을 테스트하는 스크립트가 포함되어 있습니다.

## 스크립트 목록

| 파일 | 설명 |
|------|------|
| `01-deploy-prerequisites.sh` | 테스트 전 필수 리소스 배포 (CRD, Policy, Operator) |
| `02-test-cases.sh` | MALE Paper 3가지 산업 사례 테스트 |
| `03-verify-status.sh` | 모든 MaleWorkload 상태 확인 |

## 실행 순서

```bash
# 1. 필수 리소스 배포
./01-deploy-prerequisites.sh

# 2. 테스트 케이스 실행
./02-test-cases.sh

# 3. 상태 확인 (선택)
./03-verify-status.sh
```

## 테스트 케이스

### Case 1: Autonomous Vehicles (자율주행)

```
입력:
  - accuracy: 0.6
  - latency: 0.3
  - energy: 0.1
  - user criticality: A

예상 결과:
  - effective criticality: C
  - missionType: accuracy-critical
  - 이유: A >= 0.6 && L >= 0.3 (자율주행 패턴)
```

### Case 2: Real-Time Robotics (실시간 로봇)

```
입력:
  - accuracy: 0.1
  - latency: 0.7
  - energy: 0.2
  - user criticality: A

예상 결과:
  - effective criticality: B
  - missionType: latency-critical
  - 이유: Latency-critical mission (L >= 0.7)
```

### Case 3: IoT Sensor Networks (IoT 센서)

```
입력:
  - accuracy: 0.2
  - latency: 0.1
  - energy: 0.7
  - user criticality: C

예상 결과:
  - effective criticality: A
  - missionType: energy-critical
  - 이유: Energy-critical mission (E >= 0.5 && L < 0.5)
```

## 예상 출력

```
============================================================
 테스트 결과 요약
============================================================

PASS: 3
FAIL: 0

모든 테스트 통과!
```
