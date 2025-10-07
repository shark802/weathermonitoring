#!/bin/bash
# Application deployment script

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

# Configuration
APP_NAME="weatherapp"
APP_DIR="/var/www/apps/$APP_NAME"
VENV_DIR="$APP_DIR/venv"
LOG_DIR="/var/log/$APP_NAME"

print_status "Starting deployment of $APP_NAME..."

# Check if app directory exists
if [ ! -d "$APP_DIR" ]; then
    print_error "Application directory $APP_DIR does not exist!"
    print_status "Please run setup_environment.sh first or create the directory manually."
    exit 1
fi

cd "$APP_DIR"

# Create virtual environment if it doesn't exist
if [ ! -d "$VENV_DIR" ]; then
    print_status "Creating Python virtual environment..."
    python3 -m venv "$VENV_DIR"
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

# Set proper permissions
print_status "Setting file permissions..."
sudo chown -R www-data:www-data "$APP_DIR"
sudo chmod -R 755 "$APP_DIR"

# Create .env file if it doesn't exist
if [ ! -f "$APP_DIR/.env" ]; then
    print_warning ".env file not found. Creating template..."
    cat > "$APP_DIR/.env" << EOF
# Django Settings
SECRET_KEY=your-super-secret-key-here
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

# Set Django settings module
export DJANGO_SETTINGS_MODULE=weatheralert.settings

# Run Django migrations
print_status "Running Django migrations..."
python manage.py makemigrations
python manage.py migrate

# Create superuser if it doesn't exist
print_status "Checking for superuser..."
if ! python manage.py shell -c "from django.contrib.auth import get_user_model; User = get_user_model(); print('Superuser exists' if User.objects.filter(is_superuser=True).exists() else 'No superuser found')" | grep -q "Superuser exists"; then
    print_warning "No superuser found. You may need to create one manually:"
    echo "python manage.py createsuperuser"
fi

# Collect static files
print_status "Collecting static files..."
python manage.py collectstatic --noinput

# Create gunicorn configuration
print_status "Creating Gunicorn configuration..."
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

# Create Supervisor configuration
print_status "Creating Supervisor configuration..."
sudo tee /etc/supervisor/conf.d/weatherapp.conf > /dev/null << 'EOF'
[program:weatherapp]
command=/var/www/apps/weatherapp/venv/bin/gunicorn --config /var/www/apps/weatherapp/gunicorn.conf.py weatheralert.wsgi:application
directory=/var/www/apps/weatherapp
user=www-data
group=www-data
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/weatherapp/gunicorn.log
environment=DJANGO_SETTINGS_MODULE="weatheralert.settings"

[program:weatherapp-celery-worker]
command=/var/www/apps/weatherapp/venv/bin/celery -A weatheralert worker --loglevel=info
directory=/var/www/apps/weatherapp
user=www-data
group=www-data
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/weatherapp/celery-worker.log
environment=DJANGO_SETTINGS_MODULE="weatheralert.settings"

[program:weatherapp-celery-beat]
command=/var/www/apps/weatherapp/venv/bin/celery -A weatheralert beat --loglevel=info
directory=/var/www/apps/weatherapp
user=www-data
group=www-data
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/weatherapp/celery-beat.log
environment=DJANGO_SETTINGS_MODULE="weatheralert.settings"
EOF

# Create Nginx configuration
print_status "Creating Nginx configuration..."
sudo tee /etc/nginx/sites-available/weatherapp > /dev/null << 'EOF'
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
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Handle static files
        location /weatherapp/static/ {
            alias /var/www/apps/weatherapp/staticfiles/;
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
        
        # Handle media files
        location /weatherapp/media/ {
            alias /var/www/apps/weatherapp/media/;
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

# Enable Nginx site
print_status "Enabling Nginx site..."
sudo ln -sf /etc/nginx/sites-available/weatherapp /etc/nginx/sites-enabled/

# Test configurations
print_status "Testing configurations..."
sudo nginx -t
sudo supervisorctl reread

# Update Supervisor
print_status "Updating Supervisor configuration..."
sudo supervisorctl update

# Start services
print_status "Starting application services..."
sudo supervisorctl start weatherapp
sudo supervisorctl start weatherapp-celery-worker
sudo supervisorctl start weatherapp-celery-beat

# Reload Nginx
print_status "Reloading Nginx..."
sudo systemctl reload nginx

# Check service status
print_status "Checking service status..."
sudo supervisorctl status

print_status "Deployment completed successfully!"
print_status "Your application should be accessible at: http://192.168.3.5/weatherapp/"
print_status "Health check: http://192.168.3.5/health"

print_status "Useful commands:"
echo "  Check status: sudo supervisorctl status"
echo "  View logs: sudo tail -f /var/log/weatherapp/gunicorn.log"
echo "  Restart app: sudo supervisorctl restart weatherapp"
echo "  Check nginx: sudo nginx -t && sudo systemctl status nginx"
