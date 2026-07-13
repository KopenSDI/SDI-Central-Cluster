
import logging
from kubernetes import config, client
from kubernetes.client.exceptions import ApiException
import yaml
import json
import os

# 로거 설정
logger = logging.getLogger(__name__)


# 모든 번들 리소스는 Karmada apiserver로 간다. MaleWorkload CRD도 Karmada에 설치되어
# 있고 male-operator가 Karmada를 감시한다 (2026-03 전환; 호스트 클러스터의 CRD는 레거시).
# 호스트 클러스터로 보내야 하는 리소스가 생기면 여기에 kind를 추가.
HOST_ONLY_KINDS: set = set()


def _load_api_client(config_path: str, fallback_incluster: bool, label: str) -> client.ApiClient:
    """주어진 kubeconfig 경로(또는 in-cluster/default)로 별도의 ApiClient를 만든다."""
    try:
        if os.path.exists(config_path):
            configuration = client.Configuration()
            config.load_kube_config(config_file=config_path, client_configuration=configuration)
            logger.info(f"Successfully loaded {label} config from {config_path}")
        elif fallback_incluster:
            configuration = client.Configuration()
            try:
                config.load_incluster_config(client_configuration=configuration)
            except config.ConfigException:
                config.load_kube_config(client_configuration=configuration)
            logger.warning(f"{label} config not found at {config_path}. Using default config.")
        else:
            configuration = client.Configuration()
            config.load_kube_config(client_configuration=configuration)
            logger.warning(f"{label} config not found at {config_path}. Using default kube config.")
    except Exception as e:
        logger.error(f"Failed to load {label} K8s config: {e}")
        configuration = client.Configuration()

    configuration.verify_ssl = False
    return client.ApiClient(configuration)


class K8sClient:
    """
    쿠버네티스 클러스터와의 통신을 관리합니다.
    서버 사이드 적용(Server-Side Apply)을 사용하여 리소스를 생성/업데이트합니다.

    Karmada(멀티클러스터 전파 대상)와 호스트 클러스터(MaleWorkload 등 센트럴 전용
    리소스)에 각각 별도의 ApiClient로 연결하고, 리소스 kind에 따라 적절한 쪽으로 보낸다.
    """

    def __init__(self):
        self.karmada_api_client = _load_api_client(
            "/etc/karmada/karmada-apiserver.config", fallback_incluster=True, label="Karmada")
        self.host_api_client = _load_api_client(
            "/root/.kube/config", fallback_incluster=True, label="Host cluster")

    def apply(self, manifest: dict, dry_run: bool = False) -> dict:
        """
        Server-Side Apply를 사용하여 리소스를 생성/업데이트합니다.
        apiVersion과 kind를 분석하여 적절한 API 경로를 동적으로 생성합니다.
        """
        api_version = manifest.get("apiVersion")
        kind = manifest.get("kind")
        meta = manifest.get("metadata", {}) or {}
        name = meta.get("name")
        namespace = meta.get("namespace") or "default"

        if not api_version or not kind or not name:
            raise ValueError("Resource manifest must contain apiVersion, kind, and metadata.name")

        api_client = self.host_api_client if kind in HOST_ONLY_KINDS else self.karmada_api_client

        # 리소스 종류에 따른 복수형 이름(Plural) 결정
        plural_mapping = {
            "Deployment": "deployments",
            "MaleWorkload": "maleworkloads",
            "Pod": "pods",
            "Service": "services",
            "StatefulSet": "statefulsets",
            "Job": "jobs"
        }
        plural = plural_mapping.get(kind, kind.lower() + "s")
        if plural.endswith("ys"): # e.g. Policy -> Policies (예외 처리용)
            plural = plural[:-2] + "ies"

        # API 경로 생성
        if "/" in api_version:
            # 커스텀 리소스 (e.g., apps/v1, opensdi.opensdi.io/v1alpha1)
            group, version = api_version.split("/")
            path = f"/apis/{group}/{version}/namespaces/{namespace}/{plural}/{name}"
        else:
            # 코어 리소스 (e.g., v1)
            path = f"/api/{api_version}/namespaces/{namespace}/{plural}/{name}"

        # SSA 설정: PATCH + application/apply-patch+yaml
        query = [("fieldManager", "sdi-manifest-bridge"), ("force", "true")]
        if dry_run:
            query.append(("dryRun", "All"))

        headers = {
            "Content-Type": "application/apply-patch+yaml",
            "Accept": "application/json"
        }

        try:
            target = "host cluster" if kind in HOST_ONLY_KINDS else "Karmada"
            logger.info(f"Applying {kind}/{name} in {namespace} (dry_run={dry_run}) via {path} [{target}]")

            data, status, _ = api_client.call_api(
                path, "PATCH",
                path_params={},
                query_params=query,
                header_params=headers,
                body=manifest,
                auth_settings=["BearerToken"],
                response_type="object",
                _preload_content=True,
            )
            logger.info(f"Successfully applied {kind}/{name} (status={status})")
            return data
        except ApiException as e:
            logger.error(f"Failed to apply {kind}/{name}: {e.body if hasattr(e, 'body') else e}")
            raise e


# 싱글턴 인스턴스 생성
k8s_client = K8sClient()
