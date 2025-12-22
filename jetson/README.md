# Jetson Metric Collection

This directory contains the scripts and configuration for collecting metrics from an NVIDIA Jetson device and pushing them to a remote Prometheus Pushgateway.

## Files

### `jetson_fetch.sh`
The main metric collection script that runs on the Jetson device.

**What it does:**
- Executes `tegrastats` to read Jetson hardware metrics
- Parses CPU temperature, GPU temperature, RAM usage, GPU load, and per-core CPU frequencies
- Formats metrics in Prometheus text format
- Pushes metrics to a remote Pushgateway via HTTP

**Key features:**
- Robust error handling and logging
- Configurable via environment variables
- Validates metric parsing before pushing
- Logs to syslog and stderr for troubleshooting

**Configuration (in the script or systemd service):**
```bash
PUSHGATEWAY_URL="http://10.0.4.42:9091"  # External monitoring VM
JOB_NAME="jetson_remote"                  # Prometheus job name
SCRAPE_INTERVAL=5                          # Collection interval in seconds
INSTANCE_LABEL="jetson-primary"            # Instance identifier
LOG_LEVEL="INFO"                           # DEBUG, INFO, WARN, ERROR
```

**Collected Metrics:**
- `jetson_cpu_temp_c` - CPU temperature in Celsius
- `jetson_gpu_temp_c` - GPU temperature in Celsius
- `jetson_soc0_temp_c`, `jetson_soc1_temp_c`, `jetson_soc2_temp_c` - SOC temperatures
- `jetson_ram_used_mb` - RAM used in MB
- `jetson_ram_total_mb` - Total RAM in MB
- `jetson_gpu_load_percent` - GPU load percentage
- `jetson_cpu_core{N}_percent` - Per-core CPU usage
- `jetson_cpu_core{N}_freq_mhz` - Per-core CPU frequency

### `jetson-monitoring.service`
Systemd service file for automatic startup and management of the metric collection script.

**What it does:**
- Defines a systemd service named `jetson-monitoring`
- Automatically starts the script on Jetson boot
- Restarts the script if it fails
- Logs output to syslog (viewable via `journalctl`)
- Sets environment variables for the script

**Installation:**
```bash
sudo cp jetson-monitoring.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable jetson-monitoring
sudo systemctl start jetson-monitoring
```

**Management:**
```bash
# View status
sudo systemctl status jetson-monitoring

# View logs
sudo journalctl -u jetson-monitoring -f

# Restart
sudo systemctl restart jetson-monitoring

# Stop
sudo systemctl stop jetson-monitoring

# Disable auto-start
sudo systemctl disable jetson-monitoring
```

## Deployment Steps

### 1. Copy files to Jetson
```bash
# From your local machine
scp jetson_fetch.sh wisevision@10.20.23.55:/tmp/
scp jetson-monitoring.service wisevision@10.20.23.55:/tmp/
```

### 2. Install on Jetson
```bash
# SSH to Jetson
ssh wisevision@10.20.23.55

# Create directory
mkdir -p /opt/jetson-monitoring

# Copy script
sudo cp /tmp/jetson_fetch.sh /opt/jetson-monitoring/
sudo chmod +x /opt/jetson-monitoring/jetson_fetch.sh

# Install systemd service
sudo cp /tmp/jetson-monitoring.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable jetson-monitoring
sudo systemctl start jetson-monitoring
```

### 3. Verify
```bash
# Check service status
sudo systemctl status jetson-monitoring

# View recent logs
sudo journalctl -u jetson-monitoring -n 20

# Follow live logs
sudo journalctl -u jetson-monitoring -f
```

Expected log output:
```
[INFO] Starting Jetson metric collection (PID: 1234)
[DEBUG] Environment validation passed
[DEBUG] Raw tegrastats: RAM 2048/7654...
[DEBUG] Successfully pushed metrics (HTTP 200)
```

## Configuration

### Change metric collection interval

Edit the systemd service:
```bash
sudo nano /etc/systemd/system/jetson-monitoring.service
```

Change the `SCRAPE_INTERVAL` line:
```ini
Environment="SCRAPE_INTERVAL=10"  # Collect every 10 seconds instead of 5
```

Apply changes:
```bash
sudo systemctl daemon-reload
sudo systemctl restart jetson-monitoring
```

### Change Pushgateway URL

If your monitoring VM IP or port changes:
```bash
sudo nano /etc/systemd/system/jetson-monitoring.service
```

Update:
```ini
Environment="PUSHGATEWAY_URL=http://10.0.4.99:9091"
```

Restart:
```bash
sudo systemctl daemon-reload
sudo systemctl restart jetson-monitoring
```

### Change instance label

If you have multiple Jetson devices:
```bash
sudo nano /etc/systemd/system/jetson-monitoring.service
```

```ini
Environment="INSTANCE_LABEL=jetson-device-2"
```

This helps distinguish metrics from different Jetson devices in Prometheus.

## Troubleshooting

### Script fails with "tegrastats not found"
```bash
# Verify tegrastats is installed
ls -la /usr/bin/tegrastats

# It should be part of NVIDIA Jetson Tools
# Install if missing: sudo apt-get install nvidia-jetson-tools
```

### "curl not found"
```bash
sudo apt-get install curl
```

### Metrics not reaching Pushgateway

1. Check logs on Jetson:
   ```bash
   sudo journalctl -u jetson-monitoring -f
   ```

2. Verify network connectivity:
   ```bash
   # Can Jetson reach monitoring VM?
   ping 10.0.4.42
   curl http://10.0.4.42:9091/-/healthy
   ```

3. Check metrics file is being created:
   ```bash
   cat /tmp/jetson_jetson-primary.prom
   ```

4. Check Pushgateway is accessible:
   ```bash
   curl -X POST --data-binary @/tmp/jetson_jetson-primary.prom \
       http://10.0.4.42:9091/metrics/job/jetson_remote/instance/jetson-primary
   ```

### High CPU/Memory usage

If the script is consuming too much CPU:
1. Increase `SCRAPE_INTERVAL` to collect less frequently
2. Check if `tegrastats` is hanging (use timeout)
3. Monitor with: `top`, `ps aux | grep jetson_fetch`

### Service keeps restarting

Check logs for errors:
```bash
sudo journalctl -u jetson-monitoring -n 50
```

Common causes:
- Pushgateway is unreachable → Check network connectivity
- Metrics parsing fails → Check tegrastats output manually
- Out of memory → Check system resources

## Manual Testing

To test the script manually without the systemd service:

```bash
# Run the script directly
/opt/jetson-monitoring/jetson_fetch.sh

# With debug logging
LOG_LEVEL=DEBUG /opt/jetson-monitoring/jetson_fetch.sh

# Stop with Ctrl+C
```

View the generated metrics file:
```bash
cat /tmp/jetson_jetson-primary.prom
```

Test pushing manually:
```bash
curl -X POST --data-binary @/tmp/jetson_jetson-primary.prom \
    http://10.0.4.42:9091/metrics/job/jetson_remote/instance/jetson-primary
```

## Monitoring VM Integration

The metrics collected by this script are:
1. Pushed to Pushgateway: `http://10.0.4.42:9091`
2. Scraped by Prometheus from Pushgateway
3. Visualized in Grafana dashboards
4. Used for alerting in Alertmanager

For monitoring VM setup, see the main project documentation:
- `QUICKSTART.md`
- `TWO_TIER_ARCHITECTURE.md`

## Performance Considerations

| Setting | Trade-off |
|---------|-----------|
| `SCRAPE_INTERVAL=2` | More frequent data, higher bandwidth |
| `SCRAPE_INTERVAL=5` | **Recommended** - Good balance |
| `SCRAPE_INTERVAL=10` | Less frequent updates, lower bandwidth |
| `SCRAPE_INTERVAL=60` | Very sparse data, minimal overhead |

## Architecture

```
┌─────────────────────────────────────┐
│         Jetson Device               │
│  (10.20.23.55)                     │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ jetson_fetch.sh             │   │
│  │ (every 5 seconds)           │   │
│  │                             │   │
│  │ 1. Run tegrastats           │   │
│  │ 2. Parse metrics            │   │
│  │ 3. Format Prometheus text   │   │
│  │ 4. HTTP POST to Pushgateway │   │
│  └──────────────┬──────────────┘   │
└─────────────────┼──────────────────┘
                  │ HTTP POST
                  │ (metrics)
                  ↓
        ┌──────────────────────┐
        │  Monitoring VM       │
        │  (10.0.4.42)         │
        │                      │
        │  ┌────────────────┐  │
        │  │  Pushgateway   │  │
        │  │  (9091)        │  │
        │  └────────┬───────┘  │
        │           │          │
        │           ↓ (scrape) │
        │  ┌────────────────┐  │
        │  │  Prometheus    │  │
        │  │  (9090)        │  │
        │  └────────┬───────┘  │
        │           │          │
        │           ↓          │
        │  ┌────────────────┐  │
        │  │    Grafana     │  │
        │  │    (3000)      │  │
        │  └────────────────┘  │
        └──────────────────────┘
```

## Links

- Prometheus: https://prometheus.io/
- Pushgateway: https://github.com/prometheus/pushgateway
- Jetson Documentation: https://developer.nvidia.com/embedded/jetson
- tegrastats: https://docs.nvidia.com/jetson/l4t/index.html
