from influxdb_client import InfluxDBClient, Point, WritePrecision
from influxdb_client.client.write_api import SYNCHRONOUS
from datetime import datetime, timedelta, timezone
import random
import os

INFLUX_URL    = os.getenv("INFLUX_URL", "http://10.0.5.52:32086")
INFLUX_TOKEN  = os.getenv("INFLUX_TOKEN")
INFLUX_ORG    = os.getenv("INFLUX_ORG", "keti")
INFLUX_BUCKET = os.getenv("INFLUX_BUCKET", "turtlebot")

BOTS = ["TURTLEBOT3-Burger-1", "TURTLEBOT3-Burger-2"]  # 실제 터틀봇 호스트 이름

N_POINTS = 50  # 총 50개 포인트

def main():
    client = InfluxDBClient(url=INFLUX_URL, token=INFLUX_TOKEN, org=INFLUX_ORG)
    write_api = client.write_api(write_options=SYNCHRONOUS)

    now = datetime.now(timezone.utc)

    points = []
    for _ in range(N_POINTS):
        bot = random.choice(BOTS)
        wh  = round(random.uniform(250.0, 500.0), 1)  
        ts = now - timedelta(
            minutes=random.randint(0, 25),
            seconds=random.randint(0, 59)
        )

        p = (
            Point("battery")
            .tag("bot", bot)
            .field("wh", wh)
            .time(ts, WritePrecision.NS)
        )
        points.append(p)
    write_api.write(bucket=INFLUX_BUCKET, org=INFLUX_ORG, record=points)

    print(f"Wrote {len(points)} points to bucket '{INFLUX_BUCKET}'.")
    client.close()

if __name__ == "__main__":
    main()

