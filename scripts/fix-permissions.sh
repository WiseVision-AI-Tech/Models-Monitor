#!/bin/sh
# Run this from the root of your project: ./scripts/fix-permissions.sh
echo "[Init] Fixing host folder permissions..."

# Grafana
if [ -d ./grafana/data ]; then
  echo "Fixing Grafana data, dashboards, provisioning..."
  sudo chown -R 472:472 ./grafana/data ./grafana/dashboards ./grafana/provisioning
  sudo chmod -R 755 ./grafana/data ./grafana/dashboards ./grafana/provisioning
fi

# Prometheus
if [ -d ./prometheus/data ]; then
  echo "Fixing Prometheus data..."
  sudo chown -R 65534:65534 ./prometheus/data
  sudo chmod -R 755 ./prometheus/data
fi

echo "[Init] Permissions fixed successfully!"
