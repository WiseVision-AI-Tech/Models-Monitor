#!/usr/bin/env python3
"""
Telegram Webhook Service for Alertmanager
One alert → one Telegram message → correct template
"""

import os
import logging
import requests
from flask import Flask, request, jsonify
from datetime import datetime
from typing import Dict

# ---------------- LOGGING ----------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger("telegram-webhook")

app = Flask(__name__)

# ---------------- CONFIG ----------------
TELEGRAM_ENABLED = os.getenv("TELEGRAM_ENABLED", "true").lower() == "true"
TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "")
TELEGRAM_CHAT_IDS = [
    cid.strip()
    for cid in os.getenv("TELEGRAM_CHAT_IDS", "").split(",")
    if cid.strip()
]

SEND_RESOLVED = os.getenv("SEND_RESOLVED_ALERTS", "false").lower() == "true"


def telegram_url() -> str:
    return f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"


# ---------------- TEMPLATES ----------------
TEMPLATES = {

    "HighRAMUsage": """ *HIGH RAM USAGE ALERT*

*Instance:* {instance}
*Severity:* {severity}
*RAM Usage:* {value}
*Time:* {time}

{description}

*Status:* {status}
""",

    "HighGPUUsage": """ *HIGH GPU USAGE ALERT*

*Instance:* {instance}
*Severity:* {severity}
*GPU Usage:* {value}
*Time:* {time}

{description}

*Status:* {status}
""",

    "CPUCoreImbalance": """ *CPU CORE IMBALANCE ALERT*

*Instance:* {instance}
*Severity:* {severity}
*Imbalance:* {value}
*Time:* {time}

{description}

*Status:* {status}
""",

    "HighCPUTemperature": """ *HIGH CPU TEMPERATURE ALERT*

*Instance:* {instance}
*Severity:* {severity}
*CPU Temperature:* {value}
*Time:* {time}

{description}

*Status:* {status}
"""
}


# ---------------- HELPERS ----------------
def format_time(ts: str) -> str:
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).strftime(
            "%Y-%m-%d %H:%M:%S UTC"
        )
    except Exception:
        return ts


def send_telegram(text: str) -> None:
    if not TELEGRAM_ENABLED or not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_IDS:
        logger.error("Telegram not configured correctly")
        return

    for chat_id in TELEGRAM_CHAT_IDS:
        requests.post(
            telegram_url(),
            json={
                "chat_id": chat_id,
                "text": text,
                "parse_mode": "Markdown"
            },
            timeout=10
        )


# ---------------- ROUTES ----------------
@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"}), 200


@app.route("/webhook", methods=["POST"])
def webhook():
    data = request.get_json()
    alerts = data.get("alerts", [])

    logger.info("Received %d alert(s)", len(alerts))

    for alert in alerts:
        labels = alert.get("labels", {})
        annotations = alert.get("annotations", {})

        alert_name = labels.get("alertname", "Unknown")
        alert_status = alert.get("status", "unknown")

        if alert_status == "resolved" and not SEND_RESOLVED:
            continue

        template = TEMPLATES.get(alert_name)
        if not template:
            logger.warning("No template for alert: %s", alert_name)
            continue

        message = template.format(
            instance=labels.get("instance", "unknown"),
            severity=labels.get("severity", "unknown").upper(),
            value=annotations.get("value", "N/A"),
            description=annotations.get("description", "No description"),
            time=format_time(alert.get("startsAt", "")),
            status=alert_status.upper()
        )

        send_telegram(message)
        logger.info("Sent alert: %s", alert_name)

    return jsonify({"status": "processed"}), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
