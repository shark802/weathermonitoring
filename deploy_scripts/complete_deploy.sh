#!/bin/bash
# Complete deployment script for weather application
# This script handles the current server setup and deploys correctly

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
LOG_DIR="/var/log/$APP_NAME"

print_header "Complete Weather Application Deployment"
echo "This script will deploy the weather application with correct paths and configurations."
echo ""

# Check if running as correct user
if [ "$USER" != "bccbsis-py-admin" ]; then
    print_warning "Expected user 'bccbsis-py-admin', but running as '$USER'"
    print_status "Continuing with current user..."
fi

# Step 1: Check if application exists
print_header "Step 1: Checking application directory"
if [ ! -d "$APP_DIR" ]; then
    print_error "Application directory $APP_DIR does not exist!"
    print_status "Please ensure the weatherapp directory is in /home/bccbsis-py-admin/"
    print_status "You can copy it there with:"
    echo "  sudo cp -r /path/to/your/weatherapp /home/bccbsis-py-admin/"
    exit 1
fi

print_status "Application directory found: $APP_DIR"

# Step 2: Stop any existing services and clean up
print_header "Step 2: Stopping existing services and cleaning up"
sudo supervisorctl stop weatherapp 2>/dev/null || true
sudo supervisorctl stop weatherapp-celery-worker 2>/dev/null || true
sudo supervisorctl stop weatherapp-celery-beat 2>/dev/null || true

# Remove old supervisor configuration to ensure clean start
sudo rm -f /etc/supervisor/conf.d/weatherapp.conf

# Remove old nginx site to ensure clean configuration
sudo rm -f /etc/nginx/sites-enabled/weatherapp
sudo rm -f /etc/nginx/sites-available/weatherapp

# Step 3: Set up Python environment
print_header "Step 3: Setting up Python environment"
cd "$APP_DIR"

# Check if we're in the right directory
if [ ! -f "manage.py" ]; then
    print_error "manage.py not found in $APP_DIR. Please ensure this is a Django project."
    exit 1
fi

# Create virtual environment if it doesn't exist
if [ ! -d "$VENV_DIR" ]; then
    print_status "Creating Python virtual environment..."
    python3 -m venv "$VENV_DIR"
    if [ $? -ne 0 ]; then
        print_error "Failed to create virtual environment"
        exit 1
    fi
else
    print_status "Virtual environment already exists, using existing one"
fi

# Activate virtual environment
print_status "Activating virtual environment..."
source "$VENV_DIR/bin/activate"

# Upgrade pip
print_status "Upgrading pip..."
pip install --upgrade pip

# Install dependencies
print_status "Installing Python dependencies..."
if [ -f "requirements.txt" ]; then
    pip install -r requirements.txt
else
    print_error "requirements.txt not found!"
    exit 1
fi

# Install additional production dependencies
print_status "Installing production dependencies..."
pip install gunicorn psycopg2-binary

# Step 4: Set up environment variables
print_header "Step 4: Setting up environment variables"
if [ ! -f "$APP_DIR/.env" ]; then
    print_warning ".env file not found. Creating template..."
    cat > "$APP_DIR/.env" << EOF
# Django Settings
SECRET_KEY=your-super-secret-key-here-$(date +%s)
DEBUG=False
ALLOWED_HOSTS=192.168.3.5,localhost,127.0.0.1

# Database Configuration
DATABASE_URL=mysql://u520834156_uWApp2024:bIxG2Z$In#8@localhost:3306/u520834156_dbweatherApp

# Email Configuration
EMAIL_HOST=smtp.gmail.com
EMAIL_PORT=587
EMAIL_USE_TLS=True
EMAIL_HOST_USER=your-email@gmail.com
EMAIL_HOST_PASSWORD=your-app-password

# Redis Configuration
REDIS_URL=redis://localhost:6379/0

# Weather API Configuration
OPENWEATHERMAP_API_KEY=your-openweathermap-api-key
LATITUDE=10.5283
LONGITUDE=122.8338

# SMS Configuration
SMS_API_URL=https://sms.pagenet.info/api/v1/sms/send
SMS_API_KEY=your-sms-api-key
SMS_DEVICE_ID=your-device-id
EOF
    print_warning "Please edit $APP_DIR/.env with your actual configuration values!"
fi

# Step 5: Set up Django
print_header "Step 5: Setting up Django"
export DJANGO_SETTINGS_MODULE=weatheralert.settings

# Check if Django settings are valid
print_status "Checking Django configuration..."
python manage.py check
if [ $? -ne 0 ]; then
    print_error "Django configuration check failed. Please fix the issues first."
    exit 1
fi

# Run Django migrations
print_status "Running Django migrations..."
python manage.py makemigrations
if [ $? -ne 0 ]; then
    print_warning "makemigrations failed, continuing with existing migrations..."
fi

python manage.py migrate
if [ $? -ne 0 ]; then
    print_error "Database migration failed. Please check your database connection."
    exit 1
fi

# Collect static files
print_status "Collecting static files..."
python manage.py collectstatic --noinput
if [ $? -ne 0 ]; then
    print_warning "Static files collection failed, but continuing..."
fi

# Step 6: Set proper permissions
print_header "Step 6: Setting permissions"
sudo chown -R www-data:www-data "$APP_DIR"
sudo chmod -R 755 "$APP_DIR"

# Step 7: Create Gunicorn configuration
print_header "Step 7: Creating Gunicorn configuration"
cat > "$APP_DIR/gunicorn.conf.py" << 'EOF'
import multiprocessing

bind = "127.0.0.1:8001"
workers = multiprocessing.cpu_count() * 2 + 1
worker_class = "sync"
worker_connections = 1000
max_requests = 1000
max_requests_jitter = 100
timeout = 30
keepalive = 2

# Logging
accesslog = "/var/log/weatherapp/access.log"
errorlog = "/var/log/weatherapp/error.log"
loglevel = "info"

# Process naming
proc_name = "weatherapp"

# Server mechanics
daemon = False
pidfile = "/var/run/weatherapp.pid"
user = "www-data"
group = "www-data"
tmp_upload_dir = None
EOF

# Step 8: Create Supervisor configuration
print_header "Step 8: Creating Supervisor configuration"
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

# Step 9: Create Nginx configuration
print_header "Step 9: Creating Nginx configuration"
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

# Step 10: Enable Nginx site
print_header "Step 10: Enabling Nginx site"
sudo ln -sf /etc/nginx/sites-available/weatherapp /etc/nginx/sites-enabled/

# Step 11: Test configurations
print_header "Step 11: Testing configurations"
sudo nginx -t
if [ $? -eq 0 ]; then
    print_status "Nginx configuration is valid"
else
    print_error "Nginx configuration has errors!"
    exit 1
fi

# Step 12: Update Supervisor
print_header "Step 12: Updating Supervisor"
sudo supervisorctl reread
if [ $? -ne 0 ]; then
    print_error "Supervisor configuration read failed"
    exit 1
fi

sudo supervisorctl update
if [ $? -ne 0 ]; then
    print_error "Supervisor update failed"
    exit 1
fi

# Step 13: Start services
print_header "Step 13: Starting services"
sudo supervisorctl start weatherapp
if [ $? -ne 0 ]; then
    print_error "Failed to start weatherapp service"
    print_status "Checking logs for errors..."
    sudo tail -n 20 /var/log/weatherapp/gunicorn.log 2>/dev/null || true
    exit 1
fi

sudo supervisorctl start weatherapp-celery-worker
if [ $? -ne 0 ]; then
    print_warning "Failed to start celery worker, but continuing..."
fi

sudo supervisorctl start weatherapp-celery-beat
if [ $? -ne 0 ]; then
    print_warning "Failed to start celery beat, but continuing..."
fi

# Step 14: Reload Nginx
print_header "Step 14: Reloading Nginx"
sudo systemctl reload nginx

# Step 15: Check status
print_header "Step 15: Checking service status"
sudo supervisorctl status

# Step 16: Test endpoints
print_header "Step 16: Testing endpoints"
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

print_header "Deployment Complete!"
echo ""
print_status "Your application should now be accessible at:"
echo "  Main URL: http://192.168.3.5/weatherapp/"
echo "  Health Check: http://192.168.3.5/health"
echo "  Admin Panel: http://192.168.3.5/weatherapp/admin/"
echo ""

print_status "Next steps:"
echo "1. Create a superuser: cd $APP_DIR && source venv/bin/activate && python manage.py createsuperuser"
echo "2. Update the .env file with your actual configuration values"
echo "3. Test the application thoroughly"
echo ""

print_status "Useful commands:"
echo "  Check status: sudo supervisorctl status"
echo "  View logs: sudo tail -f /var/log/weatherapp/gunicorn.log"
echo "  Restart app: sudo supervisorctl restart weatherapp"
echo "  Check nginx: sudo nginx -t && sudo systemctl status nginx"
echo ""

print_status "If you encounter issues:"
echo "  Check logs: sudo tail -f /var/log/weatherapp/gunicorn.log"
echo "  Check nginx logs: sudo tail -f /var/log/nginx/error.log"
echo "  Restart services: sudo supervisorctl restart all"
