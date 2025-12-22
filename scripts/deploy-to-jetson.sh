#!/bin/bash
# Jetson deployment helper script
# This automates the deployment process via SSH ProxyJump
# Usage: ./scripts/deploy-to-jetson.sh [sync|deploy|logs|tunnel]

set -e

JETSON_HOST="wisejetson"
JETSON_PROJECT_PATH="~/Models-Monitor"
LOCAL_PROJECT_PATH="/home/bouhmid/Desktop/Models-Monitor"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_header() {
  echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
  echo -e "${RED}✗ $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}⚠ $1${NC}"
}

# Check SSH access
check_ssh_access() {
  print_header "Checking SSH access to Jetson"
  
  if ssh -q "$JETSON_HOST" "echo 'SSH OK'" 2>/dev/null; then
    print_success "SSH connection to $JETSON_HOST is working"
  else
    print_error "Cannot connect to $JETSON_HOST. Check your SSH config:"
    echo "  Host: $JETSON_HOST"
    echo "  Check ~/.ssh/config has proper ProxyJump configuration"
    exit 1
  fi
}

# Sync project to Jetson
sync_to_jetson() {
  print_header "Syncing project to Jetson"
  
  echo "Source: $LOCAL_PROJECT_PATH"
  echo "Target: $JETSON_HOST:$JETSON_PROJECT_PATH"
  
  rsync -av --delete \
    -e "ssh -o ProxyJump=52.47.89.123" \
    "$LOCAL_PROJECT_PATH/" \
    "wisevision@10.20.23.55:$JETSON_PROJECT_PATH/" \
    --exclude=".git" \
    --exclude=".env" \
    --exclude="prometheus/data" \
    --exclude="grafana/data" \
    --exclude="alertmanager"
  
  print_success "Project synced to Jetson"
}

# Deploy services
deploy_services() {
  print_header "Deploying monitoring stack to Jetson"
  
  ssh "$JETSON_HOST" bash <<'ENDSSH'
    set -e
    echo "1/5: Navigating to project..."
    cd ~/Models-Monitor
    
    echo "2/5: Fixing permissions..."
    chmod +x scripts/fix-permissions.sh
    ./scripts/fix-permissions.sh
    
    echo "3/5: Ensuring .env file exists..."
    if [ ! -f .env ]; then
      cat > .env << 'EOF'
SMTP_IDENTITY=amriyassine722@gmail.com
PROMETHEUS_URL=http://prometheus:9090
GRAFANA_URL=http://grafana:3000
PUSHGATEWAY_URL=http://pushgateway:9091
ALERTMANAGER_URL=http://alertmanager:9093
GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASSWORD=admin
EOF
      echo "Created .env file"
    fi
    
    echo "4/5: Pulling latest Docker images..."
    docker compose pull || true
    
    echo "5/5: Starting services..."
    docker compose up -d
    
    echo ""
    echo "Service status:"
    docker compose ps
ENDSSH
  
  print_success "Services deployed successfully"
}

# View logs
view_logs() {
  print_header "Jetson monitoring stack logs"
  
  local service=${1:-""}
  
  if [ -z "$service" ]; then
    echo "Usage: ./scripts/deploy-to-jetson.sh logs [service]"
    echo ""
    echo "Available services:"
    ssh "$JETSON_HOST" "cd ~/Models-Monitor && docker compose ps --services"
    return
  fi
  
  ssh -t "$JETSON_HOST" "cd ~/Models-Monitor && docker compose logs -f --tail=100 $service"
}

# Setup SSH tunnels
setup_tunnels() {
  print_header "Setting up SSH tunnels to Jetson"
  
  echo "Forwarding ports:"
  echo "  Local 9090  → Jetson 9090  (Prometheus)"
  echo "  Local 3000  → Jetson 3000  (Grafana)"
  echo "  Local 9093  → Jetson 9093  (Alertmanager)"
  echo "  Local 9091  → Jetson 9091  (Pushgateway)"
  echo ""
  echo "Press Ctrl+C to stop tunnels"
  echo ""
  
  ssh -N \
    -L 9090:localhost:9090 \
    -L 3000:localhost:3000 \
    -L 9093:localhost:9093 \
    -L 9091:localhost:9091 \
    "$JETSON_HOST"
}

# Full deployment workflow
full_deploy() {
  print_header "Full Deployment Workflow"
  
  check_ssh_access
  
  read -p "Sync project to Jetson? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    sync_to_jetson
  fi
  
  read -p "Deploy services? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    deploy_services
  fi
  
  print_header "Deployment Complete!"
  echo "Next steps:"
  echo "1. Run: ./scripts/deploy-to-jetson.sh tunnel"
  echo "2. Open http://localhost:3000 (Grafana)"
  echo "3. Open http://localhost:9090 (Prometheus)"
}

# Main command router
case "${1:-help}" in
  sync)
    check_ssh_access
    sync_to_jetson
    ;;
  deploy)
    check_ssh_access
    deploy_services
    ;;
  logs)
    check_ssh_access
    view_logs "$2"
    ;;
  tunnel)
    check_ssh_access
    setup_tunnels
    ;;
  ssh)
    ssh "$JETSON_HOST"
    ;;
  status)
    check_ssh_access
    print_header "Jetson Services Status"
    ssh "$JETSON_HOST" "cd ~/Models-Monitor && docker compose ps"
    ;;
  restart)
    check_ssh_access
    print_header "Restarting services on Jetson"
    ssh "$JETSON_HOST" "cd ~/Models-Monitor && docker compose restart"
    print_success "Services restarted"
    ;;
  full|deploy-full)
    full_deploy
    ;;
  help|--help|-h)
    cat << 'HELP'
Jetson Deployment Helper

Usage: ./scripts/deploy-to-jetson.sh [command]

Commands:
  sync              Sync project files to Jetson (excludes data directories)
  deploy            Deploy services on Jetson
  logs [service]    View logs from specific service (or all if not specified)
  tunnel            Create SSH tunnels for accessing services locally
  status            Check service status on Jetson
  restart           Restart all services on Jetson
  ssh               SSH into Jetson directly
  full              Full deployment workflow (sync + deploy)
  help              Show this help message

Examples:
  # Full deployment
  ./scripts/deploy-to-jetson.sh full

  # Sync code and deploy
  ./scripts/deploy-to-jetson.sh sync
  ./scripts/deploy-to-jetson.sh deploy

  # View Prometheus logs
  ./scripts/deploy-to-jetson.sh logs prometheus

  # Create tunnels to access services locally
  ./scripts/deploy-to-jetson.sh tunnel

  # Then open http://localhost:3000 for Grafana

HELP
    ;;
  *)
    print_error "Unknown command: $1"
    echo "Run './scripts/deploy-to-jetson.sh help' for usage"
    exit 1
    ;;
esac
