# Jetson Monitoring Dashboard

This repository contains scripts and Docker Compose configuration for monitoring a Jetson device using Prometheus, Grafana, and Alertmanager.

## Features

- Real-time system monitoring
- GPU and CPU usage tracking
- Memory and storage metrics
- Temperature and power monitoring
- Alerting system with Alertmanager
- Beautiful dashboards with Grafana

## Prerequisites

- NVIDIA Jetson Device
- Docker installed
- Docker Compose installed

## Getting Started


### 1. Clone the repository
```bash
git clone https://github.com/WiseVision-AI-Tech/Models-Monitor.git
cd Models-Monitor
```
### 2. Fix script permissions
```bash
chmod +x scripts/fix_permissions.sh
./scripts/fix_permissions.sh
```
### 3. Start the monitoring stack
```bash
docker compose up -d
```