#!/bin/sh
# Auto-generate alert_rules.yml from template and config

set -e


# Load alert config (container or host)
if [ -f "/etc/prometheus/alert-config.env" ]; then
    set -a
    . /etc/prometheus/alert-config.env
    set +a
elif [ -f "./prometheus/alert-config.env" ]; then
    set -a
    . ./prometheus/alert-config.env
    set +a
fi

# Set defaults if not set
export TEMP_THRESHOLD=${TEMP_THRESHOLD:-80}
export TEMP_DURATION=${TEMP_DURATION:-2m}
export GPU_THRESHOLD=${GPU_THRESHOLD:-95}
export GPU_DURATION=${GPU_DURATION:-1m}
export RAM_THRESHOLD_MB=${RAM_THRESHOLD_MB:-13312}
export RAM_THRESHOLD_GB=${RAM_THRESHOLD_GB:-13}
export RAM_DURATION=${RAM_DURATION:-1m}
export CPU_CORE_THRESHOLD=${CPU_CORE_THRESHOLD:-95}
export CPU_CORE_DURATION=${CPU_CORE_DURATION:-1m}
export RAM_AVAILABLE_THRESHOLD=${RAM_AVAILABLE_THRESHOLD:-800}
export RAM_AVAILABLE_DURATION=${RAM_AVAILABLE_DURATION:-30s}
export GPU_IDLE_THRESHOLD=${GPU_IDLE_THRESHOLD:-5}
export GPU_IDLE_DURATION=${GPU_IDLE_DURATION:-1m}
export CPU_FREQ_THRESHOLD=${CPU_FREQ_THRESHOLD:-1800}
export CPU_FREQ_DURATION=${CPU_FREQ_DURATION:-30s}


# Determine if running in container or on host
if [ -f /etc/prometheus/alert_rules.yml.template ]; then
    TEMPLATE_PATH=/etc/prometheus/alert_rules.yml.template
    OUTPUT_PATH=/etc/prometheus/alert_rules.yml
elif [ -f ./prometheus/alert_rules.yml.template ]; then
    TEMPLATE_PATH=./prometheus/alert_rules.yml.template
    OUTPUT_PATH=./prometheus/alert_rules.yml
else
    echo "ERROR: alert_rules.yml.template not found."
    exit 1
fi

envsubst < "$TEMPLATE_PATH" > "$OUTPUT_PATH"

echo "Alert rules generated with:"
echo "  TEMP_THRESHOLD=${TEMP_THRESHOLD}°C"
echo "  GPU_THRESHOLD=${GPU_THRESHOLD}%"
echo "  RAM_THRESHOLD_MB=${RAM_THRESHOLD_MB}MB"
echo "  CPU_CORE_THRESHOLD=${CPU_CORE_THRESHOLD}%"

