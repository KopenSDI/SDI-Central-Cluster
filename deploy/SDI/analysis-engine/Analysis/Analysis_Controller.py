from typing import Dict, Any, Optional
import json
import logging
from datetime import datetime
from SDI_Devcie.SDV_Device import SDV_Device
# from .Pod_Analyzer import PodAnalyzer, PodData  # 파일 없음 - 주석 처리
# from .Etcd_Analyzer import EtcdAnalyzer  # 파일 없음 - 주석 처리
from .ALE_Weight_Manager import ALEWeightManager

class AnalysisController:
    """
    분석 컨트롤러 - 사용자 요청을 처리하고 응답을 생성 etcd를 읽어야함
    """
    
    def __init__(self, analysis_model, etcd_host: str = "localhost", etcd_port: int = 2379):
        self.analysis_model = analysis_model
        
        # ALE Weight Manager 직접 초기화 (독립적인 인스턴스)
        self.ale_weight_manager = ALEWeightManager()

        self.etcd_analyzer = None
        self.etcd_enabled = False
        
   
    # ========================================================================================
    # MVC 리팩토링: InfluxDB 데이터 처리 로직을 Controller로 이동
    # ========================================================================================
    
    def update_devices_from_influx(self, influx_results) -> Dict[str, Any]:
        """
        InfluxDB 조회 결과를 기반으로 디바이스들을 생성/업데이트
        비즈니스 로직과 흐름 제어를 Controller에서 담당
        """
        updated_devices = []
        created_devices = []
        failed_devices = []
        
        try:
            for result in influx_results:
                bot_id = result.get('bot')
                wh_value = result.get('wh')
                
                if not bot_id:
                    logging.warning("bot_id가 없는 결과 건너뜀")
                    continue
                    
                # wh 값이 None인 경우 처리
                if wh_value is None:
                    logging.warning(f"{bot_id}: InfluxDB에서 데이터를 찾을 수 없음")
                    wh_value = 0.0
                
                try:
                    # 디바이스 존재 여부 확인
                    if self.analysis_model.device_exists(bot_id):
                        # 기존 디바이스 업데이트
                        success = self._update_existing_device(bot_id, wh_value)
                        if success:
                            updated_devices.append(bot_id)
                            logging.debug(f"{bot_id}: 기존 디바이스 업데이트 완료")
                        else:
                            failed_devices.append(bot_id)
                    else:
                        # 새 디바이스 생성
                        success = self._create_new_device(bot_id, wh_value)
                        if success:
                            created_devices.append(bot_id)
                            logging.info(f"{bot_id}: 새 디바이스 생성 완료")
                        else:
                            failed_devices.append(bot_id)
                            
                except Exception as e:
                    logging.error(f"{bot_id} 처리 실패: {e}")
                    failed_devices.append(bot_id)
            
            # 결과 반환
            total_processed = len(updated_devices) + len(created_devices)
            logging.info(f"디바이스 처리 완료 - 업데이트: {len(updated_devices)}, 생성: {len(created_devices)}, 실패: {len(failed_devices)}")
            
            return {
                'success': len(failed_devices) == 0,
                'message': f'총 {total_processed}개 디바이스 처리 완료',
                'updated_devices': updated_devices,
                'created_devices': created_devices,
                'failed_devices': failed_devices,
                'total_processed': total_processed
            }
            
        except Exception as e:
            logging.error(f"InfluxDB 데이터 처리 전체 실패: {e}")
            return {
                'success': False,
                'message': f'InfluxDB 데이터 처리 실패: {str(e)}',
                'updated_devices': [],
                'created_devices': [],
                'failed_devices': [],
                'total_processed': 0
            }
    
    def _create_new_device(self, bot_id: str, wh_value: float) -> bool:
        """
        새로운 디바이스 생성 및 초기 설정 - 자동으로 적절한 SD* 클래스 선택
        """
        try:
            # 디바이스 ID 패턴을 보고 자동으로 적절한 SD* 클래스와 설정 결정
            device_class_info = self._determine_device_class_info(bot_id)
            location = self._get_location_for_bot(bot_id)
            
            # Model에 SD* 클래스별 디바이스 생성 요청
            device = self.analysis_model.create_sdi_device(
                device_id=bot_id,
                device_class_info=device_class_info,
                location=location
            )
            if not device:
                return False
            
            # 클래스별 초기 데이터 설정
            return self.analysis_model.update_device_data_by_class(bot_id, wh_value, device_class_info['class_type'])
            
        except Exception as e:
            logging.error(f"새 디바이스 생성 실패 ({bot_id}): {e}")
            return False
    
    def _update_existing_device(self, bot_id: str, wh_value: float) -> bool:
        """
        기존 디바이스 업데이트 - 클래스 타입에 맞게 업데이트
        """
        try:
            # 기존 디바이스의 클래스 타입 확인
            device = self.analysis_model.get_device(bot_id)
            if not device:
                return False
                
            device_class_type = self._get_device_class_type(device)
            return self.analysis_model.update_device_data_by_class(bot_id, wh_value, device_class_type)
            
        except Exception as e:
            logging.error(f"디바이스 업데이트 실패 ({bot_id}): {e}")
            return False
    
    def _determine_device_class_info(self, device_id: str) -> Dict[str, Any]:
        """
        디바이스 ID 패턴을 분석하여 적절한 SD* 클래스 정보를 결정
        자동으로 SDV, SDA, 등등 중에서 선택
        
        Args:
            device_id: 디바이스 ID (예: "TURTLEBOT3-Burger-1", "DRONE-DJI-01")
            
        Returns:
            Dict: 클래스 정보
            {
                'class_type': 'SDV' | 'SDA' | 'SDI',
                'device_type': 'vehicle' | 'air' | 'appliance',  
                'model': '구체적인 모델명',
                'sub_type': '세부 타입'
            }
        """
        device_id_upper = device_id.upper()
        
        # 패턴 매칭으로 자동 클래스 결정
        if any(keyword in device_id_upper for keyword in ['TURTLEBOT', 'ROBOT_CAR', 'AGV', 'VEHICLE']):
            # SDV (Smart Device Vehicle) - 지상 이동체
            return {
                'class_type': 'SDV',
                'device_type': 'vehicle',
                'model': self._determine_vehicle_model(device_id),
                'sub_type': self._determine_vehicle_sub_type(device_id)
            }
            
        elif any(keyword in device_id_upper for keyword in ['DRONE', 'UAV', 'QUADCOPTER', 'AIRCRAFT']):
            # SDA (Smart Device Air) - 공중 이동체  
            return {
                'class_type': 'SDA', 
                'device_type': 'air',
                'model': self._determine_air_model(device_id),
                'sub_type': self._determine_air_sub_type(device_id)
            }
            
        # 향후 확장 가능한 다른 SD* 클래스들
        # elif any(keyword in device_id_upper for keyword in ['ROBOT_ARM', 'MANIPULATOR']):
        #     return {'class_type': 'SDM', 'device_type': 'manipulator', ...}
        # elif any(keyword in device_id_upper for keyword in ['SENSOR', 'CAMERA']):  
        #     return {'class_type': 'SDS', 'device_type': 'sensor', ...}
        
        else:
            # 기본값: 일반 SDI 디바이스
            logging.warning(f"알 수 없는 디바이스 패턴 ({device_id}), 기본 SDI 사용")
            return {
                'class_type': 'SDI',
                'device_type': 'generic',
                'model': 'Unknown-Device',
                'sub_type': 'generic'
            }
    
    def _determine_vehicle_model(self, device_id: str) -> str:
        """SDV용 차량 모델 결정"""
        if "Burger" in device_id:
            return "TURTLEBOT3-Burger"
        elif "Waffle" in device_id:
            return "TURTLEBOT3-Waffle" 
        elif "TURTLEBOT" in device_id.upper():
            return "TURTLEBOT3-Burger"  # 기본값
        else:
            return "Generic-Vehicle"
    
    def _determine_vehicle_sub_type(self, device_id: str) -> str:
        """SDV용 차량 서브타입 결정"""
        if "TURTLEBOT" in device_id.upper():
            return "turtlebot"
        elif "AGV" in device_id.upper():
            return "agv"
        else:
            return "vehicle"
            
    def _determine_air_model(self, device_id: str) -> str:
        """SDA용 항공기 모델 결정"""
        if "DJI" in device_id.upper():
            return "DJI-Mini-4-Pro"
        elif "PARROT" in device_id.upper():
            return "Parrot-AR-Drone"
        else:
            return "Generic-Drone"
    
    def _determine_air_sub_type(self, device_id: str) -> str:
        """SDA용 항공기 서브타입 결정"""
        if "DRONE" in device_id.upper():
            return "drone"
        elif "UAV" in device_id.upper():
            return "uav"
        else:
            return "aircraft"
    
    def _get_device_class_type(self, device) -> str:
        """기존 디바이스 객체에서 클래스 타입 추출"""
        class_name = type(device).__name__
        if class_name == "SDV_Device":
            return "SDV"
        elif class_name == "SDA_Device":
            return "SDA"
        elif class_name == "BasicDevice":
            return "SDI"
        else:
            return "SDI"  # 기본값
    
    def _get_location_for_bot(self, bot_id: str) -> str:
        """디바이스 ID를 기반으로 위치 정보를 결정"""
        # TODO: 실제로는 별도 설정이나 데이터베이스에서 가져와야 함
        location_map = {
            "TURTLEBOT3-Burger-1": "Lab-A",
            "TURTLEBOT3-Burger-2": "Lab-B", 
            "TURTLEBOT3-Waffle-1": "Office",
        }
        return location_map.get(bot_id, "Unknown")
    
    # ========================================================================================
    # 새로운 분석 서비스들 - MALE Mission, Accuracy, Latency, 종합 점수
    # ========================================================================================
    
    def analyze_male_mission(self, device_id: str, mission_type: str, time_range: str = "-24h") -> Dict[str, Any]:
        """
        MALE Mission 분석 - 미션 효과성, 성공률, 수행시간 등 분석
        """
        try:
            # Model에서 미션 데이터 분석
            mission_analysis = self.analysis_model.analyze_male_mission_data(device_id, mission_type, time_range)
            
            if mission_analysis:
                return {
                    'success': True,
                    'message': f'{device_id} MALE Mission 분석 완료',
                    'device_id': device_id,
                    'mission_type': mission_type,
                    'mission_success_rate': mission_analysis.get('success_rate', 0.0),
                    'mission_effectiveness': mission_analysis.get('effectiveness', 0.0),
                    'average_mission_duration': mission_analysis.get('avg_duration', 0.0),
                    'mission_records': mission_analysis.get('records', [])
                }
            else:
                return {
                    'success': False,
                    'message': f'{device_id} MALE Mission 데이터를 찾을 수 없습니다'
                }
                
        except Exception as e:
            logging.error(f"MALE Mission 분석 실패 ({device_id}): {e}")
            return {
                'success': False,
                'message': f'MALE Mission 분석 실패: {str(e)}'
            }
    
    def analyze_accuracy(self, device_id: str, accuracy_type: str, time_range: str = "-24h") -> Dict[str, Any]:
        """
        Accuracy 분석 - 위치 정확도, 목표 도달 정확도 등 분석
        """
        try:
            # Model에서 정확도 데이터 분석
            accuracy_analysis = self.analysis_model.analyze_accuracy_data(device_id, accuracy_type, time_range)
            
            if accuracy_analysis:
                return {
                    'success': True,
                    'message': f'{device_id} Accuracy 분석 완료',
                    'device_id': device_id,
                    'accuracy_type': accuracy_type,
                    'accuracy_percentage': accuracy_analysis.get('accuracy_pct', 0.0),
                    'average_error_distance': accuracy_analysis.get('avg_error', 0.0),
                    'max_error_distance': accuracy_analysis.get('max_error', 0.0),
                    'accuracy_records': accuracy_analysis.get('records', [])
                }
            else:
                return {
                    'success': False,
                    'message': f'{device_id} Accuracy 데이터를 찾을 수 없습니다'
                }
                
        except Exception as e:
            logging.error(f"Accuracy 분석 실패 ({device_id}): {e}")
            return {
                'success': False,
                'message': f'Accuracy 분석 실패: {str(e)}'
            }
    
    def analyze_latency(self, device_id: str, latency_type: str, time_range: str = "-24h") -> Dict[str, Any]:
        """
        Latency 분석 - 명령 응답시간, 네트워크 지연 등 분석
        """
        try:
            # Model에서 지연시간 데이터 분석
            latency_analysis = self.analysis_model.analyze_latency_data(device_id, latency_type, time_range)
            
            if latency_analysis:
                return {
                    'success': True,
                    'message': f'{device_id} Latency 분석 완료',
                    'device_id': device_id,
                    'latency_type': latency_type,
                    'average_latency_ms': latency_analysis.get('avg_latency', 0.0),
                    'max_latency_ms': latency_analysis.get('max_latency', 0.0),
                    'min_latency_ms': latency_analysis.get('min_latency', 0.0),
                    'latency_records': latency_analysis.get('records', [])
                }
            else:
                return {
                    'success': False,
                    'message': f'{device_id} Latency 데이터를 찾을 수 없습니다'
                }
                
        except Exception as e:
            logging.error(f"Latency 분석 실패 ({device_id}): {e}")
            return {
                'success': False,
                'message': f'Latency 분석 실패: {str(e)}'
            }
    
    def get_device_score(self, device_id: str, time_range: str = "-24h") -> Dict[str, Any]:
        """
        디바이스 종합 점수 계산 - A+, A, B+ 등급과 함께 상세 점수 제공
        """
        try:
            # Model에서 종합 점수 계산
            device_score = self.analysis_model.calculate_device_score(device_id, time_range)
            
            if device_score:
                return {
                    'success': True,
                    'message': f'{device_id} 종합 점수 계산 완료',
                    'device_id': device_id,
                    'overall_score': device_score.get('overall_score', 0.0),
                    'performance_score': device_score.get('performance_score', 0.0),
                    'mission_score': device_score.get('mission_score', 0.0),
                    'accuracy_score': device_score.get('accuracy_score', 0.0),
                    'latency_score': device_score.get('latency_score', 0.0),
                    'reliability_score': device_score.get('reliability_score', 0.0),
                    'grade': device_score.get('grade', 'F'),
                    'score_details': device_score.get('details', [])
                }
            else:
                return {
                    'success': False,
                    'message': f'{device_id} 점수 계산 데이터가 부족합니다'
                }
                
        except Exception as e:
            logging.error(f"디바이스 점수 계산 실패 ({device_id}): {e}")
            return {
                'success': False,
                'message': f'디바이스 점수 계산 실패: {str(e)}'
            }
    
    # grpc로 create device를 만들었으나, 현재구조상에서는 grpc로 쓰일일은 없음. inflex db에서 읽는데로 생성하는구조로 변경
    def create_device(self, device_id: str, model: str = "", location: str = "") -> Dict[str, Any]:
        """SDI 디바이스 생성 및 등록 - 자동 클래스 선택 시스템 (터틀봇, 드론 등 모든 타입 지원)"""
        """device ID는 SDV, SDR,SDA """
        try:
            # 자동으로 적절한 SD* 클래스 결정 (SDV, SDA, SDI 등)
            device_class_info = self._determine_device_class_info(device_id)
            device = self.analysis_model.create_sdi_device(device_id, device_class_info, location)
            
            if device:
                return {
                    'success': True,
                    'message': f'{device_class_info["class_type"]} 디바이스 {device_id} 생성 완료',
                    'device_id': device_id,
                    'device_type': device_class_info['device_type'],
                    'device_class': device_class_info['class_type'],
                    'model': device_class_info['model'],
                    'location': location,
                    'status': 'offline'
                }
            else:
                return {
                    'success': False,
                    'message': 'SDI 디바이스 등록 실패'
                }
        except Exception as e:
            logging.error(f"SDI 디바이스 생성 실패: {e}")
            return {
                'success': False,
                'message': f'SDI 디바이스 생성 실패: {str(e)}'
            }
    
    def create_turtlebot(self, device_id: str, model: str, location: str = "") -> Dict[str, Any]:
        """터틀봇 생성 (하위 호환성) - 내부적으로 create_device 호출"""
        return self.create_device(device_id, model, location)
    
    def get_device_status(self, device_id: str) -> Dict[str, Any]:
        """SDI 디바이스 상태 조회 - 모든 디바이스 타입 지원 (SDV, SDA, SDI)"""
        try:
            device = self.analysis_model.get_device(device_id)
            if device:
                # SDI 공통 속성과 클래스별 배터리 속성을 범용적으로 처리
                battery_level = self._get_device_battery_level(device)
                battery_wh = self._get_device_battery_wh(device)
                device_class = type(device).__name__
                
                return {
                    'success': True,
                    'message': 'SDI 디바이스 상태 조회 완료',
                    'device_id': device_id,
                    'device_class': device_class,
                    'device_type': getattr(device, 'device_type', 'unknown'),
                    'status': device.status,
                    'battery_level': battery_level,
                    'battery_wh': battery_wh,
                    'location': device.location,
                    'model': getattr(device, 'model', 'unknown'),
                    'last_updated': device.last_updated.isoformat() if device.last_updated else datetime.now().isoformat()
                }
            else:
                return {
                    'success': False,
                    'message': f'SDI 디바이스 {device_id}를 찾을 수 없습니다'
                }
        except Exception as e:
            logging.error(f"SDI 디바이스 상태 조회 실패: {e}")
            return {
                'success': False,
                'message': f'SDI 디바이스 상태 조회 실패: {str(e)}'
            }
    
    def analyze_device_performance(self, device_id: str) -> Dict[str, Any]:
        """기본 디바이스 성능 분석"""
        try:
            analysis_result = self.analysis_model.analyze_device_performance(device_id)
            if analysis_result:
                return {
                    'success': True,
                    'message': '디바이스 성능 분석 완료',
                    'device_id': device_id,
                    'performance_score': analysis_result.get('performance_score', 0.0),
                    'efficiency_rating': analysis_result.get('efficiency_rating', 0.0),
                    'battery_health': analysis_result.get('battery_health', 0.0),
                    'summary': analysis_result.get('summary', ''),
                    'metrics': analysis_result.get('metrics', [])
                }
            else:
                return {
                    'success': False,
                    'message': f'디바이스 {device_id} 분석 실패'
                }
        except Exception as e:
            logging.error(f"디바이스 성능 분석 실패: {e}")
            return {
                'success': False,
                'message': f'디바이스 성능 분석 실패: {str(e)}'
            }
    
    def get_fleet_analysis(self) -> Dict[str, Any]:
        """플릿 전체 분석"""
        try:
            fleet_result = self.analysis_model.get_fleet_analysis()
            if fleet_result:
                return {
                    'success': True,
                    'message': '플릿 분석 완료',
                    'total_devices': fleet_result.get('total_devices', 0),
                    'active_devices': fleet_result.get('active_devices', 0),
                    'average_performance': fleet_result.get('average_performance', 0.0),
                    'average_battery_health': fleet_result.get('average_battery_health', 0.0),
                    'device_analyses': fleet_result.get('device_analyses', [])
                }
            else:
                return {
                    'success': False,
                    'message': '플릿 분석 실패'
                }
        except Exception as e:
            logging.error(f"플릿 분석 실패: {e}")
            return {
                'success': False,
                'message': f'플릿 분석 실패: {str(e)}'
            }
    
    def get_all_devices(self) -> Dict[str, Any]:
        """모든 디바이스 목록 조회"""
        try:
            devices_data = self.analysis_model.get_all_devices()
            return {
                'success': True,
                'message': '디바이스 목록 조회 완료',
                'devices': devices_data.get('devices', [])
            }
        except Exception as e:
            logging.error(f"디바이스 목록 조회 실패: {e}")
            return {
                'success': False,
                'message': f'디바이스 목록 조회 실패: {str(e)}',
                'devices': []
            }
    
    def get_device_battery_status(self, device_id: str) -> Dict[str, Any]:
        """SDI 디바이스 배터리 상태 분석 - 모든 디바이스 타입 지원 (SDV, SDA, SDI)"""
        try:
            device = self.analysis_model.get_device(device_id)
            if device:
                # SDI 상속구조를 활용한 범용 배터리 정보 추출
                battery_level = self._get_device_battery_level(device)
                battery_wh = self._get_device_battery_wh(device)
                device_class = type(device).__name__
                
                # 배터리 건강 상태 분석 (클래스별 기준 다를 수 있음)
                health_status = self._analyze_battery_health(device, battery_level)
                
                # 예상 런타임 분석 (디바이스 타입별 소비 패턴 고려)
                estimated_runtime = self._calculate_estimated_runtime(device, battery_wh)
                
                return {
                    'success': True,
                    'message': 'SDI 디바이스 배터리 분석 완료',
                    'device_id': device_id,
                    'device_class': device_class,
                    'battery_level': battery_level,
                    'battery_wh': battery_wh,
                    'estimated_runtime': estimated_runtime,
                    'health_status': health_status,
                    'last_updated': device.last_updated.isoformat() if device.last_updated else datetime.now().isoformat()
                }
            else:
                return {
                    'success': False,
                    'message': f'SDI 디바이스 {device_id}를 찾을 수 없습니다'
                }
        except Exception as e:
            logging.error(f"SDI 디바이스 배터리 분석 실패: {e}")
            return {
                'success': False,
                'message': f'SDI 디바이스 배터리 분석 실패: {str(e)}'
            }
    
    def get_turtlebot_battery_status(self, device_id: str) -> Dict[str, Any]:
        """터틀봇 배터리 상태 (하위 호환성) - 내부적으로 get_device_battery_status 호출"""
        return self.get_device_battery_status(device_id)
    def _get_device_battery_level(self, device) -> float:
        """SDI 디바이스에서 배터리 레벨을 범용적으로 추출"""
        # SDV (차량): fuel_level 사용
        if hasattr(device, 'fuel_level'):
            return getattr(device, 'fuel_level', 0.0)
        # SDA (항공): battery_level 사용  
        elif hasattr(device, 'battery_level'):
            return getattr(device, 'battery_level', 0.0)
        # SDI (기본): 기본값
        else:
            return 0.0
    
    def _get_device_battery_wh(self, device) -> float:
        """SDI 디바이스에서 배터리 Wh를 범용적으로 추출"""
        return getattr(device, 'battery_wh', 0.0)
    
    def _analyze_battery_health(self, device, battery_level: float) -> str:
        """디바이스 클래스별 배터리 건강 상태 분석"""
        device_class = type(device).__name__
        # 일단 기준을 하드코딩으로 함 정책적이나 의미적으로 분류가 되야함-기철 
        if device_class == "SDV_Device":
            # 차량형 디바이스 배터리 기준
            if battery_level > 60:
                return "OK"
            elif battery_level > 30:
                return "GOOD"
            elif battery_level > 15:
                return "CAUTION"
            else:
                return "위험"
        elif device_class == "SDA_Device":
            # 항공형 디바이스 배터리 기준 (더 엄격)
            if battery_level > 70:
                return "OK"
            elif battery_level > 40:
                return "GOOD"
            elif battery_level > 20:
                return "CAUTION"
            else:
                return "DANGER"
        else:
            # 기본 SDI 디바이스 기준
            if battery_level > 50:
                return "OK"
            elif battery_level > 20:
                return "GOOD"
            else:
                return "CAUTION"
    
    def _calculate_estimated_runtime(self, device, battery_wh: float) -> float:
        """디바이스 클래스별 예상 런타임 계산"""
        if battery_wh <= 0:
            return 0.0
            
        device_class = type(device).__name__
        
        # 일단은 단순계산으로 하드코딩됨 수정해야함 연료가 전기라고 만 한정하지않기위해서 ..-기철
        if device_class == "SDV_Device":
            consumption_rate = 45.0  
        elif device_class == "SDA_Device":
            consumption_rate = 80.0  
        else:
            consumption_rate = 50.0  
            
        return battery_wh / consumption_rate  



    # MALE Weight 관리 함수들 ////////////
    def get_ale_weight(self, device_id: str = "") -> Dict[str, Any]:
        """
        단일 디바이스 ALE 가중치 조회 (ALEWeightManager 사용)
        
        Args:
            device_id: 디바이스 ID (빈 문자열이면 기본 가중치 반환)
            
        Returns:
            ALE 가중치 조회 결과
        """
        try:
            result = self.ale_weight_manager.get_weight(device_id)
            
            if result.get('success', False):
                logging.info(f"ALE 가중치 조회 성공: {device_id or 'default'}")
                return result
            else:
                logging.warning(f"ALE 가중치 조회 실패: {result.get('message', '')}")
                return result
                
        except Exception as e:
            error_msg = f"ALE 가중치 조회 중 오류: {str(e)}"
            logging.error(error_msg)
            return {
                'success': False,
                'message': error_msg,
                'weights': None
            }
    
    def get_all_ale_weights(self) -> Dict[str, Any]:
        """
        모든 디바이스의 ALE 가중치 조회 (ALEWeightManager 사용)
        
        Returns:
            모든 디바이스의 ALE 가중치 조회 결과 (etcd 스타일)
        """
        try:
            result = self.ale_weight_manager.get_all_weights()
            
            if result.get('success', False):
                logging.info(f"모든 ALE 가중치 조회 성공: {result.get('total_devices', 0)}개 디바이스")
                return result
            else:
                logging.warning(f"모든 ALE 가중치 조회 실패: {result.get('message', '')}")
                return result
                
        except Exception as e:
            error_msg = f"모든 ALE 가중치 조회 중 오류: {str(e)}"
            logging.error(error_msg)
            return {
                'success': False,
                'message': error_msg,
                'total_devices': 0,
                'weights': []
            }
    
    def get_ale_weights_for_devices(self, device_ids: list) -> Dict[str, Any]:
        """
        특정 디바이스 목록의 ALE 가중치 조회
        
        Args:
            device_ids: 조회할 디바이스 ID 목록
            
        Returns:
            지정된 디바이스들의 ALE 가중치 조회 결과
        """
        try:
            # 현재 등록된 디바이스 목록이 있다면 사용, 없다면 요청된 목록 사용
            if not device_ids:
                # 등록된 디바이스 목록 가져오기
                device_ids = list(self.analysis_model.devices.keys())
                logging.info(f"등록된 디바이스 목록 사용: {len(device_ids)}개")
            
            result = self.ale_weight_manager.get_weights_by_device_list(device_ids)
            
            if result.get('success', False):
                logging.info(f"디바이스 목록 ALE 가중치 조회 성공: {result.get('total_devices', 0)}개")
                return result
            else:
                logging.warning(f"디바이스 목록 ALE 가중치 조회 실패: {result.get('message', '')}")
                return result
                
        except Exception as e:
            error_msg = f"디바이스 목록 ALE 가중치 조회 중 오류: {str(e)}"
            logging.error(error_msg)
            return {
                'success': False,
                'message': error_msg,
                'total_devices': 0,
                'weights': [],
                'default_applied': []
            }
    
    def set_ale_weight(self, device_id: str, accuracy_weight: float, latency_weight: float, 
                       energy_weight: float, description: str = "") -> Dict[str, Any]:
        """
        디바이스별 ALE 가중치 설정 (ALEWeightManager 사용)
        
        Args:
            device_id: 디바이스 ID
            accuracy_weight: 정확도 가중치 (0-1)
            latency_weight: 지연시간 가중치 (0-1)
            energy_weight: 에너지 가중치 (0-1)
            description: 가중치 설명
            
        Returns:
            ALE 가중치 설정 결과
        """
        try:
            result = self.ale_weight_manager.set_weight(
                device_id, accuracy_weight, latency_weight, energy_weight, description
            )
            
            if result.get('success', False):
                logging.info(f"ALE 가중치 설정 성공: {device_id}")
                return result
            else:
                logging.warning(f"ALE 가중치 설정 실패: {result.get('message', '')}")
                return result
                
        except Exception as e:
            error_msg = f"ALE 가중치 설정 중 오류: {str(e)}"
            logging.error(error_msg)
            return {
                'success': False,
                'message': error_msg,
                'weights': None
            }
    
    def calculate_weighted_score(self, device_id: str, accuracy_value: float, latency_value: float, 
                               energy_value: float, time_range: str = "-24h") -> Dict[str, Any]:
        """
        ALE 가중치를 적용한 종합 점수 계산 (ALEWeightManager 사용)
        
        Args:
            device_id: 디바이스 ID
            accuracy_value: 정확도 값 (0-1000)
            latency_value: 지연시간 값 (0-1000)
            energy_value: 에너지 값 (0-1000)
            time_range: 분석 시간 범위 (현재 사용되지 않음)
            
        Returns:
            가중치 적용된 점수 계산 결과
        """
        try:
            result = self.ale_weight_manager.calculate_weighted_score(
                device_id, accuracy_value, latency_value, energy_value
            )
            
            if result.get('success', False):
                logging.info(f"가중치 점수 계산 성공: {device_id} -> {result['result']['weighted_score']}")
                return result
            else:
                logging.warning(f"가중치 점수 계산 실패: {result.get('message', '')}")
                return result
                
        except Exception as e:
            error_msg = f"가중치 점수 계산 중 오류: {str(e)}"
            logging.error(error_msg)
            return {
                'success': False,
                'message': error_msg,
                'result': None
            }
    
    
    def get_ale_scores_for_device(self, device_id: str) -> Dict[str, Any]:
        """
        단일 디바이스의 ALE 점수 조회
        
        Args:
            device_id: 디바이스 ID
            
        Returns:
            디바이스의 ALE 점수 (Accuracy, Latency, Energy)
        """
        try:
            # 디바이스 정보 가져오기
            device = self.analysis_model.get_device(device_id)
            device_data = None
            
            if device:
                # 디바이스 상태 데이터 추출
                device_data = {
                    'battery_level': getattr(device, 'fuel_level', 75.0),
                    'battery_wh': getattr(device, 'battery_wh', 400.0),
                    'status': getattr(device, 'status', 'online'),
                    'device_type': getattr(device, 'device_type', 'turtlebot'),
                    # 실측 A/L 메트릭: 모델에 채워지면 자동 반영, 없으면 None → Manager가 fallback
                    'accuracy_measured': getattr(device, 'accuracy_measured', None),
                    'latency_ms': getattr(device, 'latency_ms', None),
                }

            # ALE 점수 계산
            result = self.ale_weight_manager.calculate_ale_scores_for_device(device_id, device_data)
            
            if result.get('success', False):
                logging.info(f"ALE 점수 조회 성공: {device_id}")
                return result
            else:
                logging.warning(f"ALE 점수 조회 실패: {result.get('message', '')}")
                return result
                
        except Exception as e:
            error_msg = f"ALE 점수 조회 중 오류: {str(e)}"
            logging.error(error_msg)
            return {
                'success': False,
                'message': error_msg,
                'ale_scores': None
            }
    
    def get_ale_scores_for_devices(self, device_ids: list = None) -> Dict[str, Any]:
        """
        다중 디바이스의 ALE 점수 조회
        
        Args:
            device_ids: 디바이스 ID 목록 (None이면 등록된 모든 디바이스)
            
        Returns:
            다중 디바이스의 ALE 점수 목록
        """
        try:
            # 디바이스 목록 결정
            if device_ids is None or len(device_ids) == 0:
                device_ids = list(self.analysis_model.devices.keys())
                logging.info(f"등록된 모든 디바이스 ALE 점수 조회: {len(device_ids)}개")
            
            if not device_ids:
                return {
                    'success': True,
                    'message': '조회할 디바이스가 없습니다',
                    'total_devices': 0,
                    'ale_scores': [],
                    'failed_devices': []
                }
            
            # 디바이스들의 상태 데이터 수집
            devices_data = {}
            for device_id in device_ids:
                device = self.analysis_model.get_device(device_id)
                if device:
                    devices_data[device_id] = {
                        'battery_level': getattr(device, 'fuel_level', 75.0),
                        'battery_wh': getattr(device, 'battery_wh', 400.0),
                        'status': getattr(device, 'status', 'online'),
                        'device_type': getattr(device, 'device_type', 'turtlebot'),
                        # 실측 A/L 메트릭: 모델에 채워지면 자동 반영, 없으면 None → Manager가 fallback
                        'accuracy_measured': getattr(device, 'accuracy_measured', None),
                        'latency_ms': getattr(device, 'latency_ms', None),
                    }
            
            # 다중 ALE 점수 계산
            result = self.ale_weight_manager.calculate_ale_scores_for_devices(device_ids, devices_data)
            
            if result.get('success', False):
                logging.info(f"다중 디바이스 ALE 점수 조회 성공: {len(result.get('ale_scores', []))}개")
                return result
            else:
                logging.warning(f"다중 디바이스 ALE 점수 조회 실패: {result.get('message', '')}")
                return result
                
        except Exception as e:
            error_msg = f"다중 디바이스 ALE 점수 조회 중 오류: {str(e)}"
            logging.error(error_msg)
            return {
                'success': False,
                'message': error_msg,
                'total_devices': len(device_ids) if device_ids else 0,
                'ale_scores': [],
                'failed_devices': device_ids if device_ids else []
            }
    