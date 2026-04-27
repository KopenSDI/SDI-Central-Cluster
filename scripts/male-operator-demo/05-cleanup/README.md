# 정리 스크립트

## 개요

테스트 후 생성된 리소스를 정리하는 스크립트입니다.

## 스크립트 목록

| 파일 | 설명 |
|------|------|
| `cleanup-test-resources.sh` | 테스트 리소스만 삭제 (MaleWorkload, 테스트 Deployment) |
| `cleanup-all.sh` | 전체 삭제 (Operator, Policy, CRD 포함) |

## 사용 방법

### 테스트 리소스만 정리

```bash
./cleanup-test-resources.sh
```

삭제되는 리소스:
- 모든 MaleWorkload
- 테스트용 Deployment (deploy-av, deploy-robot, deploy-iot 등)

유지되는 리소스:
- MALE-Operator
- MalePolicy
- CRD

### 전체 정리

```bash
./cleanup-all.sh
```

삭제되는 리소스:
- 모든 MaleWorkload
- 모든 MalePolicy
- MALE-Operator
- CRD (선택)

## 수동 정리 명령어

```bash
# MaleWorkload 전체 삭제
kubectl delete maleworkload --all -A

# MalePolicy 전체 삭제
kubectl delete malepolicy --all

# Operator 삭제
kubectl delete deployment male-controller-manager -n male-system

# CRD 삭제 (주의: 모든 CR도 함께 삭제됨)
kubectl delete crd maleworkloads.male.keti.dev
kubectl delete crd malepolicies.male.keti.dev
```
