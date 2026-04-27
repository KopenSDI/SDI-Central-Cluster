
import logging
from kubernetes import config, client
from kubernetes.client.exceptions import ApiException
import yaml
import json
import os

# 로거 설정
logger = logging.getLogger(__name__)

class K8sClient:
    """
    쿠버네티스 클러스터와의 통신을 관리합니다.
    서버 사이드 적용(Server-Side Apply)을 사용하여 리소스를 생성/업데이트합니다.
    """

    def __init__(self):
       # --- 카르마다 설정 파일을 우선적으로 로드하도록 변경 ---
        karmada_config_path = "/etc/karmada/karmada-apiserver.config"
        try:
            if os.path.exists(karmada_config_path):
                # 카르마다 전용 설정 로드
                config.load_kube_config(config_file=karmada_config_path)
                logger.info(f"Successfully loaded Karmada config from {karmada_config_path}")
            else:
                # 파일이 없을 경우 기본 설정 시도
                try:
                    config.load_incluster_config()
                except config.ConfigException:
                    config.load_kube_config()
                logger.warning(f"Karmada config not found at {karmada_config_path}. Using default config.")
        except Exception as e:
            logger.error(f"Failed to load any K8s/Karmada config: {e}")
            # 클러스터 내부에서 실행될 때의 설정
           # config.load_incluster_config()
       # except config.ConfigException:
            # 로컬 환경에서 실행될 때 (개발용)
         #   config.load_kube_config()

#ssl검증 무시 설정
        configuration = client.Configuration.get_default_copy()
        configuration.verify_ssl = False
        client.Configuration.set_default(configuration)

        self.api_client = client.ApiClient()

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
            logger.info(f"Applying {kind}/{name} in {namespace} (dry_run={dry_run}) via {path}")
            
            data, status, _ = self.api_client.call_api(
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
