#!/bin/bash

################################################################################
# JETSON SETUP GUIDE
# 
# Deploy monitoring agent on Jetson device at 10.20.23.55
################################################################################

set -euo pipefail

JETSON_IP="10.20.23.55"
MONITORING_VM_IP="10.0.4.42"
MONITORING_PORT="9091"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║         JETSON MONITORING DEPLOYMENT GUIDE                 ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Configuration:"
echo "  📍 Jetson IP: $JETSON_IP"
echo "  📍 Monitoring VM IP: $MONITORING_VM_IP:$MONITORING_PORT"
echo ""

# Step 1: SSH connection check
echo "STEP 1: Testing SSH connection to Jetson..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Run this to test connectivity:"
echo ""
echo "  ssh ubuntu@$JETSON_IP 'echo SSH Connection OK'"
echo ""
read -p "✓ Can you SSH into Jetson? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Cannot connect to Jetson. Please check:"
    echo "   - Network connectivity: ping $JETSON_IP"
    echo "   - SSH service running on Jetson"
    echo "   - Firewall rules"
    exit 1
fi
echo ""

# Step 2: Network connectivity check
echo "STEP 2: Testing network connectivity..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Run this from Jetson to test PushGateway connectivity:"
echo ""
echo "  ssh ubuntu@$JETSON_IP 'curl -I http://$MONITORING_VM_IP:$MONITORING_PORT'"
echo ""
read -p "✓ Can Jetson reach monitoring VM? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Jetson cannot reach monitoring VM. Please check:"
    echo "   - Firewall rules on both sides"
    echo "   - Port $MONITORING_PORT is open on monitoring VM"
    echo "   - Correct IP address ($MONITORING_VM_IP)"
    exit 1
fi
echo ""

# Step 3: Copy files to Jetson
echo "STEP 3: Copying monitoring script to Jetson..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Create directory on Jetson
ssh ubuntu@$JETSON_IP 'sudo mkdir -p /opt/jetson-monitoring'

# Copy files
scp "$SCRIPT_DIR/jetson_fetch.sh" ubuntu@$JETSON_IP:/tmp/
scp "$SCRIPT_DIR/jetson-monitoring.service" ubuntu@$JETSON_IP:/tmp/

# Move and set permissions
ssh ubuntu@$JETSON_IP '
  sudo mv /tmp/jetson_fetch.sh /opt/jetson-monitoring/
  sudo chmod +x /opt/jetson-monitoring/jetson_fetch.sh
  sudo mv /tmp/jetson-monitoring.service /etc/systemd/system/
  sudo chmod 644 /etc/systemd/system/jetson-monitoring.service
'

echo "✓ Files copied and permissions set"
echo ""

# Step 4: Enable and start service
echo "STEP 4: Enabling monitoring service..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

ssh ubuntu@$JETSON_IP '
  sudo systemctl daemon-reload
  sudo systemctl enable jetson-monitoring
  sudo systemctl start jetson-monitoring
  sleep 2
  sudo systemctl status jetson-monitoring --no-pager
'

echo ""

# Step 5: Verify metrics are flowing
echo "STEP 5: Verifying metrics..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

sleep 5  # Wait for first push

METRIC_COUNT=$(curl -s http://localhost:9091/metrics 2>/dev/null | grep -c "^jetson_" || echo 0)

if [ "$METRIC_COUNT" -gt 0 ]; then
    echo "✅ SUCCESS! Found $METRIC_COUNT Jetson metrics"
    echo ""
    echo "Sample metrics:"
    curl -s http://localhost:9091/metrics | grep "^jetson_" | head -5
else
    echo "⏳ Waiting for first metric push (usually within 5 seconds)..."
    sleep 10
    METRIC_COUNT=$(curl -s http://localhost:9091/metrics 2>/dev/null | grep -c "^jetson_" || echo 0)
    
    if [ "$METRIC_COUNT" -gt 0 ]; then
        echo "✅ SUCCESS! Found $METRIC_COUNT Jetson metrics"
    else
        echo "❌ No metrics yet. Check logs:"
        echo "   ssh ubuntu@$JETSON_IP 'sudo journalctl -u jetson-monitoring -n 20'"
        exit 1
    fi
fi
echo ""

# Step 6: Setup complete
echo "╔════════════════════════════════════════════════════════════╗"
echo "║            ✅ SETUP COMPLETE                              ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Next steps:"
echo ""
echo "1️⃣ Monitor Jetson metrics in Prometheus:"
echo "   http://10.0.4.42:9090"
echo ""
echo "2️⃣ View live metrics in Grafana:"
echo "   http://10.0.4.42:3000 (admin/admin)"
echo ""
echo "3️⃣ View Jetson logs (if needed):"
echo "   ssh ubuntu@$JETSON_IP 'sudo journalctl -u jetson-monitoring -f'"
echo ""
echo "4️⃣ Common troubleshooting:"
echo "   - Check service status: sudo systemctl status jetson-monitoring"
echo "   - Restart service: sudo systemctl restart jetson-monitoring"
echo "   - View recent errors: sudo journalctl -u jetson-monitoring --since '1 hour ago' -p err"
echo ""
