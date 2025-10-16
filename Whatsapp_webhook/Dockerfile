FROM python:3.10-slim
WORKDIR /app
COPY . /app
RUN pip install --no-cache-dir fastapi uvicorn requests python-dotenv
EXPOSE 5000
CMD ["uvicorn", "whatsapp_webhook:app", "--host", "0.0.0.0", "--port", "5000"]
