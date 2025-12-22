#!/bin/bash

################################################################################
# Jetson Metric Collection and Push Script
# 
# Collects NVIDIA Jetson metrics (CPU, GPU, RAM, temperatures) using tegrastats
# and pushes them to a Prometheus Pushgateway (typically on external monitoring VM)
#
# Configuration:
#   - PUSHGATEWAY_URL: External Prometheus Pushgateway endpoint
#   - JOB_NAME: Prometheus job name for these metrics
#   - SCRAPE_INTERVAL: How often to collect and push metrics (seconds)
#
# Deployment:
#   1. Copy this script to Jetson: /opt/jetson-monitoring/jetson_fetch.sh
#   2. Make executable: chmod +x /opt/jetson-monitoring/jetson_fetch.sh
#   3. Create systemd service: copy jetson-monitoring.service to /etc/systemd/system/
#   4. Enable and start: sudo systemctl enable jetson-monitoring && sudo systemctl start jetson-monitoring
#
# Logs:
#   journalctl -u jetson-monitoring -f    # Follow live logs
#   journalctl -u jetson-monitoring --since "1 hour ago"  # View recent logs
################################################################################

set -euo pipefail

# ================= CONFIG =================
# These can be overridden by environment variables or config file

# External Pushgateway URL (on monitoring VM)
PUSHGATEWAY_URL="${PUSHGATEWAY_URL:-http://10.0.4.42:9091}"

# Prometheus job name - identifies this Jetson in monitoring
JOB_NAME="${JOB_NAME:-jetson_remote}"

# How often to collect metrics (seconds)
SCRAPE_INTERVAL="${SCRAPE_INTERVAL:-5}"

# Instance label (optional - identifies which Jetson if multiple)
INSTANCE_LABEL="${INSTANCE_LABEL:-$(hostname)}"

# Paths to required commands
TEGRAPATH="${TEGRAPATH:-/usr/bin/tegrastats}"
CURLPATH="${CURLPATH:-/usr/bin/curl}"

# Temporary metrics file
METRICS_FILE="/tmp/jetson_${INSTANCE_LABEL}.prom"

# Log configuration
LOG_LEVEL="${LOG_LEVEL:-INFO}"  # DEBUG, INFO, WARN, ERROR
SYSLOG_TAG="jetson-monitoring"

# ================= LOGGING =================

log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log to stderr and syslog
    echo "[${timestamp}] [${level}] ${message}" >&2
    echo "[${level}] ${message}" | logger -t "$SYSLOG_TAG" -p "user.${level,,}" 2>/dev/null || true
}

debug() { [[ "$LOG_LEVEL" =~ DEBUG|INFO ]] && log "DEBUG" "$@" || true; }
info()  { log "INFO" "$@"; }
warn()  { log "WARN" "$@"; }
error() { log "ERROR" "$@"; }

# ================= VALIDATION =================

validate_environment() {
    # Check required commands exist
    if [[ ! -f "$TEGRAPATH" ]]; then
        error "tegrastats not found at $TEGRAPATH"
        error "Please install NVIDIA Tegra utilities or update TEGRAPATH"
        exit 1
    fi
    
    if [[ ! -f "$CURLPATH" ]]; then
        error "curl not found at $CURLPATH"
        error "Please install curl: sudo apt-get install curl"
        exit 1
    fi
    
    # Verify tegrastats is executable
    if [[ ! -x "$TEGRAPATH" ]]; then
        error "tegrastats is not executable. Run: sudo chmod +x $TEGRAPATH"
        exit 1
    fi
    
    info "Environment validation passed"
    info "Pushgateway: $PUSHGATEWAY_URL"
    info "Job Name: $JOB_NAME"
    info "Instance: $INSTANCE_LABEL"
    info "Scrape Interval: ${SCRAPE_INTERVAL}s"
}

# ================= METRIC COLLECTION =================

collect_metrics() {
    local output
    
    # Run tegrastats with timeout (3s should be enough for one iteration)
    output=$(timeout 3s "$TEGRAPATH" 2>/dev/null | head -n 1) || {
        error "Failed to read tegrastats. Is this an NVIDIA Jetson device?"
        return 1
    }
    
    [[ -z "$output" ]] && {
        error "tegrastats returned empty output"
        return 1
    }
    
    debug "Raw tegrastats: $output"
    
    # Parse metrics from tegrastats output
    local ram_used ram_total cpu_temp gpu_load gpu_temp soc0_temp soc1_temp soc2_temp
    local cpu_usage_metrics cpu_freq_metrics
    
    # --- Parse RAM (format: RAM 1234/7654 example) ---
    ram_used=$(echo "$output" | grep -oP 'RAM \K\d+(?=/)' || echo "") && [[ -z "$ram_used" ]] && {
        error "Failed to parse RAM used from: $output"
        return 1
    }
    
    ram_total=$(echo "$output" | grep -oP 'RAM \d+/\K\d+' || echo "") && [[ -z "$ram_total" ]] && {
        error "Failed to parse RAM total"
        return 1
    }
    
    debug "RAM: ${ram_used}/${ram_total} MB"
    
    # --- Parse CPU temperature ---
    cpu_temp=$(echo "$output" | grep -oP 'cpu@\K\d+(\.\d+)?' || echo "0")
    debug "CPU Temp: ${cpu_temp}°C"
    
    # --- Parse GPU temperature ---
    gpu_temp=$(echo "$output" | grep -oP 'gpu@\K\d+(\.\d+)?' || echo "0")
    debug "GPU Temp: ${gpu_temp}°C"
    
    # --- Parse GPU load/frequency (GR3D_FREQ) ---
    # Handle both formats: "GR3D_FREQ 0%" and "GR3D_FREQ 0%@[305]"
    gpu_load=$(echo "$output" | grep -oP 'GR3D_FREQ \K\d+(?=%|@)' || echo "0")
    debug "GPU Load: ${gpu_load}%"
    
    # --- Parse SOC temperatures (Jetson Xavier/Orin have multiple SOCs) ---
    soc0_temp=$(echo "$output" | grep -oP 'soc0@\K\d+(\.\d+)?' || echo "0")
    soc1_temp=$(echo "$output" | grep -oP 'soc1@\K\d+(\.\d+)?' || echo "0")
    soc2_temp=$(echo "$output" | grep -oP 'soc2@\K\d+(\.\d+)?' || echo "0")
    debug "SOC Temps: ${soc0_temp}°C, ${soc1_temp}°C, ${soc2_temp}°C"
    
    # --- Parse per-core CPU usage and frequency ---
    local cpu_section cpu_usage_metrics cpu_freq_metrics
    cpu_section=$(echo "$output" | grep -oP 'CPU \[\K[^\]]+' || echo "")
    
    if [[ -n "$cpu_section" ]]; then
        local -a cores
        IFS=',' read -ra cores <<< "$cpu_section"
        
        debug "Found ${#cores[@]} CPU cores"
        
        for i in "${!cores[@]}"; do
            local usage freq
            usage=$(echo "${cores[$i]}" | grep -oP '^\d+' || echo "0")
            freq=$(echo "${cores[$i]}" | grep -oP '(?<=%@)\d+' || echo "0")
            
            cpu_usage_metrics+="jetson_cpu_core${i}_percent $usage"$'\n'
            cpu_freq_metrics+="jetson_cpu_core${i}_freq_mhz $freq"$'\n'
        done
    else
        warn "Could not parse CPU section from tegrastats"
        # Fallback: create placeholder metrics
        for i in {0..3}; do
            cpu_usage_metrics+="jetson_cpu_core${i}_percent 0"$'\n'
            cpu_freq_metrics+="jetson_cpu_core${i}_freq_mhz 0"$'\n'
        done
    fi
    
    # --- Generate Prometheus metrics file ---
    cat > "$METRICS_FILE" <<EOF
# HELP jetson_cpu_temp_c CPU temperature in Celsius
# TYPE jetson_cpu_temp_c gauge
jetson_cpu_temp_c{instance="$INSTANCE_LABEL"} $cpu_temp

# HELP jetson_gpu_temp_c GPU temperature in Celsius
# TYPE jetson_gpu_temp_c gauge
jetson_gpu_temp_c{instance="$INSTANCE_LABEL"} $gpu_temp

# HELP jetson_soc0_temp_c SOC0 temperature in Celsius
# TYPE jetson_soc0_temp_c gauge
jetson_soc0_temp_c{instance="$INSTANCE_LABEL"} $soc0_temp

# HELP jetson_soc1_temp_c SOC1 temperature in Celsius
# TYPE jetson_soc1_temp_c gauge
jetson_soc1_temp_c{instance="$INSTANCE_LABEL"} $soc1_temp

# HELP jetson_soc2_temp_c SOC2 temperature in Celsius
# TYPE jetson_soc2_temp_c gauge
jetson_soc2_temp_c{instance="$INSTANCE_LABEL"} $soc2_temp

# HELP jetson_ram_used_mb RAM used in MB
# TYPE jetson_ram_used_mb gauge
jetson_ram_used_mb{instance="$INSTANCE_LABEL"} $ram_used

# HELP jetson_ram_total_mb Total RAM in MB
# TYPE jetson_ram_total_mb gauge
jetson_ram_total_mb{instance="$INSTANCE_LABEL"} $ram_total

# HELP jetson_gpu_load_percent GPU load percentage
# TYPE jetson_gpu_load_percent gauge
jetson_gpu_load_percent{instance="$INSTANCE_LABEL"} $gpu_load

# HELP jetson_cpu_core_percent CPU core usage percentage
# TYPE jetson_cpu_core_percent gauge
$cpu_usage_metrics

# HELP jetson_cpu_core_freq_mhz CPU core frequency in MHz
# TYPE jetson_cpu_core_freq_mhz gauge
$cpu_freq_metrics
EOF
    
    debug "Metrics written to $METRICS_FILE"
    return 0
}

# ================= PUSH METRICS =================

push_metrics() {
    [[ ! -f "$METRICS_FILE" ]] && {
        error "Metrics file not found: $METRICS_FILE"
        return 1
    }
    
    local push_url="${PUSHGATEWAY_URL}/metrics/job/${JOB_NAME}/instance/${INSTANCE_LABEL}"
    
    debug "Pushing to: $push_url"
    
    local response
    response=$("$CURLPATH" -s -w "\n%{http_code}" -X POST \
        --data-binary "@${METRICS_FILE}" \
        "${push_url}" 2>&1) || {
        error "curl command failed. Check Pushgateway connectivity."
        return 1
    }
    
    local http_code=$(echo "$response" | tail -n1)
    
    if [[ "$http_code" == "200" ]]; then
        debug "Successfully pushed metrics (HTTP $http_code)"
        return 0
    else
        error "Failed to push metrics. HTTP Status: $http_code"
        error "Response: $(echo "$response" | head -n-1)"
        return 1
    fi
}

# ================= MAIN LOOP =================

main() {
    validate_environment
    
    info "Starting Jetson metric collection (PID: $$)"
    info "Metrics will be pushed to Pushgateway every ${SCRAPE_INTERVAL}s"
    
    # Initial sleep to let system stabilize
    sleep 2
    
    local iteration=0
    local errors=0
    local max_consecutive_errors=5
    
    while true; do
        iteration=$((iteration + 1))
        
        # Collect metrics from Jetson
        if ! collect_metrics; then
            errors=$((errors + 1))
            warn "Collection failed (attempt $errors/$max_consecutive_errors)"
            
            if [[ $errors -ge $max_consecutive_errors ]]; then
                error "Too many consecutive collection failures. Exiting."
                exit 1
            fi
        else
            errors=0  # Reset error counter on success
            
            # Push metrics to Pushgateway
            if ! push_metrics; then
                warn "Push failed, will retry on next cycle"
            fi
        fi
        
        # Log progress every 100 iterations
        if [[ $((iteration % 100)) -eq 0 ]]; then
            info "Still running... ($iteration cycles completed)"
        fi
        
        sleep "$SCRAPE_INTERVAL"
    done
}

# Trap signals for graceful shutdown
trap 'info "Received SIGTERM, shutting down gracefully"; exit 0' SIGTERM
trap 'info "Received SIGINT, shutting down gracefully"; exit 0' SIGINT

# Run main loop
main
