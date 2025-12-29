#!/usr/bin/env python3
"""
Telegram Webhook Service for Alertmanager
Receives alerts from Prometheus Alertmanager and sends Telegram messages
Uses Telegram Bot API (completely free!)
"""

import os
import json
import logging
import requests
from flask import Flask, request, jsonify
from datetime import datetime
from typing import Dict, List, Optional
import re

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Configuration from environment
TELEGRAM_ENABLED = os.getenv('TELEGRAM_ENABLED', 'true').lower() == 'true'
TELEGRAM_BOT_TOKEN = os.getenv('TELEGRAM_BOT_TOKEN', '')
TELEGRAM_CHAT_IDS = [cid.strip() for cid in os.getenv('TELEGRAM_CHAT_IDS', '').split(',') if cid.strip()] if os.getenv('TELEGRAM_CHAT_IDS') else []

def get_telegram_api_url():
    """Get Telegram API URL with current bot token."""
    return f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}"

# Alert template directory
TEMPLATE_DIR = '/app/templates'


def load_template(alert_name: str, alert_type: str = 'default') -> str:
    """Load alert template from file or return default."""
    template_path = os.path.join(TEMPLATE_DIR, f"{alert_name}_{alert_type}.tmpl")
    
    if os.path.exists(template_path):
        try:
            with open(template_path, 'r', encoding='utf-8') as f:
                return f.read()
        except Exception as e:
            logger.warning(f"Failed to load template {template_path}: {e}")
    
    # Return default template based on alert type
    return get_default_template(alert_name, alert_type)


def get_default_template(alert_name: str, alert_type: str) -> str:
    """Get default template for an alert."""
    # Try to match by alert name first
    defaults = {
        'HighTemperature': """ *High Temperature Alert*

*Alert:* {{ alertname }}
*Instance:* {{ instance }}
*Severity:* {{ severity }}
*Temperature:* {{ value }}°C
*Time:* {{ startsAt }}

{{ description }}

*Status:* {{ status }}""",

        'CPUCoreImbalance': """ *CPU Core Imbalance Alert*

*Alert:* {{ alertname }}
*Instance:* {{ instance }}
*Severity:* {{ severity }}
*Core Usage:* {{ value }}%
*Time:* {{ startsAt }}

{{ description }}

*Status:* {{ status }}""",

        'HighGPUUsage': """ *High GPU Usage Alert*

*Alert:* {{ alertname }}
*Instance:* {{ instance }}
*Severity:* {{ severity }}
*GPU Usage:* {{ value }}%
*Time:* {{ startsAt }}

{{ description }}

*Status:* {{ status }}""",

        'HighRAMUsage': """ *High RAM Usage Alert*

*Alert:* {{ alertname }}
*Instance:* {{ instance }}
*Severity:* {{ severity }}
*RAM Usage:* {{ value }}
*Time:* {{ startsAt }}

{{ description }}

*Status:* {{ status }}"""
    }
    
    # Try alert name first
    if alert_name in defaults:
        return defaults[alert_name]
    
    # Then try by alert type
    type_defaults = {
        'temperature': defaults['HighTemperature'],
        'cpu': defaults['CPUCoreImbalance'],
        'gpu': defaults['HighGPUUsage'],
        'ram': defaults['HighRAMUsage']
    }
    
    if alert_type in type_defaults:
        return type_defaults[alert_type]
    
    # Generic default
    return """*Alert: {{ alertname }}*

*Instance:* {{ instance }}
*Severity:* {{ severity }}
*Value:* {{ value }}
*Time:* {{ startsAt }}

{{ description }}

*Status:* {{ status }}"""


def render_template(template: str, alert: Dict) -> str:
    """Render template with alert data."""
    message = template
    
    # Extract alert data
    labels = alert.get('labels', {})
    annotations = alert.get('annotations', {})
    status = alert.get('status', 'unknown')
    starts_at = alert.get('startsAt', datetime.utcnow().isoformat())
    
    # Extract value from description or annotations
    value = 'N/A'
    description = annotations.get('description', annotations.get('summary', 'No description'))
    
    # Try to extract numeric value from description (e.g., "temperature is 85°C" or "usage is 95%")
    value_match = re.search(r'(\d+(?:\.\d+)?)\s*(?:°C|%|MHz|MB)', description, re.IGNORECASE)
    if value_match:
        value = value_match.group(1)
        # Add unit if found
        unit_match = re.search(r'(\d+(?:\.\d+)?)\s*(°C|%|MHz|MB)', description, re.IGNORECASE)
        if unit_match:
            value = f"{value}{unit_match.group(2)}"
    
    # Also check if value is directly in annotations
    if 'value' in annotations:
        value = annotations['value']
    
    # Format timestamp
    try:
        dt = datetime.fromisoformat(starts_at.replace('Z', '+00:00'))
        formatted_time = dt.strftime('%Y-%m-%d %H:%M:%S UTC')
    except:
        formatted_time = starts_at
    
    # Replace template variables
    replacements = {
        '{{ alertname }}': labels.get('alertname', 'Unknown'),
        '{{ instance }}': labels.get('instance', labels.get('exported_instance', 'Unknown')),
        '{{ severity }}': labels.get('severity', 'unknown').upper(),
        '{{ value }}': str(value),
        '{{ startsAt }}': formatted_time,
        '{{ description }}': description,
        '{{ summary }}': annotations.get('summary', ''),
        '{{ status }}': status.upper(),
    }
    
    for key, val in replacements.items():
        message = message.replace(key, str(val))
    
    # Remove any remaining template variables
    message = re.sub(r'\{\{[^}]+\}\}', 'N/A', message)
    
    return message.strip()


def escape_markdown_v2(text: str) -> str:
    """Escape special characters for Telegram MarkdownV2."""
    # Characters that need escaping in MarkdownV2
    special_chars = ['_', '*', '[', ']', '(', ')', '~', '`', '>', '#', '+', '-', '=', '|', '{', '}', '.', '!']
    for char in special_chars:
        text = text.replace(char, f'\\{char}')
    return text


def send_telegram_message(message: str, chat_ids: Optional[List[str]] = None) -> bool:
    """Send Telegram message using Bot API."""
    if not TELEGRAM_ENABLED:
        logger.info("Telegram alerts are disabled")
        return False
    
    if not TELEGRAM_BOT_TOKEN:
        logger.error("Telegram bot token not configured")
        return False
    
    # Get chat IDs
    if chat_ids is None:
        chat_ids = [cid.strip() for cid in TELEGRAM_CHAT_IDS if cid.strip()]
    
    if not chat_ids:
        logger.error("No Telegram chat IDs configured")
        return False
    
    url = f"{get_telegram_api_url()}/sendMessage"
    success = True
    
    for chat_id in chat_ids:
        try:
            # Use Markdown for formatting, but don't escape since templates already use * for bold
            data = {
                'chat_id': chat_id.strip(),
                'text': message,
                'parse_mode': 'Markdown'  # Support for *bold*, _italic_, etc.
            }
            
            response = requests.post(url, json=data, timeout=10)
            response.raise_for_status()
            
            result = response.json()
            if result.get('ok'):
                logger.info(f"Telegram message sent to chat {chat_id}")
            else:
                logger.error(f"Telegram API error: {result.get('description', 'Unknown error')}")
                # Try sending without parse_mode if Markdown fails
                if 'parse' in result.get('description', '').lower():
                    try:
                        data_no_parse = {
                            'chat_id': chat_id.strip(),
                            'text': message.replace('*', '').replace('_', '')
                        }
                        response2 = requests.post(url, json=data_no_parse, timeout=10)
                        response2.raise_for_status()
                        if response2.json().get('ok'):
                            logger.info(f"Telegram message sent to chat {chat_id} (without formatting)")
                            continue
                    except:
                        pass
                success = False
                
        except Exception as e:
            logger.error(f"Failed to send Telegram message to {chat_id}: {e}")
            success = False
    
    return success


@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint."""
    return jsonify({
        'status': 'healthy',
        'provider': 'telegram',
        'enabled': TELEGRAM_ENABLED,
        'bot_configured': bool(TELEGRAM_BOT_TOKEN),
        'chat_ids_count': len(TELEGRAM_CHAT_IDS)
    }), 200


@app.route('/webhook', methods=['POST'])
def webhook():
    """Receive alerts from Alertmanager and send WhatsApp messages."""
    try:
        data = request.get_json()
        
        if not data:
            logger.warning("Received empty request")
            return jsonify({'error': 'Invalid request'}), 400
        
        # Alertmanager sends alerts in this format:
        # {
        #   "version": "4",
        #   "groupKey": "...",
        #   "status": "firing|resolved",
        #   "receiver": "...",
        #   "alerts": [...]
        # }
        
        alerts = data.get('alerts', [])
        status = data.get('status', 'unknown')
        
        logger.info(f"Received {len(alerts)} alert(s) with status: {status}")
        
        # Process each alert
        for alert in alerts:
            labels = alert.get('labels', {})
            alert_name = labels.get('alertname', 'Unknown')
            severity = labels.get('severity', 'info')
            
            # Skip resolved alerts if configured to only send firing
            if status == 'resolved' and os.getenv('SEND_RESOLVED_ALERTS', 'false').lower() != 'true':
                logger.info(f"Skipping resolved alert: {alert_name}")
                continue
            
            # Determine template type based on alert name or alert_type label
            alert_type_label = labels.get('alert_type', '')
            template_type = 'default'
            
            if alert_type_label:
                template_type = alert_type_label
            elif 'Temperature' in alert_name or 'temperature' in alert_name.lower():
                template_type = 'temperature'
            elif 'CPU' in alert_name or 'cpu' in alert_name.lower() or 'Core' in alert_name:
                template_type = 'cpu'
            elif 'GPU' in alert_name or 'gpu' in alert_name.lower():
                template_type = 'gpu'
            elif 'RAM' in alert_name or 'ram' in alert_name.lower() or 'Ram' in alert_name:
                template_type = 'ram'
            
            # Load and render template
            template = load_template(alert_name, template_type)
            message = render_template(template, alert)
            
            # Send Telegram message
            if send_telegram_message(message):
                logger.info(f"Successfully sent alert: {alert_name}")
            else:
                logger.error(f"Failed to send alert: {alert_name}")
        
        return jsonify({'status': 'processed', 'alerts': len(alerts)}), 200
        
    except Exception as e:
        logger.error(f"Error processing webhook: {e}", exc_info=True)
        return jsonify({'error': str(e)}), 500


if __name__ == '__main__':
    port = int(os.getenv('PORT', '5000'))
    debug = os.getenv('DEBUG', 'false').lower() == 'true'
    
    logger.info(f"Starting Telegram webhook service on port {port}")
    logger.info(f"Provider: Telegram, Enabled: {TELEGRAM_ENABLED}")
    logger.info(f"Bot token configured: {bool(TELEGRAM_BOT_TOKEN)}")
    logger.info(f"Chat IDs: {len(TELEGRAM_CHAT_IDS)} configured")
    
    app.run(host='0.0.0.0', port=port, debug=debug)

