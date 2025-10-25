from prometheus_client import start_http_server, Gauge
import requests
import time
import os
from dotenv import load_dotenv
from datetime import datetime

load_dotenv()

UP = Gauge('mlops_container_up', 'Container running state', ['name'])
RESTARTS = Gauge('mlops_container_restart_count', 'Container restart count', ['name'])
HEALTH = Gauge('mlops_container_health_status', 'Container health status', ['name'])
START_TIME = Gauge('mlops_container_start_time', 'Container start timestamp', ['name'])

METRICS_URL = os.environ.get('MLFLOW_METRICS_URL')
HEALTH_URL = os.environ.get('MLFLOW_HEALTH_URL')
CONTAINERS_URL = os.environ.get('MLFLOW_CONTAINERS_URL')

def parse_timestamp(timestamp_str):
    try:
        if timestamp_str == "0001-01-01T00:00:00Z":
            return 0
            
        if '.' in timestamp_str and 'T' in timestamp_str:
            date_part, time_fraction = timestamp_str.split('T')
            time_base, fractional = time_fraction.split('.')
            fractional = fractional.rstrip('Z')[:6]
            normalized = f"{date_part}T{time_base}.{fractional}Z"
        else:
            normalized = timestamp_str
            
        if normalized.endswith('Z'):
            normalized = normalized[:-1] + '+00:00'
            
        dt = datetime.fromisoformat(normalized)
        return dt.timestamp()
        
    except Exception:
        return 0

def update_metrics():
    try:
        metrics_resp = requests.get(METRICS_URL).text.splitlines()
        for line in metrics_resp:
            if line.startswith('mlops_container_up'):
                name = line.split('name="')[1].split('"')[0]
                value = float(line.split()[-1])
                UP.labels(name=name).set(value)
            elif line.startswith('mlops_container_restart_count'):
                name = line.split('name="')[1].split('"')[0]
                value = float(line.split()[-1])
                RESTARTS.labels(name=name).set(value)

        health_resp = requests.get(HEALTH_URL).json()
        for c in health_resp.get('containers', []):
            status = 1 if c.get('health_status') == 'healthy' else 0
            HEALTH.labels(name=c['name']).set(status)

        containers_resp = requests.get(CONTAINERS_URL).json()
        for c in containers_resp.get('containers', []):
            start_ts = parse_timestamp(c['started_at'])
            START_TIME.labels(name=c['name']).set(start_ts)

    except Exception as e:
        print("Error:", e)

if __name__ == '__main__':
    start_http_server(8000)
    while True:
        update_metrics()
        time.sleep(5)