from fastapi import FastAPI, Request
import requests
import os
import uvicorn
from dotenv import load_dotenv
load_dotenv()
import os

app = FastAPI()

WHATSAPP_TOKEN = os.environ.get("WHATSAPP_TOKEN")
WHATSAPP_NUMBER = os.environ.get("WHATSAPP_NUMBER")
WHATSAPP_PHONE_ID = os.environ.get("WHATSAPP_PHONE_ID")

@app.post("/alert")
async def alert(request: Request):
    data = await request.json()
    alert_name = data.get("alerts", [{}])[0].get("labels", {}).get("alertname", "Unknown")
    message = f"Alert triggered: {alert_name}"

    payload = {
        "messaging_product": "whatsapp",
        "to": WHATSAPP_NUMBER,
        "type": "template",
        "template": {
            "name": "hello_world",
            "language": {"code": "en_US"}
        }
    }


    headers = {
        "Authorization": f"Bearer {WHATSAPP_TOKEN}",
        "Content-Type": "application/json"
    }

    try:
        response = requests.post(
            f"https://graph.facebook.com/v22.0/{WHATSAPP_PHONE_ID}/messages",
            json=payload,
            headers=headers
        )
        response.raise_for_status()  # Raises error if status != 2xx
        return {"status": "ok", "whatsapp_response": response.json()}
    except requests.exceptions.RequestException as e:
        return {"status": "error", "details": str(e), "whatsapp_response": getattr(e.response, "text", None)}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=5000)
