# Jetson Monitoring Stack

A decoupled monitoring solution for NVIDIA Jetson devices in private networks. Jetson pushes metrics to an external monitoring VM, ensuring monitoring continues even if the Jetson device fails.

## Architecture

```
Jetson Device (Private Network)          Monitoring VM (AWS/External)
10.20.23.55                              10.0.4.42

tegrastats
  |
jetson_fetch.sh (every 5 seconds)        Pushgateway (9091)
  |                                       |
  | HTTP POST                            Prometheus (9090)
  +-----------------------------------+-> |
                                         Grafana (3000)
                                         Alertmanager (9093)
```

Benefits:
- Monitoring survives if Jetson fails
- Jetson has no service dependencies
- Works through VPN, NAT, and firewalls
- Scalable to multiple Jetson devices

## Metrics Collected

- CPU temperature (Celsius)
- GPU temperature (Celsius)
- SOC temperatures (Celsius)
- RAM usage (MB)
- GPU load percentage
- Per-core CPU usage and frequency

## Prerequisites

### Jetson Device
- NVIDIA Jetson (Nano, Xavier, Orin, etc.)
- tegrastats (pre-installed with JetPack)
- curl (install: `apt-get install curl`)
- Network access to monitoring VM port 9091

### Monitoring VM
- Ubuntu 18.04+ (or similar Linux)
- Docker and Docker Compose
- 100MB disk space minimum
- Port 9091 accessible from Jetson

## Installation

### Step 1: Configure Jetson Device

Copy the metric collection script and service file to Jetson:

```bash
ssh wisevision@10.20.23.55 -o ProxyJump=52.47.89.123 "mkdir -p /opt/jetson-monitoring"

scp -o ProxyJump=52.47.89.123 \
    jetson/jetson_fetch.sh \
    wisevision@10.20.23.55:/tmp/

scp -o ProxyJump=52.47.89.123 \
    jetson/jetson-monitoring.service \
    wisevision@10.20.23.55:/tmp/
```

On Jetson, install and configure the service:

```bash
ssh wisevision@10.20.23.55 -o ProxyJump=52.47.89.123

# Install
sudo cp /tmp/jetson_fetch.sh /opt/jetson-monitoring/
sudo chmod +x /opt/jetson-monitoring/jetson_fetch.sh
sudo cp /tmp/jetson-monitoring.service /etc/systemd/system/

# Configure (edit service file to match your monitoring VM IP)
sudo nano /etc/systemd/system/jetson-monitoring.service
```

Edit the PUSHGATEWAY_URL to match your monitoring VM:
```
Environment="PUSHGATEWAY_URL=http://10.0.4.42:9091"
```

Start the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable jetson-monitoring
sudo systemctl start jetson-monitoring

# Verify it is running
sudo systemctl status jetson-monitoring
sudo journalctl -u jetson-monitoring -f
```

Expected output: `Successfully pushed metrics (HTTP 200)`

### Step 2: Deploy Monitoring Stack on VM

On the monitoring VM (10.0.4.42):

```bash
cd /opt/Models-Monitor

# Create .env configuration
cp .env.example .env
nano .env  # Update SMTP credentials and Grafana password

# Fix permissions
chmod +x scripts/fix-permissions.sh
./scripts/fix-permissions.sh

# Start services
docker compose pull
docker compose up -d

# Verify all services are running
docker compose ps
```

Expected: All 4 containers should show "Up"

### Step 3: Verify Metrics Flow

```bash
# Check Pushgateway received metrics
curl -s http://localhost:9091/metrics | grep jetson | head -5

# Verify Prometheus scraping
curl -s http://localhost:9090/api/v1/targets | grep pushgateway

# Run verification script
chmod +x scripts/verify-monitoring.sh
./scripts/verify-monitoring.sh
```

## Visualization

### Access Grafana Dashboard

#### Option 1: Direct Access (if VM accessible)

```
http://10.0.4.42:3000
Login: admin / (password from .env)
```

#### Option 2: SSH Tunnel

From your local machine:

```bash
ssh -L 3000:localhost:3000 -L 9090:localhost:9090 ubuntu@10.0.4.42

# Then open http://localhost:3000
```

Or use the provided tunnel script:

```bash
./scripts/tunnel.sh
# Then open http://localhost:3000
```

### Import Jetson Dashboard

1. Open Grafana: http://10.0.4.42:3000
2. Navigate to Configuration > Data Sources
3. Click "Add Data Source" > Prometheus
4. URL: `http://prometheus:9090`
5. Click "Save & Test"
6. Go to Dashboards > Import
7. Upload `grafana/dashboards/jetson_dashboard.json`
8. Select Prometheus as datasource

Dashboard displays:
- CPU temperature (real-time graph)
- GPU temperature (real-time graph)
- RAM usage percentage
- Per-core CPU frequencies
- GPU load percentage
- 30-day historical data

### Manual Metric Queries

Query metrics in Prometheus web UI (http://10.0.4.42:9090):

```
jetson_cpu_temp_c
jetson_gpu_temp_c
jetson_gpu_load_percent
jetson_ram_used_mb / jetson_ram_total_mb * 100  (RAM percentage)
jetson_cpu_core0_freq_mhz
jetson_soc0_temp_c
```

## Configuration

### Change Metric Collection Interval

Edit systemd service on Jetson:

```bash
sudo nano /etc/systemd/system/jetson-monitoring.service

# Default: SCRAPE_INTERVAL=5 (seconds)
# Change to: SCRAPE_INTERVAL=10

sudo systemctl daemon-reload
sudo systemctl restart jetson-monitoring
```

### Update Pushgateway URL

If monitoring VM IP changes:

```bash
sudo nano /etc/systemd/system/jetson-monitoring.service

# Update: Environment="PUSHGATEWAY_URL=http://NEW_IP:9091"

sudo systemctl daemon-reload
sudo systemctl restart jetson-monitoring
```

### Configure Alert Rules

Edit `prometheus/alert_rules.yml` to add custom alerts:

```yaml
- alert: HighCPUTemperature
  expr: jetson_cpu_temp_c > 80
  for: 30s
  labels:
    severity: critical
  annotations:
    summary: "CPU temperature {{ $value }}C"

- alert: HighGPULoad
  expr: jetson_gpu_load_percent > 90
  for: 30s
  labels:
    severity: warning
```

Restart Prometheus:

```bash
docker compose restart prometheus
```

## Troubleshooting

### Jetson Service Not Running

```bash
sudo systemctl status jetson-monitoring
sudo journalctl -u jetson-monitoring -n 50
```

Manual test:

```bash
/opt/jetson-monitoring/jetson_fetch.sh
```

### Metrics Not Reaching Pushgateway

From Jetson, test connectivity:

```bash
ping 10.0.4.42
curl -v http://10.0.4.42:9091/-/healthy
cat /tmp/jetson_jetson-primary.prom
```

### Prometheus Not Scraping

```bash
curl -s http://localhost:9090/api/v1/targets | grep pushgateway
docker compose logs prometheus | tail -50
```

### No Data in Grafana

1. Verify Prometheus data source is working: http://10.0.4.42:3000 > Configuration > Data Sources > Test
2. Check Prometheus has data: http://10.0.4.42:9090 > Graph > query "up"
3. Verify dashboard queries use correct metric names

## Multi-Jetson Deployment

Deploy on each Jetson with unique instance label:

```bash
# Jetson #1
sudo nano /etc/systemd/system/jetson-monitoring.service
# Add: Environment="INSTANCE_LABEL=jetson-primary"

# Jetson #2
sudo nano /etc/systemd/system/jetson-monitoring.service
# Add: Environment="INSTANCE_LABEL=jetson-secondary"
```

All metrics aggregate in Prometheus with labels to distinguish devices.

## Maintenance

### View Logs

```bash
# Jetson
ssh wisevision@10.20.23.55 -o ProxyJump=52.47.89.123 \
    "sudo journalctl -u jetson-monitoring -f"

# Monitoring VM
docker compose logs -f
docker compose logs -f prometheus
docker compose logs -f grafana
```

### Restart Services

```bash
# Jetson
sudo systemctl restart jetson-monitoring

# Monitoring VM
docker compose restart
docker compose restart prometheus
```

### Backup Metrics Data

```bash
docker compose exec prometheus tar czf /prometheus/backup.tar.gz /prometheus
docker cp prometheus:/prometheus/backup.tar.gz ./prometheus_backup.tar.gz
```

## File Structure

```
jetson/
  jetson_fetch.sh ................. Metric collection script
  jetson-monitoring.service ....... Systemd service file
  README.md ....................... Jetson documentation

docker-compose.yml ................. Service definitions
prometheus/
  prometheus.yml .................. Prometheus configuration
  alert_rules.yml ................. Alert definitions

grafana/
  provisioning/
    datasources/prometheus.yml .... Prometheus datasource
  dashboards/
    jetson_dashboard.json ......... Pre-configured dashboard

alertmanager/
  alertmanager.yml ................ Alert routing

scripts/
  fix-permissions.sh .............. Fix Docker permissions
  verify-monitoring.sh ............ Health check
  tunnel.sh ....................... SSH tunneling

.env.example ....................... Configuration template
docker-compose.yml ................. Main docker configuration
```

## License

Apache License 2.0 - See LICENSE file
