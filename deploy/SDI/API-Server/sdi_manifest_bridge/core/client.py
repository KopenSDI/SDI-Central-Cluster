import os
import logging
from typing import Dict, Any, List
from kubernetes import client, config
from kubernetes.client.rest import ApiException

logger = logging.getLogger(__name__)

class SDIClient:
    def __init__(self):
        # Karmada API Server (지휘소) 설정 로드
        self.kkc_config_path = "/etc/karmada/karmada-apiserver.config"
        if os.path.exists(self.kkc_config_path):
            config.load_kube_config(config_file=self.kkc_config_path)
            logger.info(f"Loaded Karmada config from {self.kkc_config_path}")
        else:
            config.load_incluster_config()
            logger.info("Loaded in-cluster config")
        
        self.dynamic_client = client.CustomObjectsApi()
        self.apps_v1 = client.AppsV1Api()
        self.core_v1 = client.CoreV1Api()

    def apply_resources(self, resources: List[Dict[str, Any]]):
        """
        리스트로 넘어온 리소스들을 순서대로 적용
        """
        results = []
        for res in resources:
            kind = res.get('kind')
            name = res.get('metadata', {}).get('name')
            namespace = res.get('metadata', {}).get('namespace', 'default')
            
            logger.info(f"Applying {kind}: {namespace}/{name}")
            
            try:
                if kind == 'Deployment':
                    self._apply_deployment(namespace, res)
                elif kind == 'MaleWorkload':
                    self._apply_custom_resource(
                        group="male.keti.dev",
                        version="v1alpha1",
                        plural="maleworkloads",
                        namespace=namespace,
                        body=res
                    )
                elif kind == 'PropagationPolicy':
                    self._apply_custom_resource(
                        group="policy.karmada.io",
                        version="v1alpha1",
                        plural="propagationpolicies",
                        namespace=namespace,
                        body=res
                    )
                results.append({"kind": kind, "name": name, "status": "success"})
            except Exception as e:
                logger.error(f"Failed to apply {kind} {name}: {str(e)}")
                results.append({"kind": kind, "name": name, "status": "failed", "error": str(e)})
        
        return results

    def _apply_deployment(self, namespace: str, body: Dict[str, Any]):
        name = body['metadata']['name']
        try:
            self.apps_v1.read_namespaced_deployment(name, namespace)
            self.apps_v1.replace_namespaced_deployment(name, namespace, body)
            logger.info(f"Updated Deployment {name}")
        except ApiException as e:
            if e.status == 404:
                self.apps_v1.create_namespaced_deployment(namespace, body)
                logger.info(f"Created Deployment {name}")
            else: raise

    def _apply_custom_resource(self, group, version, plural, namespace, body):
        name = body['metadata']['name']
        try:
            self.dynamic_client.get_namespaced_custom_object(group, version, namespace, plural, name)
            self.dynamic_client.replace_namespaced_custom_object(group, version, namespace, plural, name, body)
            logger.info(f"Updated CR {plural} {name}")
        except ApiException as e:
            if e.status == 404:
                self.dynamic_client.create_namespaced_custom_object(group, version, namespace, plural, body)
                logger.info(f"Created CR {plural} {name}")
            else: raise
