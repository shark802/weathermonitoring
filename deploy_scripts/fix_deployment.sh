#!/bin/bash
# Fix deployment script - corrects paths and configurations

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
APP_NAME="weatherapp"
APP_DIR="/home/bccbsis-py-admin/$APP_NAME"
VENV_DIR="$APP_DIR/venv"

print_header "Fixing Weather Application Deployment"
echo "This script will fix the deployment configuration to use the correct paths."
echo ""

# Check if running as correct user
if [ "$USER" != "bccbsis-py-admin" ]; then
    print_warning "Expected user 'bccbsis-py-admin', but running as '$USER'"
    print_status "Continuing with current user..."
fi

# Check if app directory exists
if [ ! -d "$APP_DIR" ]; then
    print_error "Application directory $APP_DIR does not exist!"
    print_status "Please ensure the weatherapp directory is in /home/bccbsis-py-admin/"
    exit 1
fi

print_status "Application directory found: $APP_DIR"

# Step 1: Stop existing services
print_header "Step 1: Stopping existing services"
sudo supervisorctl stop weatherapp 2>/dev/null || true
sudo supervisorctl stop weatherapp-celery-worker 2>/dev/null || true
sudo supervisorctl stop weatherapp-celery-beat 2>/dev/null || true

# Step 2: Fix permissions
print_header "Step 2: Fixing permissions"
sudo chown -R www-data:www-data "$APP_DIR"
sudo chmod -R 755 "$APP_DIR"

# Step 3: Update Supervisor configuration
print_header "Step 3: Updating Supervisor configuration"
sudo tee /etc/supervisor/conf.d/weatherapp.conf > /dev/null << EOF
[program:weatherapp]
command=$VENV_DIR/bin/gunicorn --config $APP_DIR/gunicorn.conf.py weatheralert.wsgi:application
directory=$APP_DIR
user=www-data
group=www-data
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/weatherapp/gunicorn.log
environment=DJANGO_SETTINGS_MODULE="weatheralert.settings"

[program:weatherapp-celery-worker]
command=$VENV_DIR/bin/celery -A weatheralert worker --loglevel=info
directory=$APP_DIR
user=www-data
group=www-data
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/weatherapp/celery-worker.log
environment=DJANGO_SETTINGS_MODULE="weatheralert.settings"

[program:weatherapp-celery-beat]
command=$VENV_DIR/bin/celery -A weatheralert beat --loglevel=info
directory=$APP_DIR
user=www-data
group=www-data
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/weatherapp/celery-beat.log
environment=DJANGO_SETTINGS_MODULE="weatheralert.settings"
EOF

# Step 4: Update Nginx configuration
print_header "Step 4: Updating Nginx configuration"
sudo tee /etc/nginx/sites-available/weatherapp > /dev/null << EOF
# Upstream for weather app
upstream weatherapp {
    server 127.0.0.1:8001;
}

# Main server block
server {
    listen 80;
    server_name 192.168.3.5;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;

    # Weather app location
    location /weatherapp/ {
        proxy_pass http://weatherapp/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Handle static files
        location /weatherapp/static/ {
            alias $APP_DIR/staticfiles/;
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
        
        # Handle media files
        location /weatherapp/media/ {
            alias $APP_DIR/media/;
            expires 1y;
            add_header Cache-Control "public";
        }
    }

    # Default location for other apps
    location / {
        return 200 'Welcome to Multi-App Server - Weather App available at /weatherapp/';
        add_header Content-Type text/plain;
    }

    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF

# Step 5: Test configurations
print_header "Step 5: Testing configurations"
sudo nginx -t
if [ $? -eq 0 ]; then
    print_status "Nginx configuration is valid"
else
    print_error "Nginx configuration has errors!"
    exit 1
fi

# Step 6: Update Supervisor
print_header "Step 6: Updating Supervisor"
sudo supervisorctl reread
sudo supervisorctl update

# Step 7: Start services
print_header "Step 7: Starting services"
sudo supervisorctl start weatherapp
sudo supervisorctl start weatherapp-celery-worker
sudo supervisorctl start weatherapp-celery-beat

# Step 8: Reload Nginx
print_header "Step 8: Reloading Nginx"
sudo systemctl reload nginx

# Step 9: Check status
print_header "Step 9: Checking service status"
sudo supervisorctl status

# Step 10: Test endpoints
print_header "Step 10: Testing endpoints"
sleep 5  # Wait for services to start

# Test health endpoint
if curl -s -o /dev/null -w "%{http_code}" "http://192.168.3.5/health" | grep -q "200"; then
    print_status "Health check: OK"
else
    print_warning "Health check: Failed"
fi

# Test weather app endpoint
if curl -s -o /dev/null -w "%{http_code}" "http://192.168.3.5/weatherapp/" | grep -q "200"; then
    print_status "Weather app: OK"
else
    print_warning "Weather app: Failed (this might be normal if Django needs setup)"
fi

# Step 11: Show logs if there are issues
print_header "Step 11: Checking logs"
if ! sudo supervisorctl status weatherapp | grep -q "RUNNING"; then
    print_warning "Weather app is not running. Checking logs..."
    sudo tail -n 20 /var/log/weatherapp/gunicorn.log
fi

print_header "Deployment Fix Complete!"
echo ""
print_status "Your application should now be accessible at:"
echo "  Main URL: http://192.168.3.5/weatherapp/"
echo "  Health Check: http://192.168.3.5/health"
echo ""

print_status "If the weather app is still not working, you may need to:"
echo "1. Check the logs: sudo tail -f /var/log/weatherapp/gunicorn.log"
echo "2. Run Django migrations: cd $APP_DIR && source venv/bin/activate && python manage.py migrate"
echo "3. Collect static files: python manage.py collectstatic --noinput"
echo "4. Create a superuser: python manage.py createsuperuser"
echo ""

print_status "Useful commands:"
echo "  Check status: sudo supervisorctl status"
echo "  View logs: sudo tail -f /var/log/weatherapp/gunicorn.log"
echo "  Restart app: sudo supervisorctl restart weatherapp"
echo "  Check nginx: sudo nginx -t && sudo systemctl status nginx"
