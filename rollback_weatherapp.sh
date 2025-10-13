#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Rollback Script for WeatherApp
# =============================================================================

APP_NAME="weatherapp"
SERVICE_NAME="${APP_NAME}"
NGINX_SITE="${APP_NAME}"

echo "🔄 Rolling back WeatherApp deployment..."

# Stop and disable service
echo "Stopping WeatherApp service..."
sudo systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
sudo systemctl disable "${SERVICE_NAME}" 2>/dev/null || true

# Remove systemd service file
echo "Removing systemd service..."
sudo rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
sudo systemctl daemon-reload

# Remove Nginx configuration
echo "Removing Nginx configuration..."
sudo rm -f "/etc/nginx/sites-enabled/${NGINX_SITE}"
sudo rm -f "/etc/nginx/sites-available/${NGINX_SITE}"

# Restore default Nginx site
sudo ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default 2>/dev/null || true

# Reload Nginx
sudo nginx -t && sudo systemctl reload nginx

echo "✅ Rollback completed!"
echo "WeatherApp has been removed from the system."
