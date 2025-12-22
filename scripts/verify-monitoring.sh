#!/bin/bash

################################################################################
# Jetson Monitoring - Verification & Health Check Script
# 
# Run this on the monitoring VM to verify:
# 1. All services are running and healthy
# 2. Jetson is pushing metrics to Pushgateway
# 3. Prometheus is scraping Pushgateway
# 4. Data is flowing through the entire stack
#
# Usage: ./scripts/verify-monitoring.sh
################################################################################

set -e

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0

print_header() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_check() {
    echo -n "$1... "
}

pass() {
    echo -e "${GREEN}✓${NC}"
    ((CHECKS_PASSED++))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    ((CHECKS_FAILED++))
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# ===== CHECK 1: Docker Services =====
print_header "CHECK 1: Docker Services"

print_check "Checking Docker daemon"
if docker info > /dev/null 2>&1; then
    pass
else
    fail "Docker daemon not running"
    exit 1
fi

print_check "Checking docker-compose"
if docker compose version > /dev/null 2>&1; then
    pass
else
    fail "docker-compose not found"
    exit 1
fi

print_check "Checking project directory"
if [ -f "docker-compose.yml" ]; then
    pass
else
    fail "docker-compose.yml not found in current directory"
    echo "Please run this script from the Models-Monitor root directory"
    exit 1
fi

# ===== CHECK 2: Container Status =====
print_header "CHECK 2: Container Status"

for service in prometheus pushgateway alertmanager grafana; do
    print_check "Container '$service' is running"
    
    if docker compose ps $service 2>/dev/null | grep -q "Up"; then
        pass
    else
        fail "Service '$service' is not running or not healthy"
    fi
done

# ===== CHECK 3: Service Health Checks =====
print_header "CHECK 3: Service Health"

print_check "Prometheus health"
if curl -sf http://localhost:9090/-/healthy > /dev/null 2>&1; then
    pass
else
    fail "Prometheus not responding to health check"
fi

print_check "Pushgateway health"
if curl -sf http://localhost:9091/-/healthy > /dev/null 2>&1; then
    pass
else
    fail "Pushgateway not responding to health check"
fi

print_check "Alertmanager health"
if curl -sf http://localhost:9093/-/healthy > /dev/null 2>&1; then
    pass
else
    fail "Alertmanager not responding to health check"
fi

print_check "Grafana health"
if curl -sf http://localhost:3000/api/health > /dev/null 2>&1; then
    pass
else
    fail "Grafana not responding to health check"
fi

# ===== CHECK 4: Metrics Collection =====
print_header "CHECK 4: Metrics from Jetson"

print_check "Pushgateway has metrics"
if curl -s http://localhost:9091/metrics 2>/dev/null | grep -q "jetson_"; then
    pass
    
    # Count how many Jetson metrics we have
    METRIC_COUNT=$(curl -s http://localhost:9091/metrics 2>/dev/null | grep -c "^jetson_")
    echo "   Found $METRIC_COUNT Jetson metrics"
else
    fail "No Jetson metrics found in Pushgateway"
    warn "Has Jetson started pushing metrics? Check jetson_fetch.sh on Jetson device."
fi

print_check "Jetson instances registered"
if curl -s http://localhost:9091/metrics 2>/dev/null | grep -q 'job="jetson_remote"'; then
    pass
    
    # Show registered instances
    INSTANCES=$(curl -s http://localhost:9091/metrics 2>/dev/null | grep 'job="jetson_remote"' | grep 'instance=' | sed -E 's/.*instance="([^"]+)".*/\1/' | sort -u)
    echo "   Instances: $INSTANCES"
else
    fail "No Jetson instances found (job='jetson_remote')"
fi

# ===== CHECK 5: Prometheus Scraping =====
print_header "CHECK 5: Prometheus Targets"

print_check "Prometheus scrapes Pushgateway"
if curl -s http://localhost:9090/api/v1/targets 2>/dev/null | grep -q "pushgateway"; then
    pass
else
    fail "Pushgateway not found in Prometheus targets"
fi

print_check "Pushgateway target is UP"
if curl -s http://localhost:9090/api/v1/targets 2>/dev/null | jq -r '.data.activeTargets[] | select(.labels.job=="pushgateway") | .health' 2>/dev/null | grep -q "up"; then
    pass
else
    fail "Pushgateway target is DOWN in Prometheus"
    warn "Check Prometheus logs: docker compose logs prometheus"
fi

# ===== CHECK 6: Metrics Query =====
print_header "CHECK 6: Metrics Queries"

print_check "Prometheus can query jetson_cpu_temp_c"
QUERY_RESULT=$(curl -s "http://localhost:9090/api/v1/query?query=jetson_cpu_temp_c" 2>/dev/null | jq -r '.data.result | length' 2>/dev/null || echo "0")
if [ "$QUERY_RESULT" -gt 0 ]; then
    pass
    
    # Show the latest value
    VALUE=$(curl -s "http://localhost:9090/api/v1/query?query=jetson_cpu_temp_c" 2>/dev/null | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "N/A")
    echo "   Latest CPU Temp: ${VALUE}°C"
else
    fail "No data for jetson_cpu_temp_c query"
    warn "Wait a moment for metrics to be scraped, then try again"
fi

print_check "Prometheus can query jetson_ram_used_mb"
QUERY_RESULT=$(curl -s "http://localhost:9090/api/v1/query?query=jetson_ram_used_mb" 2>/dev/null | jq -r '.data.result | length' 2>/dev/null || echo "0")
if [ "$QUERY_RESULT" -gt 0 ]; then
    pass
    
    VALUE=$(curl -s "http://localhost:9090/api/v1/query?query=jetson_ram_used_mb" 2>/dev/null | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "N/A")
    echo "   RAM Used: ${VALUE} MB"
else
    fail "No data for jetson_ram_used_mb query"
fi

# ===== CHECK 7: Data Freshness =====
print_header "CHECK 7: Data Freshness"

print_check "Metrics are recent (< 1 minute old)"
LAST_SCRAPE=$(curl -s "http://localhost:9090/api/v1/query?query=time()-timestamp(jetson_cpu_temp_c)" 2>/dev/null | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "999")

if [ "$LAST_SCRAPE" != "null" ] && [ "$LAST_SCRAPE" -lt 60 ]; then
    pass
    echo "   Last metric received: ${LAST_SCRAPE} seconds ago"
elif [ "$LAST_SCRAPE" -lt 600 ]; then
    warn "Metrics are older than 1 minute (${LAST_SCRAPE}s) - Jetson may not be pushing regularly"
    ((CHECKS_PASSED++))
else
    fail "Metrics are very old (${LAST_SCRAPE}s) or not available"
fi

# ===== CHECK 8: Disk Usage =====
print_header "CHECK 8: Disk Space & Resources"

print_check "Monitoring VM disk space"
DISK_USAGE=$(df -h . | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -lt 80 ]; then
    pass
    echo "   Disk usage: ${DISK_USAGE}%"
else
    warn "Disk usage high: ${DISK_USAGE}%"
    ((CHECKS_PASSED++))
fi

print_check "Docker resource usage"
TOTAL_SIZE=$(docker system df --format "{{.Size}}" 2>/dev/null | tail -1 || echo "N/A")
echo "   Total Docker storage: $TOTAL_SIZE"
((CHECKS_PASSED++))

# ===== CHECK 9: Configuration =====
print_header "CHECK 9: Configuration"

print_check ".env file exists"
if [ -f ".env" ]; then
    pass
else
    fail ".env file not found"
fi

print_check "Prometheus config is valid"
if docker exec prometheus prometheus --config.file=/etc/prometheus/prometheus.yml --dry-run 2>&1 | grep -q "config valid"; then
    pass
else
    fail "Prometheus config validation failed"
fi

# ===== CHECK 10: Alertmanager =====
print_header "CHECK 10: Alertmanager Configuration"

print_check "Alertmanager config exists"
if [ -f "alertmanager/alertmanager.yml" ]; then
    pass
else
    fail "alertmanager.yml not found"
fi

print_check "Alerting rules are loaded"
RULES_COUNT=$(curl -s http://localhost:9090/api/v1/rules 2>/dev/null | jq '.data.groups | length' || echo "0")
if [ "$RULES_COUNT" -gt 0 ]; then
    pass
    echo "   Loaded $RULES_COUNT rule group(s)"
else
    warn "No alert rules loaded"
    ((CHECKS_PASSED++))
fi

# ===== SUMMARY =====
print_header "SUMMARY"

TOTAL_CHECKS=$((CHECKS_PASSED + CHECKS_FAILED))
echo "Checks Passed: ${GREEN}${CHECKS_PASSED}${NC}/$TOTAL_CHECKS"

if [ "$CHECKS_FAILED" -gt 0 ]; then
    echo "Checks Failed: ${RED}${CHECKS_FAILED}${NC}/$TOTAL_CHECKS"
    echo ""
    echo "⚠ Some checks failed. Review the output above for details."
    exit 1
else
    echo "Checks Failed: ${GREEN}0${NC}/$TOTAL_CHECKS"
    echo ""
    echo -e "${GREEN}✓ All checks passed! Monitoring stack is healthy.${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Open Grafana: http://localhost:3000"
    echo "2. Check Prometheus: http://localhost:9090"
    echo "3. View Pushgateway: http://localhost:9091"
    exit 0
fi
