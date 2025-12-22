#!/bin/bash
# Fix permissions for Prometheus, Grafana, and Alertmanager data directories
# Run this from the root of your project: ./scripts/fix-permissions.sh
# This ensures Docker containers can write to mounted volumes

set -e

echo "[INFO] Starting permission fix for monitoring stack..."

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running with appropriate privileges
if [ "$EUID" -ne 0 ] && ! sudo -n true 2>/dev/null; then
  echo -e "${RED}[ERROR] This script requires sudo privileges${NC}"
  exit 1
fi

# Helper function to fix directory
fix_directory() {
  local dir=$1
  local uid=$2
  local gid=$3
  local name=$4
  
  if [ -d "$dir" ]; then
    echo -e "${YELLOW}[INFO] Fixing $name ($dir)...${NC}"
    sudo chown -R "$uid:$gid" "$dir"
    sudo chmod -R u+rwx,g+rwx,o+rx "$dir"
    echo -e "${GREEN}[OK] Fixed $name${NC}"
  else
    echo -e "${YELLOW}[WARN] Directory $dir does not exist, creating...${NC}"
    sudo mkdir -p "$dir"
    sudo chown "$uid:$gid" "$dir"
    sudo chmod u+rwx,g+rwx,o+rx "$dir"
    echo -e "${GREEN}[OK] Created and fixed $name${NC}"
  fi
}

# Grafana: UID 472, GID 472 (official grafana docker image)
fix_directory "./grafana/data" "472" "472" "Grafana data"
fix_directory "./grafana/dashboards" "472" "472" "Grafana dashboards"
fix_directory "./grafana/provisioning" "472" "472" "Grafana provisioning"

# Prometheus: UID 65534, GID 65534 (nobody user, used by prom/prometheus)
fix_directory "./prometheus/data" "65534" "65534" "Prometheus data"

# Alertmanager: UID 65534, GID 65534 (nobody user, used by prom/alertmanager)
fix_directory "./alertmanager" "65534" "65534" "Alertmanager config"

echo ""
echo -e "${GREEN}[SUCCESS] All permissions fixed successfully!${NC}"
echo ""
echo "Ownership summary:"
ls -ld ./grafana/data ./prometheus/data ./alertmanager 2>/dev/null | awk '{print $3":"$4, $NF}'
