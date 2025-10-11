#!/bin/bash

# =============================================================================
# Quick Update/Redeploy Script for WeatherAlert
# Use this for updating an existing deployment
# =============================================================================

set -e

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

APP_NAME="weatherapp"
APP_DIR="/opt/django-apps/$APP_NAME"
SERVER_IP="119.93.148.180"

echo -e "${BLUE}[INFO]${NC} Quick redeployment starting..."

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)"
    exit 1
fi

# Stop services
echo -e "${BLUE}[INFO]${NC} Stopping services..."
systemctl stop django-$APP_NAME
systemctl stop celery-$APP_NAME
systemctl stop celerybeat-$APP_NAME

# Copy updated files
echo -e "${BLUE}[INFO]${NC} Copying updated files..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -d "$PROJECT_DIR/weatheralert" ]; then
    cp -r $PROJECT_DIR/weatheralert $APP_DIR/
fi

if [ -d "$PROJECT_DIR/weatherapp" ]; then
    cp -r $PROJECT_DIR/weatherapp $APP_DIR/
fi

if [ -f "$PROJECT_DIR/requirements.txt" ]; then
    cp $PROJECT_DIR/requirements.txt $APP_DIR/
fi

# Update virtualenv dependencies
echo -e "${BLUE}[INFO]${NC} Updating dependencies..."
cd $APP_DIR
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
deactivate

# Run migrations and collect static
echo -e "${BLUE}[INFO]${NC} Running migrations..."
cd $APP_DIR
source venv/bin/activate
python manage.py migrate --noinput
python manage.py collectstatic --noinput
deactivate

# Fix permissions
chown -R django-$APP_NAME:django-$APP_NAME $APP_DIR

# Restart services
echo -e "${BLUE}[INFO]${NC} Restarting services..."
systemctl start django-$APP_NAME
systemctl start celery-$APP_NAME
systemctl start celerybeat-$APP_NAME
systemctl restart nginx

# Wait and check status
sleep 5
if systemctl is-active --quiet django-$APP_NAME; then
    echo -e "${GREEN}[SUCCESS]${NC} Application redeployed successfully!"
    echo -e "${GREEN}[SUCCESS]${NC} Available at: http://$SERVER_IP/weatherapp"
else
    echo "ERROR: Service failed to start"
    systemctl status django-$APP_NAME --no-pager
    exit 1
fi

