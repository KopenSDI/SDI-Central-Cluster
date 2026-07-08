import os
import logging
from typing import Optional, List, Dict, Any
from influxdb_client import InfluxDBClient
from datetime import datetime, timedelta

# InfluxDB 설정
INFLUX_URL = "http://10.0.5.52:32086"
INFLUX_TOKEN = "6hZxFzOacf-6TlnlhDUWjLnp1EtefcY9ViBziEfEPeklZYgijfdQrslUenifowQZ7cMQmuHk74iToaGK6mEG-A=="
INFLUX_ORG = "keti"
INFLUX_BUCKET = "turtlebot"

#Edit 필요- 터틀봇 초기 정보를 읽어드림  수정해야할것 -> 초기 인플럭스 디비에서 읽어 들이게해야함 
BOTS = ["TURTLEBOT3-Burger-1", "TURTLEBOT3-Burger-2"]

class InfluxService:
    def __init__(self):
        self.org = INFLUX_ORG
        self.bucket = INFLUX_BUCKET
        self.client = InfluxDBClient(
            url=INFLUX_URL, 
            token=INFLUX_TOKEN, 
            org=INFLUX_ORG, 
            timeout=10000
        )
        self.query_api = self.client.query_api()
        logging.info("InfluxDB 서비스 초기화 완료")

    def close(self):
        """데이터베이스 연결 종료"""
        try:
            self.client.close()
        except Exception as e:
            logging.error(f"데이터베이스 연결 종료 실패: {e}")

    def get_latest_battery_status(self, bot: str, lookback: str = "-30m") -> Optional[float]:
        """특정 터틀봇의 최신 배터리 상태 조회"""
        flux = f"""
        from(bucket: "{self.bucket}") 
            |> range(start: {lookback})
            |> filter(fn: (r) => r._measurement == "battery" and r.bot == "{bot}" and r._field == "wh")
            |> last()
        """
        
        try:
            tables = self.query_api.query(org=self.org, query=flux)
            for table in tables:
                for rec in table.records:
                    try:
                        return float(rec.get_value())
                    except (TypeError, ValueError):
                        return None
        except Exception as e:
            logging.error(f"InfluxDB 쿼리 실패 (bot={bot}): {e}")
            return None
        
        return None

    def get_battery_history(self, bot: str, hours: int = 24) -> List[Dict[str, Any]]:
        """특정 터틀봇의 배터리 히스토리 조회"""
        lookback = f"-{hours}h"
        flux = f"""
        from(bucket: "{self.bucket}") 
            |> range(start: {lookback})
            |> filter(fn: (r) => r._measurement == "battery" and r.bot == "{bot}" and r._field == "wh")
            |> sort(columns: ["_time"])
        """
        
        try:
            tables = self.query_api.query(org=self.org, query=flux)
            history = []
            for table in tables:
                for rec in table.records:
                    history.append({
                        'timestamp': rec.get_time().isoformat(),
                        'wh': float(rec.get_value()),
                        'bot': bot
                    })
            return history
        except Exception as e:
            logging.error(f"배터리 히스토리 조회 실패 (bot={bot}): {e}")
            return []

    def get_all_bots_battery_status(self, lookback: str = "-30m") -> List[Dict[str, Any]]:
        """모든 터틀봇의 배터리 상태 조회"""
        results = []
        for bot in BOTS:
            wh = self.get_latest_battery_status(bot, lookback)
            results.append({
                'bot': bot,
                'wh': wh,
                'status': self._get_battery_status_level(wh) if wh else 'unknown'
            })
        return results

    def _get_battery_status_level(self, wh: float) -> str:
        """배터리 잔량에 따른 상태 레벨 반환"""
        if wh is None:
            return 'unknown'
        elif wh > 400:
            return 'high'
        elif wh > 300:
            return 'medium'
        elif wh > 200:
            return 'low'
        else:
            return 'critical'

    # ------------------------------------------------------------------
    # 실측 A/L/E 메트릭 조회 (데이터 준비 계층)
    #  - 아래 measurement/field 스키마로 프로듀서가 InfluxDB에 적재하면
    #    ALE 점수가 실측 기반으로 자동 전환된다.
    #  - 아직 데이터가 없으면 None 을 반환 → 상위(Manager)에서 fallback 처리.
    #    · accuracy : measurement="accuracy", field="value" (0-100)
    #    · latency  : measurement="latency",  field="ms"    (밀리초)
    #    · energy   : 기존 battery(wh) 재사용
    # ------------------------------------------------------------------
    def get_latest_metric(self, bot: str, measurement: str, field: str,
                          lookback: str = "-30m") -> Optional[float]:
        """임의 measurement/field 의 최신 실측값 조회 (없으면 None)"""
        flux = f"""
        from(bucket: "{self.bucket}")
            |> range(start: {lookback})
            |> filter(fn: (r) => r._measurement == "{measurement}" and r.bot == "{bot}" and r._field == "{field}")
            |> last()
        """
        try:
            tables = self.query_api.query(org=self.org, query=flux)
            for table in tables:
                for rec in table.records:
                    try:
                        return float(rec.get_value())
                    except (TypeError, ValueError):
                        return None
        except Exception as e:
            logging.error(f"InfluxDB 메트릭 조회 실패 (bot={bot}, {measurement}.{field}): {e}")
            return None
        return None

    def get_latest_accuracy(self, bot: str, lookback: str = "-30m") -> Optional[float]:
        """최신 실측 정확도(0-100) 조회"""
        return self.get_latest_metric(bot, "accuracy", "value", lookback)

    def get_latest_latency(self, bot: str, lookback: str = "-30m") -> Optional[float]:
        """최신 실측 지연시간(ms) 조회"""
        return self.get_latest_metric(bot, "latency", "ms", lookback)

    def get_device_metrics(self, bot: str, lookback: str = "-30m") -> Dict[str, Any]:
        """
        디바이스의 실측 A/L/E 메트릭을 한 번에 모아 반환한다.
        (Controller/Engine 이 device_data 로 그대로 넘길 수 있는 형태)
        측정값이 없는 항목은 None 이며, 상위에서 fallback 된다.
        """
        return {
            "accuracy_measured": self.get_latest_accuracy(bot, lookback),
            "latency_ms": self.get_latest_latency(bot, lookback),
            "battery_wh": self.get_latest_battery_status(bot, lookback),
        }

    def get_available_bots(self) -> List[str]:
        """사용 가능한 터틀봇 목록 반환"""
        return BOTS 