#!/bin/sh

set -e  # Exit on any error

echo "Checking for required files..."

# Check if template file exists
if [ ! -f /etc/alertmanager/alertmanager.yml.tpl ]; then
  echo "ERROR: Template file /etc/alertmanager/alertmanager.yml.tpl not found!"
  exit 1
fi

# Check if WEBHOOK_SECRET is set
if [ -z "$WEBHOOK_SECRET" ]; then
  echo "ERROR: WEBHOOK_SECRET environment variable is not set"
  exit 1
fi

echo "Generating Alertmanager configuration..."
echo "WEBHOOK_SECRET: ${WEBHOOK_SECRET}"

# Create config directory with proper permissions
mkdir -p /alertmanager/config

# Generate the config file
sed "s/\${WEBHOOK_SECRET}/$WEBHOOK_SECRET/g" /etc/alertmanager/alertmanager.yml.tpl > /alertmanager/config/alertmanager.yml

echo "Alertmanager configuration generated successfully!"

# Verify the file was created
if [ ! -f /alertmanager/config/alertmanager.yml ]; then
  echo "ERROR: Failed to create alertmanager.yml"
  exit 1
fi

echo "Starting Alertmanager with the following config:"
cat /alertmanager/config/alertmanager.yml

echo "=== STARTING ALERTMANAGER ==="
# Use exec to replace the current process with Alertmanager
exec /bin/alertmanager \
  --config.file=/alertmanager/config/alertmanager.yml \
  --storage.path=/alertmanager/data \
  --web.listen-address=:9093 \
  --cluster.listen-address=:9094