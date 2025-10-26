global:
  resolve_timeout: 5m

route:
  receiver: "whatsapp"
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h

receivers:
  - name: "whatsapp"
    webhook_configs:
      - url: "https://whatsapp_webhook:5000/alert"
        send_resolved: true
        http_config:
          tls_config:
            insecure_skip_verify: true   # Skip verification for self-signed certs
          authorization:
            type: "Bearer"
            credentials: "${WEBHOOK_SECRET}"