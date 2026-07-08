import os
import logging
from typing import Optional, List
from influxdb_client import InfluxDBClient

#===============================================================================
# InfluxDB 설정 - 환경변수 또는 파일에서 읽기
# 우선순위: 1) 환경변수  2) 파일  3) 기본값
#===============================================================================

def _read_file_or_default(file_path: str, default: str = "") -> str:
    """파일에서 값을 읽거나 기본값 반환 (ConfigMap/Secret 연동용)"""
    try:
        if os.path.exists(file_path):
            with open(file_path, 'r') as f:
                return f.read().strip()
    except Exception as e:
        logging.warning(f"파일 읽기 실패 ({file_path}): {e}")
    return default

def _get_influx_token() -> str:
    """InfluxDB 토큰 조회 - 환경변수 > 파일 > 기본값"""
    # 1) 환경변수에서
    token = os.getenv("INFLUX_TOKEN", "")
    if token:
        return token

    # 2) Secret 파일에서 (K8s Secret mount)
    token = _read_file_or_default("/app/influxDB-TOKEN.txt")
    if token:
        return token

    # 3) 로컬 개발용 파일
    token = _read_file_or_default("./influxDB-TOKEN.txt")
    if token:
        return token

    # 4) 기본값 (개발용 - 실제 운영에서는 반드시 환경변수/Secret 사용)
    logging.warning("INFLUX_TOKEN이 설정되지 않음 - 기본 토큰 사용")
    return ""

# 환경변수에서 설정 읽기 (K8s ConfigMap 연동)
INFLUX_URL    = os.getenv("INFLUX_URL", "http://influxdb.tbot-monitoring.svc.cluster.local:8086")
INFLUX_TOKEN  = _get_influx_token()
INFLUX_ORG    = os.getenv("INFLUX_ORG", "keti")
INFLUX_BUCKET = os.getenv("INFLUX_BUCKET", "turtlebot")

# 기본 BOT 목록 (동적 조회 실패 시 폴백용)
# TODO: 이 값은 동적 조회가 정상 작동하면 사용되지 않음
DEFAULT_BOTS = os.getenv("DEFAULT_BOTS", "TURTLEBOT3-Burger-1,TURTLEBOT3-Burger-2").split(",")

# 동적으로 조회된 BOT 목록 캐시
_cached_bots: List[str] = []

def get_available_bots() -> List[str]:
    """InfluxDB에서 사용 가능한 BOT 목록을 동적으로 조회"""
    global _cached_bots
    if _cached_bots:
        return _cached_bots
    return DEFAULT_BOTS

# 하위 호환성을 위한 BOTS 변수 (동적 조회로 업데이트됨)
BOTS = DEFAULT_BOTS

class InfluxReader:
    def __init__(
        self,
        url: str = INFLUX_URL,
        token: Optional[str] = INFLUX_TOKEN,
        org: str = INFLUX_ORG,
        bucket: str = INFLUX_BUCKET,
        timeout: int = 10,  
    ):
        if not token:
            logging.warning("INFLUX_TOKEN 이 설정 안됨")
        self.org = org
        self.bucket = bucket
        self.client = InfluxDBClient(url=url, token=token, org=org, timeout=timeout * 1000)
        self.query_api = self.client.query_api()

    def close(self):
        try:
            self.client.close()
        except Exception:
            pass

    def discover_bots(self, lookback: str = "-24h") -> List[str]:
        """
        InfluxDB에서 사용 가능한 모든 BOT 목록을 동적으로 조회
        battery measurement에서 고유한 bot 태그 값들을 가져옴
        """
        global _cached_bots, BOTS

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
                _cached_bots = bots
                BOTS = bots  # 글로벌 변수 업데이트
                logging.info(f"InfluxDB에서 {len(bots)}개 BOT 발견: {bots}")
                return bots
            else:
                logging.warning("InfluxDB에서 BOT을 찾지 못함 - 기본값 사용")
                return DEFAULT_BOTS

        except Exception as e:
            logging.warning(f"BOT 목록 조회 실패: {e} - 기본값 사용")
            return DEFAULT_BOTS

    def get_all_bots_battery(self, lookback: str = "-30m") -> List[dict]:
        """모든 BOT의 배터리 상태를 한번에 조회"""
        bots = self.discover_bots()
        results = []

        for bot in bots:
            wh = self.latest_wh(bot, lookback)
            results.append({
                "bot": bot,
                "wh": wh,
                "status": "ok" if wh is not None else "no_data"
            })

        return results

    def latest_wh(self, bot: str, lookback: str = "-30m") -> Optional[float]:
        flux = f""" from(bucket: "{self.bucket}") 
                    |> range(start: {lookback})
                    |> filter(fn: (r) => r._measurement == "battery" and r.bot == "{bot}" and r._field == "wh")
                    |> last()
                """ # 디비 쿼리여서 지우면 안됩니다.
        try:
            tables = self.query_api.query(org=self.org, query=flux)
        except Exception as e:
            logging.warning(f"Influx 쿼리 실패(wh, bot={bot}): {e}")
            return None

        for table in tables:
            for rec in table.records:
                try:
                    return float(rec.get_value())
                except (TypeError, ValueError):
                    return None
        return None
