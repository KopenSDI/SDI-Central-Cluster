from typing import Dict, Any, Optional
import logging
from datetime import datetime


class ALEWeightManager:
    def __init__(self):
        self.ale_weights = {}
        self.logger = logging.getLogger(__name__)
        # 실측 기반 점수화 파라미터 (데이터 파이프라인이 채워지기 전에는 fallback 사용)
        self.DEFAULT_NEUTRAL_SCORE = 50.0   # 실측값이 없을 때 쓰는 중립 점수
        self.LATENCY_REFERENCE_MS = 500.0   # 이 지연(ms) 이상이면 지연 점수 0으로 수렴
        self.ENERGY_FULL_WH = 500.0         # 완충 기준 배터리 용량(wh)
        self._init_default_weights()
    # 가중치 초기화 -- 파이썬이라 안하면 생성이안됨
    def _init_default_weights(self):
      
        self.ale_weights['default'] = {
            'device_id': 'default',
            'accuracy_weight': 0.4,  # 40%
            'latency_weight': 0.3,   # 30% 
            'energy_weight': 0.3,    # 30%
            'description': 'Default ALE Weight',
            'last_updated': datetime.now().isoformat()
        }
        self.logger.info("Default ALE Wegight Init")
    
    #디바이스별 ALE 가중치 조회 device_id= 디바이스 아이디 return ㄴ
    def get_weight(self, device_id: str = "") -> Dict[str, Any]:
        """
        디바이스별 ALE 가중치 조회
        
        Args:
            device_id: 디바이스 ID (빈 문자열이면 기본 가중치 반환)
            
        Returns:
            ALE 가중치 정보
        """
        try:
            # 디바이스 ID가 없으면 기본 가중치 반환
            if not device_id or device_id == "":
                device_id = "default"
            
            # 해당 디바이스의 가중치가 있으면 반환
            if device_id in self.ale_weights:
                weight_data = self.ale_weights[device_id].copy()
                weight_data['device_id'] = device_id
                return {
                    'success': True,
                    'message': f'{device_id} ALE 가중치 조회 완료',
                    'weights': weight_data
                }
            
            # 디바이스별 가중치가 없으면 기본 가중치를 복사해서 반환
            default_weights = self.ale_weights['default'].copy()
            default_weights['device_id'] = device_id
            default_weights['description'] = f'{device_id} 디바이스용 기본 가중치'
            
            return {
                'success': True,
                'message': f'{device_id} 기본 ALE 가중치 반환',
                'weights': default_weights
            }
            
        except Exception as e:
            self.logger.error(f"ALE 가중치 조회 실패 ({device_id}): {e}")
            return {
                'success': False,
                'message': f'ALE 가중치 조회 실패: {str(e)}',
                'weights': None
            }
    
    def set_weight(self, device_id: str, accuracy_weight: float, latency_weight: float, 
                   energy_weight: float, description: str = "") -> Dict[str, Any]:
        """
        디바이스별 ALE 가중치 설정
        
        Args:
            device_id: 디바이스 ID
            accuracy_weight: 정확도 가중치 (0-1)
            latency_weight: 지연시간 가중치 (0-1)
            energy_weight: 에너지 가중치 (0-1)
            description: 가중치 설명
            
        Returns:
            설정 결과
        """
        try:
            # 가중치 유효성 검사
            validation_result = self._validate_weights(accuracy_weight, latency_weight, energy_weight)
            if not validation_result['valid']:
                return {
                    'success': False,
                    'message': validation_result['message'],
                    'weights': None
                }
            
            # 정규화된 가중치 사용
            normalized_weights = validation_result['normalized_weights']
            
            # 디바이스 ID 검증
            if not device_id or device_id.strip() == "":
                device_id = "default"
            
            # 가중치 저장
            weight_data = {
                'device_id': device_id,
                'accuracy_weight': normalized_weights['accuracy'],
                'latency_weight': normalized_weights['latency'],
                'energy_weight': normalized_weights['energy'],
                'description': description or f'{device_id} ALE 가중치',
                'last_updated': datetime.now().isoformat()
            }
            
            self.ale_weights[device_id] = weight_data
            
            self.logger.info(f"ALE 가중치 설정 완료: {device_id} -> A:{normalized_weights['accuracy']:.3f}, L:{normalized_weights['latency']:.3f}, E:{normalized_weights['energy']:.3f}")
            
            return {
                'success': True,
                'message': f'{device_id} ALE 가중치 설정 완료',
                'weights': weight_data.copy()
            }
            
        except Exception as e:
            self.logger.error(f"ALE 가중치 설정 실패 ({device_id}): {e}")
            return {
                'success': False,
                'message': f'ALE 가중치 설정 실패: {str(e)}',
                'weights': None
            }

    # 값 이상한거 넣는지 확인 ...
    def _validate_weights(self, accuracy_weight: float, latency_weight: float, 
                         energy_weight: float) -> Dict[str, Any]:
        try:
            if not (0 <= accuracy_weight <= 1):
                return {
                    'valid': False,
                    'message': 'accuracy_weight는 0과 1 사이의 값이어야 합니다'
                }
            
            if not (0 <= latency_weight <= 1):
                return {
                    'valid': False,
                    'message': 'latency_weight는 0과 1 사이의 값이어야 합니다'
                }
                
            if not (0 <= energy_weight <= 1):
                return {
                    'valid': False,
                    'message': 'energy_weight는 0과 1 사이의 값이어야 합니다'
                }
            # # 없어도 될듯하여 주석처리 함 개별가중치로 계싼함
            # # A+L+E 가중치 합은 1보다 넘지않게게
            # total_weight = accuracy_weight + latency_weight + energy_weight
            # if not (0.9 <= total_weight <= 1.1):
            #     return {
            #         'valid': False,
            #         'message': f'가중치 합이 1.0에 가까워야 합니다 (현재: {total_weight:.3f})'
            #     }
            
            # # 없어도 될듯하여 주석처리 함 
            # if total_weight != 1.0:
            #     accuracy_weight = accuracy_weight / total_weight
            #     latency_weight = latency_weight / total_weight  
            #     energy_weight = energy_weight / total_weight
            
            return {
                'valid': True,
                'message': '가중치 유효성 검사 통과',
                'normalized_weights': {
                    'accuracy': round(accuracy_weight, 3),
                    'latency': round(latency_weight, 3),
                    'energy': round(energy_weight, 3)
                }
            }
            
        except Exception as e:
            return {
                'valid': False,
                'message': f'가중치 검사 중 오류: {str(e)}'
            }
    
    def _validate_metric_values(self, accuracy_value: float, latency_value: float, 
                               energy_value: float) -> Dict[str, Any]:
        """메트릭 값 유효성 검사"""
        if not (0 <= accuracy_value <= 1000):
            return {
                'valid': False,
                'message': 'accuracy_value는 0과 1000 사이의 값이어야 합니다'
            }
            
        if not (0 <= latency_value <= 1000):
            return {
                'valid': False,
                'message': 'latency_value는 0과 1000 사이의 값이어야 합니다'
            }
            
        if not (0 <= energy_value <= 1000):
            return {
                'valid': False,
                'message': 'energy_value는 0과 1000 사이의 값이어야 합니다'
            }
        
        return {
            'valid': True,
            'message': '메트릭 값 유효성 검사 통과'
        }
    
    # MALE 값이 어떻게 들어오는지 모르겠으나 0~1000사이라고 했을때 스코어링 점수를 그대로 반영하기엔 너무크기때문에 100~점대로 변환
    #A = 높을수록 좋음 L 낮을수록 좋음 , E 높을 수록 좋음 으로 정의함 -기철철
    def _convert_metrics_to_scores(self, accuracy_value: float, latency_value: float, 
                                  energy_value: float) -> Dict[str, float]:
        accuracy_score = min(100.0, (accuracy_value / 1000.0) * 100.0)
        latency_score = max(0.0, 100.0 - (latency_value / 1000.0) * 100.0)
        energy_score = min(100.0, (energy_value / 1000.0) * 100.0)
        
        return {
            'accuracy': accuracy_score,
            'latency': latency_score,
            'energy': energy_score
        }
    
    def get_all_weights(self) -> Dict[str, Any]:
        try:
            # 가중치를 리스트 형태로 변환 (etcd 스타일)
            weights_list = []
            for device_id, weight_data in self.ale_weights.items():
                weights_list.append(weight_data.copy())
            
            return {
                'success': True,
                'message': f'총 {len(weights_list)}개 디바이스의 ALE 가중치 조회 완료',
                'total_devices': len(weights_list),
                'weights': weights_list  # 리스트 형태로 반환
            }
        except Exception as e:
            self.logger.error(f"모든 가중치 조회 실패: {e}")
            return {
                'success': False,
                'message': f'모든 가중치 조회 실패: {str(e)}',
                'total_devices': 0,
                'weights': []
            }
    
    def get_weights_by_device_list(self, device_ids: list) -> Dict[str, Any]:
        """특정 디바이스 목록의 가중치 조회"""
        try:
            weights_list = []
            not_found_devices = []
            
            for device_id in device_ids:
                if device_id in self.ale_weights:
                    weights_list.append(self.ale_weights[device_id].copy())
                else:
                    # 디바이스별 가중치가 없으면 기본 가중치를 복사
                    default_weights = self.ale_weights['default'].copy()
                    default_weights['device_id'] = device_id
                    default_weights['description'] = f'{device_id} 디바이스용 기본 가중치'
                    weights_list.append(default_weights)
                    not_found_devices.append(device_id)
            
            message = f'{len(weights_list)}개 디바이스의 ALE 가중치 조회 완료'
            if not_found_devices:
                message += f' (기본 가중치 적용: {", ".join(not_found_devices)})'
            
            return {
                'success': True,
                'message': message,
                'total_devices': len(weights_list),
                'weights': weights_list,
                'default_applied': not_found_devices
            }
        except Exception as e:
            self.logger.error(f"디바이스 목록 가중치 조회 실패: {e}")
            return {
                'success': False,
                'message': f'디바이스 목록 가중치 조회 실패: {str(e)}',
                'total_devices': 0,
                'weights': [],
                'default_applied': []
            }
    

    
    # ========================================================================================
    # ALE 점수 계산 함수들 (실제 디바이스 Accuracy, Latency, Energy 점수)
    # ========================================================================================
    
    def calculate_ale_scores_for_device(self, device_id: str, device_data: Dict[str, Any] = None) -> Dict[str, Any]:
        """
        단일 디바이스의 ALE 점수 계산
        
        Args:
            device_id: 디바이스 ID
            device_data: 디바이스 상태 데이터 (옵션)
            
        Returns:
            ALE 점수 결과 (Accuracy, Latency, Energy 각각 0-100점)
        """
        try:
            # 실제 ALE 점수 계산
            accuracy_score = self._calculate_accuracy_score(device_id, device_data)
            latency_score = self._calculate_latency_score(device_id, device_data)
            energy_score = self._calculate_energy_score(device_id, device_data)
            
            ale_scores = {
                'device_id': device_id,
                'accuracy_score': round(accuracy_score, 2),
                'latency_score': round(latency_score, 2),
                'energy_score': round(energy_score, 2),
                'calculation_timestamp': datetime.now().isoformat()
            }
            
            self.logger.info(f"ALE 점수 계산: {device_id} -> A:{accuracy_score:.1f}, L:{latency_score:.1f}, E:{energy_score:.1f}")
            
            return {
                'success': True,
                'message': f'{device_id} ALE 점수 계산 완료',
                'ale_scores': ale_scores
            }
            
        except Exception as e:
            self.logger.error(f"ALE 점수 계산 실패 ({device_id}): {e}")
            return {
                'success': False,
                'message': f'ALE 점수 계산 실패: {str(e)}',
                'ale_scores': None
            }
    
    def calculate_ale_scores_for_devices(self, device_ids: list, devices_data: Dict[str, Any] = None) -> Dict[str, Any]:
        """
        다중 디바이스의 ALE 점수 계산
        
        Args:
            device_ids: 디바이스 ID 목록
            devices_data: 디바이스들의 상태 데이터 (옵션)
            
        Returns:
            다중 디바이스 ALE 점수 결과
        """
        try:
            ale_scores_list = []
            failed_devices = []
            
            for device_id in device_ids:
                device_data = devices_data.get(device_id) if devices_data else None
                result = self.calculate_ale_scores_for_device(device_id, device_data)
                
                if result.get('success', False):
                    ale_scores_list.append(result['ale_scores'])
                else:
                    failed_devices.append(device_id)
            
            return {
                'success': True,
                'message': f'{len(ale_scores_list)}개 디바이스 ALE 점수 계산 완료',
                'total_devices': len(device_ids),
                'ale_scores': ale_scores_list,
                'failed_devices': failed_devices
            }
            
        except Exception as e:
            self.logger.error(f"다중 디바이스 ALE 점수 계산 실패: {e}")
            return {
                'success': False,
                'message': f'다중 디바이스 ALE 점수 계산 실패: {str(e)}',
                'total_devices': 0,
                'ale_scores': [],
                'failed_devices': device_ids if device_ids else []
            }
    
    def _calculate_accuracy_score(self, device_id: str, device_data: Dict[str, Any] = None) -> float:
        """
        정확도 점수 계산 (0-100).
        실측 정확도(device_data['accuracy_measured'], 0-100)가 있으면 그대로 사용하고,
        없으면 중립 기본값으로 폴백한다.
        ⚠️ 기존 해시 기반 임시값은 제거됨 — 실측 파이프라인이 채워지면 자동으로 실값 반영.
        """
        try:
            if device_data and device_data.get('accuracy_measured') is not None:
                return max(0.0, min(100.0, float(device_data['accuracy_measured'])))
            # 실측 정확도 없음 → 가짜 다양성 대신 명시적 중립 폴백
            return self.DEFAULT_NEUTRAL_SCORE
        except (TypeError, ValueError):
            return self.DEFAULT_NEUTRAL_SCORE

    def _calculate_latency_score(self, device_id: str, device_data: Dict[str, Any] = None) -> float:
        """
        지연시간 점수 계산 (0-100, 낮은 지연 = 높은 점수).
        실측 지연(device_data['latency_ms'])을 기준값(LATENCY_REFERENCE_MS)에 대비해 환산한다.
        offline 상태면 0, 실측값이 없으면 중립 기본값으로 폴백.
        """
        try:
            if device_data and device_data.get('status') == 'offline':
                return 0.0
            if device_data and device_data.get('latency_ms') is not None:
                latency_ms = float(device_data['latency_ms'])
                ref = self.LATENCY_REFERENCE_MS if self.LATENCY_REFERENCE_MS > 0 else 1.0
                score = 100.0 - (latency_ms / ref) * 100.0
                return max(0.0, min(100.0, score))
            return self.DEFAULT_NEUTRAL_SCORE
        except (TypeError, ValueError):
            return self.DEFAULT_NEUTRAL_SCORE

    def _calculate_energy_score(self, device_id: str, device_data: Dict[str, Any] = None) -> float:
        """
        에너지 점수 계산 (0-100, 높은 잔량/효율 = 높은 점수).
        배터리는 이미 실측되므로 battery_wh(완충 ENERGY_FULL_WH 대비)로 환산한다.
        battery_wh가 없으면 battery_level(%)을, 그것도 없으면 중립 기본값으로 폴백.
        """
        try:
            if device_data and device_data.get('battery_wh') is not None:
                wh = float(device_data['battery_wh'])
                full = self.ENERGY_FULL_WH if self.ENERGY_FULL_WH > 0 else 1.0
                return max(0.0, min(100.0, (wh / full) * 100.0))
            if device_data and device_data.get('battery_level') is not None:
                return max(0.0, min(100.0, float(device_data['battery_level'])))
            return self.DEFAULT_NEUTRAL_SCORE
        except (TypeError, ValueError):
            return self.DEFAULT_NEUTRAL_SCORE

    # ========================================================================================
    # 가중치 적용 최종 점수 계산 (외부에서 들어온 실측 A/L/E 값 → ALE 가중 점수)
    #  - Controller/Model 이 위임 호출하지만 기존에 구현이 누락되어 있던 메서드.
    #  - 해시 기반 임시 점수(_calculate_*_score)와 달리, 입력값으로만 정직하게 계산한다.
    # ========================================================================================
    def calculate_weighted_score(self, device_id: str, accuracy_value: float,
                                 latency_value: float, energy_value: float) -> Dict[str, Any]:
        """
        실측 A/L/E 값(각 0-1000)에 디바이스별 가중치를 적용해
        최종 가중 점수(0-100)와 등급을 계산한다.

        Args:
            device_id: 디바이스 ID
            accuracy_value: 정확도 측정값 (0-1000, 높을수록 좋음)
            latency_value: 지연시간 측정값 (0-1000, 낮을수록 좋음)
            energy_value: 에너지 측정값 (0-1000, 높을수록 좋음)

        Returns:
            {'success': bool, 'message': str, 'result': WeightedScoreResult|None}
        """
        try:
            # 1) 입력값 유효성 검사 (0-1000)
            v = self._validate_metric_values(accuracy_value, latency_value, energy_value)
            if not v['valid']:
                return {'success': False, 'message': v['message'], 'result': None}

            # 2) 0-1000 측정값 → 0-100 점수로 변환 (L은 낮을수록 높은 점수)
            scores = self._convert_metrics_to_scores(accuracy_value, latency_value, energy_value)

            # 3) 디바이스별 가중치 조회 (없으면 기본 가중치)
            weight_resp = self.get_weight(device_id)
            weights = weight_resp.get('weights') or self.ale_weights['default']
            aw = weights['accuracy_weight']
            lw = weights['latency_weight']
            ew = weights['energy_weight']

            # 4) 가중 합산 — 가중치 합이 1이 아니어도 정규화하여 0-100 범위 유지
            weight_sum = aw + lw + ew
            if weight_sum <= 0:
                weight_sum = 1.0
            weighted_score = (
                scores['accuracy'] * aw +
                scores['latency'] * lw +
                scores['energy'] * ew
            ) / weight_sum

            result = {
                'device_id': device_id,
                'weights_used': weights,
                'accuracy_score': round(scores['accuracy'], 2),
                'latency_score': round(scores['latency'], 2),
                'energy_score': round(scores['energy'], 2),
                'weighted_score': round(weighted_score, 2),
                'score_grade': self._score_to_grade(weighted_score),
                'calculation_timestamp': datetime.now().isoformat()
            }

            self.logger.info(
                f"가중 점수 계산: {device_id} -> {result['weighted_score']} ({result['score_grade']})"
            )
            return {
                'success': True,
                'message': f'{device_id} 가중 점수 계산 완료',
                'result': result
            }

        except Exception as e:
            self.logger.error(f"가중 점수 계산 실패 ({device_id}): {e}")
            return {
                'success': False,
                'message': f'가중 점수 계산 실패: {str(e)}',
                'result': None
            }

    def _score_to_grade(self, score: float) -> str:
        """0-100 가중 점수를 등급 문자열로 변환"""
        if score >= 95: return 'A+'
        if score >= 90: return 'A'
        if score >= 85: return 'B+'
        if score >= 80: return 'B'
        if score >= 75: return 'C+'
        if score >= 70: return 'C'
        if score >= 60: return 'D'
        return 'F'
