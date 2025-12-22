#!/bin/bash
# SSH Tunnel Helper for accessing Jetson services
# Creates persistent SSH port forwards for:
#   - Prometheus (9090)
#   - Grafana (3000)
#   - Alertmanager (9093)
#   - Pushgateway (9091)

JETSON_HOST="${1:-wisejetson}"

echo "╔════════════════════════════════════════════════════╗"
echo "║  Jetson SSH Tunnel Helper                          ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""
echo "Target: $JETSON_HOST"
echo ""
echo "Forwarding:"
echo "  Local 9090  → Jetson 9090  (Prometheus)"
echo "  Local 3000  → Jetson 3000  (Grafana)"
echo "  Local 9093  → Jetson 9093  (Alertmanager)"
echo "  Local 9091  → Jetson 9091  (Pushgateway)"
echo ""
echo "Services will be accessible at:"
echo "  • Prometheus:   http://localhost:9090"
echo "  • Grafana:      http://localhost:3000 (admin/admin)"
echo "  • Alertmanager: http://localhost:9093"
echo "  • Pushgateway:  http://localhost:9091"
echo ""
echo "Press Ctrl+C to close tunnels and exit"
echo ""

# Create the SSH tunnel
ssh -N \
  -L 9090:localhost:9090 \
  -L 3000:localhost:3000 \
  -L 9093:localhost:9093 \
  -L 9091:localhost:9091 \
  "$JETSON_HOST"
