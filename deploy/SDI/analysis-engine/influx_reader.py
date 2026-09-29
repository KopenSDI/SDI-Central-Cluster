import os
import logging
from typing import Optional
from influxdb_client import InfluxDBClient

# 일단 로컬에서도 테스트가 되게끔 해놨는데, 테스트 성공 이후에는 아래 주석 풀고 컨테이너 올려야 합니당
# INFLUX_URL    = os.getenv("INFLUX_URL", "http://influxdb.tbot-monitoring.svc.cluster.local:8086")
# INFLUX_TOKEN  = os.getenv("INFLUX_TOKEN")
# INFLUX_ORG    = os.getenv("INFLUX_ORG", "keti")
# INFLUX_BUCKET = os.getenv("INFLUX_BUCKET", "turtlebot")
INFLUX_URL    = os.getenv("INFLUX_URL", "http://10.0.4.40:32086")
INFLUX_TOKEN  = os.getenv("INFLUX_TOKEN")
INFLUX_ORG    = os.getenv("INFLUX_ORG", "keti")
INFLUX_BUCKET = os.getenv("INFLUX_BUCKET", "turtlebot")

# 실제 InfluxDB에서 조회되는 터틀봇들 (실제 데이터: Burger-1: 413.3Wh, Burger-2: 315.0Wh)
BOTS = ["TURTLEBOT3-Burger-1", "TURTLEBOT3-Burger-2"]

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
