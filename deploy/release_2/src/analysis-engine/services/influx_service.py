import os
import logging
from typing import Optional, List, Dict, Any
from influxdb_client import InfluxDBClient
from datetime import datetime, timedelta

# influx_reader.py와 설정 공유 (환경변수 기반)
from influx_reader import (
    INFLUX_URL,
    INFLUX_TOKEN,
    INFLUX_ORG,
    INFLUX_BUCKET,
    DEFAULT_BOTS,
    get_available_bots
)

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

    def discover_bots(self, lookback: str = "-24h") -> List[str]:
        """InfluxDB에서 사용 가능한 모든 BOT 목록을 동적으로 조회"""
        flux = f"""
        from(bucket: "{self.bucket}")
            |> range(start: {lookback})
            |> filter(fn: (r) => r._measurement == "battery")
            |> keep(columns: ["bot"])
            |> distinct(column: "bot")
        """

        try:
            tables = self.query_api.query(org=self.org, query=flux)
            bots = []
            for table in tables:
                for rec in table.records:
                    bot_name = rec.get_value()
                    if bot_name and bot_name not in bots:
                        bots.append(bot_name)

            if bots:
                logging.info(f"InfluxDB에서 {len(bots)}개 BOT 발견: {bots}")
                return bots
            else:
                logging.warning("InfluxDB에서 BOT을 찾지 못함 - 기본값 사용")
                return DEFAULT_BOTS

        except Exception as e:
            logging.warning(f"BOT 목록 조회 실패: {e} - 기본값 사용")
            return DEFAULT_BOTS

    def get_all_bots_battery_status(self, lookback: str = "-30m") -> List[Dict[str, Any]]:
        """모든 터틀봇의 배터리 상태 조회 (동적 BOT 조회)"""
        results = []
        bots = self.discover_bots()  # 동적으로 BOT 목록 조회

        for bot in bots:
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
        """사용 가능한 터틀봇 목록 반환 (동적 조회)"""
        return self.discover_bots() 