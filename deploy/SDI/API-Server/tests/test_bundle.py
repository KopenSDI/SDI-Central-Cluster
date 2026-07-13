"""IaCMaleBundle 검증/변환 테스트 (open-SDI/SDI-MALE-Interface Issue #1 합의 기준)."""
import pytest
from pydantic import ValidationError

from sdi_manifest_bridge.core.bundle import (
    IaCMaleBundle, validate_bundle, convert_bundle,
)


def etri_example_bundle():
    """Issue #1 본문에 ETRI가 올린 예시를 그대로 옮긴 번들."""
    return {
        "apiVersion": "sdi.keti.dev/v1alpha1",
        "kind": "IaCMaleBundle",
        "bundleId": "etri-object-detection-001",
        "targetProfile": "kubernetes-karmada",
        "workloadManifests": [
            {
                "id": "deployment.object-detection",
                "manifest": {
                    "apiVersion": "apps/v1",
                    "kind": "Deployment",
                    "metadata": {"name": "object-detection", "namespace": "sdi-demo"},
                    "spec": {
                        "replicas": 1,
                        "selector": {"matchLabels": {"app": "object-detection"}},
                        "template": {
                            "metadata": {"labels": {"app": "object-detection"}},
                            "spec": {
                                "containers": [{
                                    "name": "detector",
                                    "image": "registry.example.com/sdi-detector:v0.1.0",
                                    "ports": [{"containerPort": 8080}],
                                    "resources": {
                                        "requests": {"cpu": "200m", "memory": "256Mi"},
                                        "limits": {"cpu": "500m", "memory": "512Mi"},
                                    },
                                }],
                            },
                        },
                    },
                },
            },
            {
                "id": "service.object-detection",
                "manifest": {
                    "apiVersion": "v1",
                    "kind": "Service",
                    "metadata": {"name": "object-detection", "namespace": "sdi-demo"},
                    "spec": {
                        "selector": {"app": "object-detection"},
                        "ports": [{"protocol": "TCP", "port": 80, "targetPort": 8080}],
                        "type": "ClusterIP",
                    },
                },
            },
        ],
        "maleBindings": [
            {
                "id": "male.object-detection",
                "targetRef": {
                    "manifestId": "deployment.object-detection",
                    "apiVersion": "apps/v1",
                    "kind": "Deployment",
                    "namespace": "sdi-demo",
                    "name": "object-detection",
                },
                "mission": "object-detection",
                "importance": {"accuracy": 0.3, "latency": 0.5, "energy": 0.2},
                "mcSpec": {
                    "criticality": "B",
                    "rtPeriodMs": 50,
                    "rtWcetMs": 20,
                    "rtDeadlineMs": 50,
                    "missionId": "object-detection",
                },
                "allowPolicyOverride": True,
            },
        ],
    }


def patrol_robot_bundle():
    """서브미션 2개(object-detection + slam)가 ConfigMap을 공유하는 다중 워크로드 번들."""

    def ros_deployment(name):
        return {
            "apiVersion": "apps/v1",
            "kind": "Deployment",
            "metadata": {"name": name, "namespace": "sdi-demo",
                         "labels": {"app": name, "mission": "patrol-robot"}},
            "spec": {
                "replicas": 1,
                "selector": {"matchLabels": {"app": name}},
                "template": {
                    "metadata": {"labels": {"app": name, "mission": "patrol-robot"}},
                    "spec": {
                        "hostNetwork": True,
                        "containers": [{
                            "name": name,
                            "image": f"registry.example.com/sdi-ros2-{name}:v0.1.0",
                            "env": [{"name": "CYCLONEDDS_URI",
                                     "value": "file:///config/cyclonedds.xml"}],
                            "volumeMounts": [{"name": "dds-config", "mountPath": "/config"}],
                        }],
                        "volumes": [{"name": "dds-config",
                                     "configMap": {"name": "cyclonedds-config"}}],
                    },
                },
            },
        }

    def binding(name, importance, rt):
        return {
            "id": f"male.{name}",
            "targetRef": {"manifestId": f"deployment.{name}", "apiVersion": "apps/v1",
                          "kind": "Deployment", "namespace": "sdi-demo", "name": name},
            "mission": name,
            "importance": importance,
            "mcSpec": {"criticality": "B", "rtPeriodMs": rt, "rtWcetMs": 20,
                       "rtDeadlineMs": rt, "missionId": "patrol-robot"},
            "allowPolicyOverride": True,
        }

    return {
        "apiVersion": "sdi.keti.dev/v1alpha1",
        "kind": "IaCMaleBundle",
        "bundleId": "etri-patrol-robot-001",
        "missionId": "patrol-robot",
        "workloadManifests": [
            {"id": "configmap.cyclonedds", "manifest": {
                "apiVersion": "v1", "kind": "ConfigMap",
                "metadata": {"name": "cyclonedds-config", "namespace": "sdi-demo"},
                "data": {"cyclonedds.xml": "<CycloneDDS/>"}}},
            {"id": "deployment.object-detection", "manifest": ros_deployment("object-detection")},
            {"id": "deployment.slam", "manifest": ros_deployment("slam")},
        ],
        "maleBindings": [
            binding("object-detection", {"accuracy": 0.6, "latency": 0.3, "energy": 0.1}, 50),
            binding("slam", {"accuracy": 0.1, "latency": 0.7, "energy": 0.2}, 100),
        ],
    }


# --- 검증 ------------------------------------------------------------------

def test_etri_example_passes_validation():
    bundle = IaCMaleBundle(**etri_example_bundle())
    assert validate_bundle(bundle) == []


def test_missing_manifest_id_rejected():
    data = etri_example_bundle()
    data["maleBindings"][0]["targetRef"]["manifestId"] = "deployment.typo"
    errors = validate_bundle(IaCMaleBundle(**data))
    assert len(errors) == 1
    assert "deployment.typo" in errors[0]
    assert "not found" in errors[0]


def test_target_mismatch_rejected():
    data = etri_example_bundle()
    data["maleBindings"][0]["targetRef"]["name"] = "wrong-name"
    errors = validate_bundle(IaCMaleBundle(**data))
    assert any("does not match" in e for e in errors)


def test_duplicate_manifest_id_rejected():
    data = etri_example_bundle()
    data["workloadManifests"].append(dict(data["workloadManifests"][0]))
    errors = validate_bundle(IaCMaleBundle(**data))
    assert any("duplicate workloadManifest id" in e for e in errors)


def test_invalid_criticality_rejected():
    data = etri_example_bundle()
    data["maleBindings"][0]["mcSpec"]["criticality"] = "Z"
    errors = validate_bundle(IaCMaleBundle(**data))
    assert any("criticality" in e for e in errors)


def test_importance_out_of_range_rejected_by_schema():
    data = etri_example_bundle()
    data["maleBindings"][0]["importance"]["accuracy"] = 1.5
    with pytest.raises(ValidationError):
        IaCMaleBundle(**data)


def test_empty_manifests_rejected_by_schema():
    data = etri_example_bundle()
    data["workloadManifests"] = []
    with pytest.raises(ValidationError):
        IaCMaleBundle(**data)


# --- 변환 ------------------------------------------------------------------

def by_kind(resources, kind):
    return [r for r in resources if r["kind"] == kind]


def test_etri_example_conversion():
    bundle = IaCMaleBundle(**etri_example_bundle())
    resources = convert_bundle(bundle)

    # 원본 manifest 2개 + MaleWorkload 1개 + PropagationPolicy 1개
    assert len(resources) == 4

    mw = by_kind(resources, "MaleWorkload")[0]
    # 합의: targetRef는 apiVersion/kind/name만, namespace는 metadata로
    assert mw["spec"]["targetRef"] == {
        "apiVersion": "apps/v1", "kind": "Deployment", "name": "object-detection"}
    assert mw["metadata"]["namespace"] == "sdi-demo"
    # 합의: 외부 API 단위 명시형 -> CRD 필드명 매핑
    assert mw["spec"]["mcSpec"]["rtPeriod"] == 50
    assert mw["spec"]["mcSpec"]["rtWcet"] == 20
    assert mw["spec"]["mcSpec"]["rtDeadline"] == 50
    assert "rtPeriodMs" not in mw["spec"]["mcSpec"]
    assert mw["spec"]["importance"] == {"accuracy": 0.3, "latency": 0.5, "energy": 0.2}

    # 합의: Service는 Deployment의 정책에 포함되어 같은 클러스터로 전파
    pp = by_kind(resources, "PropagationPolicy")[0]
    selected = {(s["kind"], s["name"]) for s in pp["spec"]["resourceSelectors"]}
    assert ("Deployment", "object-detection") in selected
    assert ("Service", "object-detection") in selected
    assert pp["spec"]["schedulerName"] == "sdi-scheduler"


def test_apply_order():
    bundle = IaCMaleBundle(**patrol_robot_bundle())
    kinds = [r["kind"] for r in convert_bundle(bundle)]
    # 합의된 순서: ConfigMap/Secret -> 워크로드 -> MaleWorkload -> PropagationPolicy
    assert kinds.index("ConfigMap") < kinds.index("Deployment")
    assert max(i for i, k in enumerate(kinds) if k == "Deployment") \
        < min(i for i, k in enumerate(kinds) if k == "MaleWorkload")
    assert max(i for i, k in enumerate(kinds) if k == "MaleWorkload") \
        < min(i for i, k in enumerate(kinds) if k == "PropagationPolicy")


def test_patrol_robot_mission_grouping():
    bundle = IaCMaleBundle(**patrol_robot_bundle())
    resources = convert_bundle(bundle)

    workloads = by_kind(resources, "MaleWorkload")
    assert len(workloads) == 2
    # 서브미션 규약: mission = 서브미션 이름, mcSpec.missionId = 상위 미션
    for mw in workloads:
        assert mw["spec"]["mcSpec"]["missionId"] == "patrol-robot"
    assert {mw["spec"]["mission"] for mw in workloads} == {"object-detection", "slam"}

    # 공유 ConfigMap은 첫 번째 Deployment의 정책에만 포함 (중복 selector 방지)
    policies = by_kind(resources, "PropagationPolicy")
    assert len(policies) == 2
    cm_owners = [p for p in policies
                 if any(s["kind"] == "ConfigMap" for s in p["spec"]["resourceSelectors"])]
    assert len(cm_owners) == 1


def test_bundle_mission_id_fallback():
    """binding의 mcSpec.missionId가 없으면 번들 최상위 missionId를 사용한다."""
    data = patrol_robot_bundle()
    for b in data["maleBindings"]:
        del b["mcSpec"]["missionId"]
    resources = convert_bundle(IaCMaleBundle(**data))
    for mw in by_kind(resources, "MaleWorkload"):
        assert mw["spec"]["mcSpec"]["missionId"] == "patrol-robot"
