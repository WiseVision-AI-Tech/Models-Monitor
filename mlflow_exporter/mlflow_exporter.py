from prometheus_client import start_http_server, Gauge
import requests
import time
import os
from dotenv import load_dotenv
from datetime import datetime, timezone

load_dotenv()

# Prometheus metrics
UP = Gauge('mlops_container_up', 'Container running state (1=running, 0=down)', ['name'])
RESTARTS = Gauge('mlops_container_restart_count', 'Container restart count', ['name'])
HEALTH = Gauge('mlops_container_health_status', 'Container health status (1=healthy, 0=unhealthy)', ['name'])
START_TIME = Gauge('mlops_container_start_time', 'Container start timestamp (epoch)', ['name'])

# Endpoints from env
METRICS_URL = os.environ.get('MLFLOW_METRICS_URL')
HEALTH_URL = os.environ.get('MLFLOW_HEALTH_URL')
CONTAINERS_URL = os.environ.get('MLFLOW_CONTAINERS_URL')

def update_metrics():
    try:
        # --- Metrics endpoint ---
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

        # --- Health endpoint ---
        health_resp = requests.get(HEALTH_URL).json()
        for c in health_resp.get('containers', []):
            status = 1 if c.get('health_status') == 'healthy' else 0
            HEALTH.labels(name=c['name']).set(status)

        # --- Containers endpoint ---
        containers_resp = requests.get(CONTAINERS_URL).json()
        for c in containers_resp.get('containers', []):
            # Convert UTC ISO timestamp to epoch
            started_at = c['started_at'].split('.')[0]  
            dt = datetime.strptime(started_at, "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc)
            start_ts = dt.timestamp()
            START_TIME.labels(name=c['name']).set(start_ts)

    except Exception as e:
        print("Error fetching metrics:", e)

if __name__ == '__main__':
    start_http_server(8000)  # Prometheus will scrape this
    while True:
        update_metrics()
        time.sleep(5)
