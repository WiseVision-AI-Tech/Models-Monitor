#!/bin/bash

################################################################################
# Monitoring Stack Diagnostics
# 
# Check connectivity and data flow from Jetson to PushGateway to Prometheus
################################################################################

set -euo pipefail

echo "================================"
echo "MONITORING STACK DIAGNOSTICS"
echo "================================"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get monitoring VM IP
MONITORING_IP=$(hostname -I | awk '{print $1}')
echo "[1] Monitoring VM IP: $MONITORING_IP"
echo ""

# Check PushGateway connectivity
echo "[2] Checking PushGateway (port 9091)..."
if curl -s http://localhost:9091/-/healthy > /dev/null 2>&1; then
    echo -e "${GREEN}✓ PushGateway is UP${NC}"
else
    echo -e "${RED}✗ PushGateway is DOWN${NC}"
    exit 1
fi
echo ""

# Check Prometheus connectivity
echo "[3] Checking Prometheus (port 9090)..."
if curl -s http://localhost:9090/-/healthy > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Prometheus is UP${NC}"
else
    echo -e "${RED}✗ Prometheus is DOWN${NC}"
    exit 1
fi
echo ""

# Check for metrics in PushGateway
echo "[4] Checking metrics in PushGateway..."
METRICS_COUNT=$(curl -s http://localhost:9091/metrics 2>/dev/null | grep -c "^jetson_" || echo 0)
if [ "$METRICS_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ Found $METRICS_COUNT Jetson metrics${NC}"
else
    echo -e "${RED}✗ No Jetson metrics found (yet)${NC}"
    echo "   Jetson monitoring script may not have started or failed to push"
fi
echo ""

# Check Prometheus scrape targets
echo "[5] Checking Prometheus scrape targets..."
PUSHGATEWAY_UP=$(curl -s 'http://localhost:9090/api/v1/query?query=up{job="pushgateway"}' 2>/dev/null | grep -o '"value":\[.*\]' | head -1)
if echo "$PUSHGATEWAY_UP" | grep -q '1'; then
    echo -e "${GREEN}✓ Prometheus can scrape PushGateway${NC}"
else
    echo -e "${RED}✗ Prometheus cannot scrape PushGateway${NC}"
fi
echo ""

# Show next steps
echo "================================"
echo "NEXT STEPS"
echo "================================"
echo ""
echo "If no metrics are showing:"
echo ""
echo "1. SSH into Jetson and check if monitoring service is running:"
echo "   sudo systemctl status jetson-monitoring"
echo ""
echo "2. View Jetson script logs:"
echo "   sudo journalctl -u jetson-monitoring -f"
echo ""
echo "3. Test metric push manually from Jetson:"
echo "   curl -X POST http://$MONITORING_IP:9091/metrics/job/jetson_test/instance/manual -d 'test_metric 1'"
echo ""
echo "4. View this metric:"
echo "   curl http://localhost:9091/metrics | grep test_metric"
echo ""
echo "5. Verify Prometheus is scraping it:"
echo "   curl 'http://localhost:9090/api/v1/query?query=test_metric'"
echo ""
echo "6. Grafana Dashboard:"
echo "   Open http://localhost:3000 (admin/admin)"
echo "   Add Prometheus datasource pointing to http://prometheus:9090"
echo "   Create dashboard with metrics"
echo ""
