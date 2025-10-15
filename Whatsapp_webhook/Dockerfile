FROM python:3.11-slim
WORKDIR /app
COPY whatsapp_webhook.py /app
RUN pip install fastapi uvicorn requests
EXPOSE 5000
CMD ["uvicorn", "whatsapp_webhook:app", "--host", "0.0.0.0", "--port", "5000"]
