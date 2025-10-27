from prometheus_client import start_http_server, Gauge
import requests
import time
import os
from dotenv import load_dotenv
from datetime import datetime

load_dotenv()

# Prometheus metrics
UP = Gauge('mlops_container_up', 'Container running state', ['name'])
RESTARTS = Gauge('mlops_container_restart_count', 'Container restart count', ['name'])
HEALTH = Gauge('mlops_container_health_status', 'Container health status', ['name'])
START_TIME = Gauge('mlops_container_start_time', 'Container start timestamp', ['name'])
UPTIME = Gauge('mlops_container_up_time_seconds', 'Container uptime in seconds', ['name'])

METRICS_URL = os.environ.get('MLFLOW_METRICS_URL')
HEALTH_URL = os.environ.get('MLFLOW_HEALTH_URL')
CONTAINERS_URL = os.environ.get('MLFLOW_CONTAINERS_URL')

def parse_timestamp(timestamp_str):
    try:
        if not timestamp_str or timestamp_str == "0001-01-01T00:00:00Z":
            return None
            
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
        return None

def update_metrics():
    try:
        # --- Base metrics ---
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

        # --- Health metrics ---
        health_resp = requests.get(HEALTH_URL).json()
        for c in health_resp.get('containers', []):
            status = 1 if c.get('health_status') == 'healthy' else 0
            HEALTH.labels(name=c['name']).set(status)

        # --- Start time & uptime ---
        containers_resp = requests.get(CONTAINERS_URL).json()
        now_ts = time.time()
        for c in containers_resp.get('containers', []):
            start_ts = parse_timestamp(c.get('started_at'))
            if start_ts:
                START_TIME.labels(name=c['name']).set(start_ts)
                UPTIME.labels(name=c['name']).set(now_ts - start_ts)
            else:
                print(f"Container '{c['name']}' has invalid start time: {c.get('started_at')}")

    except Exception as e:
        print("Error updating metrics:", e)

if __name__ == '__main__':
    start_http_server(8000)
    print("MLflow exporter running on port 8000...")
    while True:
        update_metrics()
        time.sleep(5)
