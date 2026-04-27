import os
from typing import Dict, Any, List
from ruamel.yaml import YAML
from io import StringIO

yaml = YAML()
yaml.indent(mapping=2, sequence=4, offset=2)

def enrich_manifest(user_input: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    Ansible 입력 -> [Deployment, MaleWorkload, PropagationPolicy] 세트 생성
    """
    mission         = user_input.get('mission', 'default')
    container_name = user_input.get('container_name', 'app')
    image          = user_input.get('image', '')
    namespace      = user_input.get('namespace', 'sdi-demo')
    name           = f"{mission}-{container_name}"

    # 앤시블에서 받은 float 값 그대로 사용 (0~1)
    accuracy_val = float(user_input.get('accuracy', 0.5))
    latency_val  = float(user_input.get('latency', 0.3))
    energy_val   = float(user_input.get('energy', 0.2))
    
    criticality = user_input.get('criticality', 'A')

    # 1. Deployment 생성 (순수 워크로드)
    deployment = {
        'apiVersion': 'apps/v1',
        'kind': 'Deployment',
        'metadata': {
            'name': name,
            'namespace': namespace,
            'labels': {
                'mission': mission,
                'app': name,
                'managed-by': 'sdi-manifest-bridge'
            }
        },
        'spec': {
            'replicas': 1,
            'selector': {
                'matchLabels': {'app': name},
            },
            'template': {
                'metadata': {
                    'labels': {
                        'app': name,
                        'mission': mission,
                    },
                },
                'spec': {
                    # schedulerName: 'sdi-scheduler'를 제거하여 에지의 기본 스케줄러가 파드를 실행하게 함
                    'containers': [{
                        'name': container_name,
                        'image': image,
                        'resources': {
                            'requests': {'cpu': '100m', 'memory': '128Mi'},
                            'limits': {'cpu': '500m', 'memory': '256Mi'}
                        }
                    }],
                },
            },
        },
    }

    # 2. MaleWorkload 생성 (의도 주입)
    maleworkload = {
        'apiVersion': 'male.keti.dev/v1alpha1',
        'kind': 'MaleWorkload',
        'metadata': {
            'name': f"{name}-workload",
            'namespace': namespace,
        },
        'spec': {
            'targetRef': {
                'apiVersion': 'apps/v1',
                'kind': 'Deployment',
                'name': name,
            },
            'mission': mission,
            'importance': {
                'accuracy': accuracy_val,
                'latency':  latency_val,
                'energy':   energy_val,
            },
            'mcSpec': {
                'criticality': criticality,
                'missionId': mission,
                'rtPeriod': int(user_input.get('rt_period', 100)),
                'rtWcet': int(user_input.get('rt_wcet', 30)),
                'rtDeadline': int(user_input.get('rt_deadline', 100)),
            },
            'allowPolicyOverride': True
        },
    }

    # 3. PropagationPolicy 생성 (배포 지시서)
    propagationpolicy = {
        'apiVersion': 'policy.karmada.io/v1alpha1',
        'kind': 'PropagationPolicy',
        'metadata': {
            'name': f"{name}-policy",
            'namespace': namespace,
        },
        'spec': {
            'resourceSelectors': [
                {
                    'apiVersion': 'apps/v1',
                    'kind': 'Deployment',
                    'name': name
                }
            ],
            'placement': {
                'clusterAffinities': [
                    {
                        'affinityName': 'intent-driven' # 기본 알고리즘
                    }
                ]
            },
            'schedulerName': 'sdi-scheduler'
        }
    }

    # 사용자 정의 라벨/어노테이션이 있다면 Deployment에만 병합
    if user_input.get('labels'):
        deployment['metadata']['labels'].update(user_input['labels'])
    if user_input.get('annotations'):
        deployment['metadata']['annotations'] = user_input['annotations']

    return [deployment, maleworkload, propagationpolicy]

def to_yaml_string(data: List[Dict[str, Any]] | Dict[str, Any]) -> str:
    if not isinstance(data, list): data = [data]
    documents = []
    for doc in data:
        stream = StringIO()
        yaml.dump(doc, stream)
        documents.append(stream.getvalue())
    return "---\n".join(documents)
