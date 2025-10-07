#!/bin/bash
# Script to add a new Python application to the multi-app server

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 <app_name> <port> <app_path>"
    echo ""
    echo "Arguments:"
    echo "  app_name  - Name of the application (e.g., myapp)"
    echo "  port      - Port number for the application (e.g., 8002)"
    echo "  app_path  - Path to the application code"
    echo ""
    echo "Example:"
    echo "  $0 myapp 8002 /path/to/myapp"
    echo ""
    echo "This will make the app accessible at: http://192.168.3.5/myapp/"
}

# Check arguments
if [ $# -ne 3 ]; then
    print_error "Invalid number of arguments!"
    show_usage
    exit 1
fi

APP_NAME="$1"
PORT="$2"
APP_PATH="$3"
APP_DIR="/var/www/apps/$APP_NAME"
VENV_DIR="$APP_DIR/venv"

# Validate port number
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1024 ] || [ "$PORT" -gt 65535 ]; then
    print_error "Invalid port number. Please use a port between 1024 and 65535."
    exit 1
fi

# Check if app path exists
if [ ! -d "$APP_PATH" ]; then
    print_error "Application path $APP_PATH does not exist!"
    exit 1
fi

print_status "Adding new application: $APP_NAME on port $PORT"

# Create app directory
print_status "Creating application directory..."
sudo mkdir -p "$APP_DIR"
sudo chown -R www-data:www-data "$APP_DIR"
sudo chmod -R 755 "$APP_DIR"

# Copy application code
print_status "Copying application code..."
sudo cp -r "$APP_PATH"/* "$APP_DIR/"
sudo chown -R www-data:www-data "$APP_DIR"

# Create virtual environment
print_status "Creating Python virtual environment..."
sudo python3 -m venv "$VENV_DIR"
sudo chown -R www-data:www-data "$VENV_DIR"

# Activate virtual environment and install dependencies
print_status "Installing dependencies..."
sudo -u www-data bash -c "source $VENV_DIR/bin/activate && pip install --upgrade pip"

if [ -f "$APP_DIR/requirements.txt" ]; then
    sudo -u www-data bash -c "source $VENV_DIR/bin/activate && pip install -r $APP_DIR/requirements.txt"
else
    print_warning "No requirements.txt found. Installing basic dependencies..."
    sudo -u www-data bash -c "source $VENV_DIR/bin/activate && pip install gunicorn django"
fi

# Create gunicorn configuration
print_status "Creating Gunicorn configuration..."
sudo tee "$APP_DIR/gunicorn.conf.py" > /dev/null << EOF
import multiprocessing

bind = "127.0.0.1:$PORT"
workers = multiprocessing.cpu_count() * 2 + 1
worker_class = "sync"
worker_connections = 1000
max_requests = 1000
max_requests_jitter = 100
timeout = 30
keepalive = 2

# Logging
accesslog = "/var/log/$APP_NAME/access.log"
errorlog = "/var/log/$APP_NAME/error.log"
loglevel = "info"

# Process naming
proc_name = "$APP_NAME"

# Server mechanics
daemon = False
pidfile = "/var/run/$APP_NAME.pid"
user = "www-data"
group = "www-data"
tmp_upload_dir = None
EOF

# Create log directory
print_status "Creating log directory..."
sudo mkdir -p "/var/log/$APP_NAME"
sudo chown -R www-data:www-data "/var/log/$APP_NAME"

# Create Supervisor configuration
print_status "Creating Supervisor configuration..."
sudo tee "/etc/supervisor/conf.d/$APP_NAME.conf" > /dev/null << EOF
[program:$APP_NAME]
command=$VENV_DIR/bin/gunicorn --config $APP_DIR/gunicorn.conf.py $APP_NAME.wsgi:application
directory=$APP_DIR
user=www-data
group=www-data
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/$APP_NAME/gunicorn.log
environment=DJANGO_SETTINGS_MODULE="$APP_NAME.settings"
EOF

# Update Nginx configuration
print_status "Updating Nginx configuration..."

# Backup current nginx config
sudo cp /etc/nginx/sites-available/weatherapp /etc/nginx/sites-available/weatherapp.backup.$(date +%Y%m%d_%H%M%S)

# Read current nginx config and add new upstream and location
CURRENT_CONFIG="/etc/nginx/sites-available/weatherapp"
TEMP_CONFIG="/tmp/nginx_config_$$"

# Add upstream definition
sudo sed -i "/^upstream weatherapp {/a\\nupstream $APP_NAME {\n    server 127.0.0.1:$PORT;\n}" "$CURRENT_CONFIG"

# Add location block
sudo sed -i "/^    # Default location for other apps/i\\n    # $APP_NAME app\n    location /$APP_NAME/ {\n        proxy_pass http://$APP_NAME/;\n        proxy_set_header Host \$host;\n        proxy_set_header X-Real-IP \$remote_addr;\n        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;\n        proxy_set_header X-Forwarded-Proto \$scheme;\n        \n        # Handle static files\n        location /$APP_NAME/static/ {\n            alias $APP_DIR/staticfiles/;\n            expires 1y;\n            add_header Cache-Control \"public, immutable\";\n        }\n        \n        # Handle media files\n        location /$APP_NAME/media/ {\n            alias $APP_DIR/media/;\n            expires 1y;\n            add_header Cache-Control \"public\";\n        }\n    }\n" "$CURRENT_CONFIG"

# Test nginx configuration
print_status "Testing Nginx configuration..."
sudo nginx -t

# Update Supervisor
print_status "Updating Supervisor configuration..."
sudo supervisorctl reread
sudo supervisorctl update

# Start the new application
print_status "Starting $APP_NAME application..."
sudo supervisorctl start "$APP_NAME"

# Reload Nginx
print_status "Reloading Nginx..."
sudo systemctl reload nginx

# Check status
print_status "Checking application status..."
sudo supervisorctl status "$APP_NAME"

print_status "Application $APP_NAME added successfully!"
print_status "Your application is accessible at: http://192.168.3.5/$APP_NAME/"

print_status "Useful commands for $APP_NAME:"
echo "  Check status: sudo supervisorctl status $APP_NAME"
echo "  View logs: sudo tail -f /var/log/$APP_NAME/gunicorn.log"
echo "  Restart app: sudo supervisorctl restart $APP_NAME"
echo "  Stop app: sudo supervisorctl stop $APP_NAME"
echo "  Start app: sudo supervisorctl start $APP_NAME"

print_status "To add more applications, run this script again with different parameters."
