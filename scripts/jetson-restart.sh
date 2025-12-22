#!/bin/bash

# RUN THIS DIRECTLY ON JETSON (wisevision@10.20.23.55)
# Copy entire script and paste into terminal

set -euo pipefail

echo "🔄 Updating Jetson monitoring script..."

# Copy new script
sudo cp /home/wisevision/Monitoring/jetson_fetch.sh /opt/jetson-monitoring/
sudo chmod +x /opt/jetson-monitoring/jetson_fetch.sh

echo "✓ Script updated"
echo ""

# Restart service
echo "🔄 Restarting service..."
sudo systemctl restart jetson-monitoring

echo "✓ Service restarted"
echo ""

# Wait for metrics
echo "⏳ Waiting 5 seconds for metrics to collect..."
sleep 5

# Check logs
echo "📋 Recent logs:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sudo journalctl -u jetson-monitoring -n 20 --no-pager

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check service status
echo "📊 Service status:"
sudo systemctl status jetson-monitoring --no-pager

echo ""
echo "✅ Done! Metrics should be flowing to PushGateway"
