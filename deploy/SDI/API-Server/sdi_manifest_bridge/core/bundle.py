"""
ETRI IaC + MALE Binding 번들 입력 API 지원 모듈.

open-SDI/SDI-MALE-Interface Issue #1 합의 사항 구현:
  - IaCMaleBundle(workloadManifests[] + maleBindings[]) 스키마 정의
  - 번들 검증 (manifestId 매칭 실패 시 render 단계에서 거부, all-or-nothing)
  - maleBindings -> MaleWorkload CR 변환 (외부 API의 rtPeriodMs 등 단위 명시형 필드를
    CRD 필드 rtPeriod 등으로 매핑, targetRef는 apiVersion/kind/name만 유지)
  - Deployment 단위 PropagationPolicy 생성 (Service/ConfigMap/Secret 등 support
    리소스는 참조하는 Deployment의 정책에 포함되어 같은 클러스터로 전파)
"""
from typing import Any, Dict, List, Optional
from pydantic import BaseModel, Field

MALE_GROUP = 'male.keti.dev'
MALE_VERSION = 'v1alpha1'

# 워크로드(스코어링 대상) 외의 kind는 support 리소스로 취급
SUPPORT_KINDS = {'ConfigMap', 'Secret', 'Service', 'PersistentVolumeClaim'}

# 합의된 적용 순서: ConfigMap/Secret -> Deployment(워크로드) -> MaleWorkload -> PropagationPolicy
APPLY_ORDER = {
    'Namespace': 0,
    'ConfigMap': 1,
    'Secret': 1,
    'PersistentVolumeClaim': 1,
    # 그 외 워크로드/Service = 2 (기본값)
    'MaleWorkload': 3,
    'PropagationPolicy': 4,
}
DEFAULT_ORDER = 2


# ---------------------------------------------------------------------------
# 스키마 (Issue #1 예시 형태 기준)
# ---------------------------------------------------------------------------

class TargetRef(BaseModel):
    manifestId: str
    apiVersion: str = 'apps/v1'
    kind: str = 'Deployment'
    namespace: Optional[str] = None
    name: Optional[str] = None


class Importance(BaseModel):
    accuracy: float = Field(ge=0.0, le=1.0)
    latency: float = Field(ge=0.0, le=1.0)
    energy: float = Field(ge=0.0, le=1.0)


class MCSpec(BaseModel):
    criticality: Optional[str] = None
    # 외부 API는 단위 명시형(합의 사항). CRD 변환 시 rtPeriod 등으로 매핑됨.
    rtPeriodMs: Optional[int] = Field(default=None, ge=0)
    rtWcetMs: Optional[int] = Field(default=None, ge=0)
    rtDeadlineMs: Optional[int] = Field(default=None, ge=0)
    missionId: Optional[str] = None


class MaleBinding(BaseModel):
    id: Optional[str] = None
    targetRef: TargetRef
    mission: Optional[str] = None
    importance: Importance
    mcSpec: Optional[MCSpec] = None
    allowPolicyOverride: bool = True


class WorkloadManifest(BaseModel):
    id: str
    manifest: Dict[str, Any]


class IaCMaleBundle(BaseModel):
    apiVersion: str = 'sdi.keti.dev/v1alpha1'
    kind: str = 'IaCMaleBundle'
    bundleId: str
    # 상위 미션 ID (서브미션 그룹핑용, KETI 제안 규약 - 선택 필드로 하위 호환 유지)
    missionId: Optional[str] = None
    targetProfile: Optional[str] = None
    workloadManifests: List[WorkloadManifest] = Field(min_length=1)
    maleBindings: List[MaleBinding] = Field(default_factory=list)


# ---------------------------------------------------------------------------
# 검증 (all-or-nothing: 에러가 하나라도 있으면 번들 전체 거부)
# ---------------------------------------------------------------------------

def validate_bundle(bundle: IaCMaleBundle) -> List[str]:
    """번들의 정합성을 검사하고 에러 메시지 목록을 반환한다 (빈 목록 = 통과)."""
    errors: List[str] = []

    manifests_by_id: Dict[str, Dict[str, Any]] = {}
    for wm in bundle.workloadManifests:
        if wm.id in manifests_by_id:
            errors.append(f"duplicate workloadManifest id: '{wm.id}'")
            continue
        m = wm.manifest
        if not m.get('apiVersion') or not m.get('kind') or not (m.get('metadata') or {}).get('name'):
            errors.append(
                f"workloadManifest '{wm.id}': manifest must contain apiVersion, kind, metadata.name")
            continue
        manifests_by_id[wm.id] = m

    seen_binding_ids = set()
    for i, b in enumerate(bundle.maleBindings):
        label = b.id or f"maleBindings[{i}]"
        if b.id:
            if b.id in seen_binding_ids:
                errors.append(f"duplicate maleBinding id: '{b.id}'")
            seen_binding_ids.add(b.id)

        target = manifests_by_id.get(b.targetRef.manifestId)
        if target is None:
            errors.append(
                f"maleBinding '{label}': targetRef.manifestId "
                f"'{b.targetRef.manifestId}' not found in workloadManifests")
            continue

        meta = target.get('metadata') or {}
        checks = [
            ('apiVersion', b.targetRef.apiVersion, target.get('apiVersion')),
            ('kind', b.targetRef.kind, target.get('kind')),
            ('name', b.targetRef.name, meta.get('name')),
            ('namespace', b.targetRef.namespace, meta.get('namespace')),
        ]
        for field, expected, actual in checks:
            if expected is not None and expected != actual:
                errors.append(
                    f"maleBinding '{label}': targetRef.{field} '{expected}' does not match "
                    f"manifest '{b.targetRef.manifestId}' ({field}='{actual}')")

        if b.mcSpec and b.mcSpec.criticality and b.mcSpec.criticality not in ('A', 'B', 'C'):
            errors.append(
                f"maleBinding '{label}': mcSpec.criticality must be one of A/B/C, "
                f"got '{b.mcSpec.criticality}'")

    return errors


# ---------------------------------------------------------------------------
# 변환: maleBinding -> MaleWorkload CR, Deployment -> PropagationPolicy
# ---------------------------------------------------------------------------

def _build_maleworkload(bundle: IaCMaleBundle, binding: MaleBinding,
                        target: Dict[str, Any]) -> Dict[str, Any]:
    meta = target.get('metadata') or {}
    name = meta['name']
    namespace = meta.get('namespace', 'default')

    spec: Dict[str, Any] = {
        # 합의 사항: CRD targetRef에는 apiVersion/kind/name만 반영,
        # namespace는 MaleWorkload.metadata.namespace로 전달
        'targetRef': {
            'apiVersion': target['apiVersion'],
            'kind': target['kind'],
            'name': name,
        },
        'importance': binding.importance.model_dump(),
        'allowPolicyOverride': binding.allowPolicyOverride,
    }
    if binding.mission:
        spec['mission'] = binding.mission

    mc = binding.mcSpec
    if mc:
        mc_spec: Dict[str, Any] = {}
        if mc.criticality:
            mc_spec['criticality'] = mc.criticality
        # 외부 API(단위 명시형) -> CRD 필드명 매핑
        if mc.rtPeriodMs is not None:
            mc_spec['rtPeriod'] = mc.rtPeriodMs
        if mc.rtWcetMs is not None:
            mc_spec['rtWcet'] = mc.rtWcetMs
        if mc.rtDeadlineMs is not None:
            mc_spec['rtDeadline'] = mc.rtDeadlineMs
        # 상위 미션 그룹핑: binding에 없으면 번들 missionId 사용
        mission_id = mc.missionId or bundle.missionId
        if mission_id:
            mc_spec['missionId'] = mission_id
        if mc_spec:
            spec['mcSpec'] = mc_spec
    elif bundle.missionId:
        spec['mcSpec'] = {'missionId': bundle.missionId}

    return {
        'apiVersion': f'{MALE_GROUP}/{MALE_VERSION}',
        'kind': 'MaleWorkload',
        'metadata': {
            'name': f'{name}-workload',
            'namespace': namespace,
            'labels': {'managed-by': 'sdi-manifest-bridge', 'sdi.keti.dev/bundle': bundle.bundleId},
        },
        'spec': spec,
    }


def _deployment_refs(manifest: Dict[str, Any]) -> Dict[str, set]:
    """Deployment pod spec이 참조하는 ConfigMap/Secret 이름을 수집한다."""
    refs = {'ConfigMap': set(), 'Secret': set()}
    pod_spec = (((manifest.get('spec') or {}).get('template') or {}).get('spec') or {})

    for vol in pod_spec.get('volumes') or []:
        if 'configMap' in vol:
            refs['ConfigMap'].add(vol['configMap'].get('name'))
        if 'secret' in vol:
            refs['Secret'].add(vol['secret'].get('secretName'))

    for container in (pod_spec.get('containers') or []) + (pod_spec.get('initContainers') or []):
        for env in container.get('env') or []:
            source = env.get('valueFrom') or {}
            if 'configMapKeyRef' in source:
                refs['ConfigMap'].add(source['configMapKeyRef'].get('name'))
            if 'secretKeyRef' in source:
                refs['Secret'].add(source['secretKeyRef'].get('name'))
        for env_from in container.get('envFrom') or []:
            if 'configMapRef' in env_from:
                refs['ConfigMap'].add(env_from['configMapRef'].get('name'))
            if 'secretRef' in env_from:
                refs['Secret'].add(env_from['secretRef'].get('name'))
    return refs


def _service_matches(service: Dict[str, Any], deployment: Dict[str, Any]) -> bool:
    """Service selector가 Deployment pod 라벨의 부분집합이면 해당 Deployment 소속으로 본다."""
    selector = (service.get('spec') or {}).get('selector') or {}
    if not selector:
        return False
    pod_labels = ((((deployment.get('spec') or {}).get('template') or {})
                   .get('metadata') or {}).get('labels') or {})
    return all(pod_labels.get(k) == v for k, v in selector.items())


def _build_propagationpolicy(bundle: IaCMaleBundle, deployment: Dict[str, Any],
                             support: List[Dict[str, Any]]) -> Dict[str, Any]:
    meta = deployment['metadata']
    name = meta['name']
    namespace = meta.get('namespace', 'default')

    # 합의 사항: 스코어링 루트는 Deployment, support 리소스는 같은 정책에 포함하여
    # 결정된 클러스터로 함께 전파
    selectors = [{'apiVersion': deployment['apiVersion'], 'kind': deployment['kind'], 'name': name}]
    for res in support:
        selectors.append({
            'apiVersion': res['apiVersion'],
            'kind': res['kind'],
            'name': res['metadata']['name'],
        })

    return {
        'apiVersion': 'policy.karmada.io/v1alpha1',
        'kind': 'PropagationPolicy',
        'metadata': {
            'name': f'{name}-policy',
            'namespace': namespace,
            'labels': {'managed-by': 'sdi-manifest-bridge', 'sdi.keti.dev/bundle': bundle.bundleId},
        },
        'spec': {
            'resourceSelectors': selectors,
            'placement': {
                'clusterAffinities': [{'affinityName': 'intent-driven'}],
            },
            'schedulerName': 'sdi-scheduler',
        },
    }


def convert_bundle(bundle: IaCMaleBundle) -> List[Dict[str, Any]]:
    """
    검증을 통과한 번들을 실제 적용할 리소스 목록으로 변환한다.
    반환 순서 = 합의된 적용 순서 (ConfigMap/Secret -> 워크로드 -> MaleWorkload -> PropagationPolicy).
    """
    manifests_by_id = {wm.id: wm.manifest for wm in bundle.workloadManifests}

    deployments = [m for m in manifests_by_id.values() if m.get('kind') == 'Deployment']
    supports = [m for m in manifests_by_id.values() if m.get('kind') in SUPPORT_KINDS]

    resources: List[Dict[str, Any]] = list(manifests_by_id.values())

    for binding in bundle.maleBindings:
        target = manifests_by_id[binding.targetRef.manifestId]
        resources.append(_build_maleworkload(bundle, binding, target))

    # support 리소스는 참조하는 첫 Deployment의 정책에만 포함 (중복 selector 방지)
    claimed = set()
    for dep in deployments:
        refs = _deployment_refs(dep)
        owned = []
        for res in supports:
            key = (res['kind'], res['metadata']['name'])
            if key in claimed:
                continue
            kind = res['kind']
            if kind in ('ConfigMap', 'Secret') and res['metadata']['name'] in refs[kind]:
                owned.append(res)
                claimed.add(key)
            elif kind == 'Service' and _service_matches(res, dep):
                owned.append(res)
                claimed.add(key)
        resources.append(_build_propagationpolicy(bundle, dep, owned))

    resources.sort(key=lambda r: APPLY_ORDER.get(r.get('kind'), DEFAULT_ORDER))
    return resources


def resource_summary(resources: List[Dict[str, Any]]) -> List[Dict[str, str]]:
    """응답용 요약: 어떤 리소스가 어떤 순서로 적용되는지."""
    return [
        {
            'kind': r.get('kind', ''),
            'name': (r.get('metadata') or {}).get('name', ''),
            'namespace': (r.get('metadata') or {}).get('namespace', 'default'),
        }
        for r in resources
    ]
