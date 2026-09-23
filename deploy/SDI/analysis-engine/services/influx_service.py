import os
import logging
from typing import Optional, List, Dict, Any
from influxdb_client import InfluxDBClient
from datetime import datetime, timedelta

# InfluxDB 설정
INFLUX_URL = os.getenv("INFLUX_URL", "http://10.0.5.52:32086")
INFLUX_TOKEN = os.getenv("INFLUX_TOKEN")
INFLUX_ORG = os.getenv("INFLUX_ORG", "keti")
INFLUX_BUCKET = os.getenv("INFLUX_BUCKET", "turtlebot")

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

    def get_available_bots(self) -> List[str]:
        """사용 가능한 터틀봇 목록 반환"""
        return BOTS 