#!/bin/bash

# =============================================================================
# WeatherAlert Django Application Deployment Script
# Deploys the weatherapp to Ubuntu Server with proper configuration
# =============================================================================

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
APP_NAME="weatherapp"
APP_URL="bccweatherapp"
SERVER_IP="192.168.3.5"
BASE_DIR="/opt/django-apps"
APP_DIR="$BASE_DIR/$APP_NAME"
LOG_DIR="/var/log/django-apps/$APP_NAME"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Function to create app directory structure
create_app_structure() {
    print_status "Creating application directory structure..."
    
    mkdir -p $APP_DIR
    mkdir -p $LOG_DIR
    mkdir -p $APP_DIR/staticfiles
    mkdir -p $APP_DIR/media
    mkdir -p $APP_DIR/logs
    
    print_success "Directory structure created"
}

# Function to setup virtual environment
setup_virtualenv() {
    print_status "Setting up Python virtual environment..."
    
    cd $APP_DIR
    
    # Create virtual environment
    python3 -m venv venv
    source venv/bin/activate
    
    # Install Python dependencies
    pip install --upgrade pip
    pip install -r requirements.txt
    
    # Install additional packages if needed
    pip install gunicorn
    pip install celery[redis]
    pip install supervisor
    
    deactivate
    
    print_success "Virtual environment setup completed"
}

# Function to create environment configuration
create_env_config() {
    print_status "Creating environment configuration..."
    
    # Generate secret key
    SECRET_KEY=$(python3 -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())")
    
    # Get database credentials
    if [ -f "/etc/django-apps/${APP_NAME}_db.conf" ]; then
        source /etc/django-apps/${APP_NAME}_db.conf
    else
        print_error "Database configuration not found. Run the main deployment script first."
        exit 1
    fi
    
    # Create .env file
    cat > $APP_DIR/.env << EOF
# WeatherAlert Environment Configuration
DEBUG=False
SECRET_KEY=$SECRET_KEY
ALLOWED_HOSTS=$SERVER_IP,localhost,127.0.0.1,192.168.3.5

# Database configuration
DATABASE_URL=mysql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME

# Redis configuration
REDIS_URL=redis://localhost:6379/0
CELERY_BROKER_URL=redis://localhost:6379/0
CELERY_RESULT_BACKEND=redis://localhost:6379/0

# Email configuration
EMAIL_BACKEND=django.core.mail.backends.smtp.EmailBackend
EMAIL_HOST=smtp.gmail.com
EMAIL_PORT=587
EMAIL_USE_TLS=True
EMAIL_HOST_USER=rainalertcaps@gmail.com
EMAIL_HOST_PASSWORD=clmz izuz zphx tnrw
DEFAULT_FROM_EMAIL=WeatherAlert <rainalertcaps@gmail.com>

# SMS configuration
SMS_API_URL=https://sms.pagenet.info/api/v1/sms/send
SMS_API_KEY=6PLX3NFL2A2FLQ81RI7X6C4PJP68ANLJNYQ7XAR6
SMS_DEVICE_ID=97e8c4360d11fa51

# PhilSys QR Verification Keys
PSA_PUBLIC_KEY=
PSA_ED25519_PUBLIC_KEY=

# App settings
APP_NAME=$APP_NAME
APP_URL=http://$SERVER_IP/$APP_URL
TIME_ZONE=Asia/Manila
LANGUAGE_CODE=en-us

# Security settings
SESSION_EXPIRE_AT_BROWSER_CLOSE=False
SESSION_ENGINE=django.contrib.sessions.backends.db
SESSION_COOKIE_HTTPONLY=True
SESSION_SAVE_EVERY_REQUEST=True

# Static files
STATIC_URL=/static/
STATIC_ROOT=$APP_DIR/staticfiles
MEDIA_URL=/media/
MEDIA_ROOT=$APP_DIR/media
EOF

    chmod 600 $APP_DIR/.env
    print_success "Environment configuration created"
}

# Function to copy application files
copy_app_files() {
    print_status "Copying application files..."
    
    # Get the directory where this script is located
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
    
    # Check if we're running from within the project directory
    if [ "$(basename "$PROJECT_DIR")" = "weatherapp" ]; then
        # We're running from within the project, so copy from current directory
        print_status "Detected running from project directory, copying from current location..."
        
        # Copy Django project files from current directory
        if [ -d "weatheralert" ]; then
            cp -r weatheralert $APP_DIR/
        fi
        if [ -d "weatherapp" ]; then
            cp -r weatherapp $APP_DIR/
        fi
        if [ -d "esp32" ]; then
            cp -r esp32 $APP_DIR/
        fi
        if [ -f "manage.py" ]; then
            cp manage.py $APP_DIR/
        fi
        if [ -f "requirements.txt" ]; then
            cp requirements.txt $APP_DIR/
        fi
        if [ -f "Procfile" ]; then
            cp Procfile $APP_DIR/
        fi
        if [ -f "Procfile.dev" ]; then
            cp Procfile.dev $APP_DIR/
        fi
        
        # Copy static files
        if [ -d "staticfiles" ]; then
            cp -r staticfiles/* $APP_DIR/staticfiles/ 2>/dev/null || true
        fi
        
        # Copy media files if they exist
        if [ -d "media" ]; then
            cp -r media/* $APP_DIR/media/ 2>/dev/null || true
        fi
    else
        # We're running from outside the project, copy from project directory
        print_status "Copying from project directory: $PROJECT_DIR"
        
        # Copy Django project files
        if [ -d "$PROJECT_DIR/weatheralert" ]; then
            cp -r $PROJECT_DIR/weatheralert $APP_DIR/
        fi
        if [ -d "$PROJECT_DIR/weatherapp" ]; then
            cp -r $PROJECT_DIR/weatherapp $APP_DIR/
        fi
        if [ -d "$PROJECT_DIR/esp32" ]; then
            cp -r $PROJECT_DIR/esp32 $APP_DIR/
        fi
        if [ -f "$PROJECT_DIR/manage.py" ]; then
            cp $PROJECT_DIR/manage.py $APP_DIR/
        fi
        if [ -f "$PROJECT_DIR/requirements.txt" ]; then
            cp $PROJECT_DIR/requirements.txt $APP_DIR/
        fi
        if [ -f "$PROJECT_DIR/Procfile" ]; then
            cp $PROJECT_DIR/Procfile $APP_DIR/
        fi
        if [ -f "$PROJECT_DIR/Procfile.dev" ]; then
            cp $PROJECT_DIR/Procfile.dev $APP_DIR/
        fi
        
        # Copy static files
        if [ -d "$PROJECT_DIR/staticfiles" ]; then
            cp -r $PROJECT_DIR/staticfiles/* $APP_DIR/staticfiles/ 2>/dev/null || true
        fi
        
        # Copy media files if they exist
        if [ -d "$PROJECT_DIR/media" ]; then
            cp -r $PROJECT_DIR/media/* $APP_DIR/media/ 2>/dev/null || true
        fi
    fi
    
    print_success "Application files copied"
}

# Function to configure Django settings
configure_django() {
    print_status "Configuring Django settings..."
    
    # Create production settings file
    cat > $APP_DIR/weatheralert/settings_production.py << EOF
"""
Production settings for WeatherAlert
"""
import os
from .settings import *

# Load environment variables
from dotenv import load_dotenv
load_dotenv()

# Security settings
DEBUG = False
SECRET_KEY = os.environ.get('SECRET_KEY')
ALLOWED_HOSTS = os.environ.get('ALLOWED_HOSTS', '$SERVER_IP').split(',')

# Database configuration
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.mysql',
        'NAME': os.environ.get('DB_NAME'),
        'USER': os.environ.get('DB_USER'),
        'PASSWORD': os.environ.get('DB_PASSWORD'),
        'HOST': os.environ.get('DB_HOST', 'localhost'),
        'PORT': os.environ.get('DB_PORT', '3306'),
        'OPTIONS': {
            'charset': 'utf8mb4',
        },
    }
}

# Redis configuration
CELERY_BROKER_URL = os.environ.get('REDIS_URL')
CELERY_RESULT_BACKEND = os.environ.get('REDIS_URL')

# Email configuration
EMAIL_BACKEND = 'django.core.mail.backends.smtp.EmailBackend'
EMAIL_HOST = os.environ.get('EMAIL_HOST', 'smtp.gmail.com')
EMAIL_PORT = int(os.environ.get('EMAIL_PORT', '587'))
EMAIL_USE_TLS = os.environ.get('EMAIL_USE_TLS', 'True') == 'True'
EMAIL_HOST_USER = os.environ.get('EMAIL_HOST_USER')
EMAIL_HOST_PASSWORD = os.environ.get('EMAIL_HOST_PASSWORD')
DEFAULT_FROM_EMAIL = f'WeatherAlert <{EMAIL_HOST_USER}>'

# Static files
STATIC_URL = '/static/'
STATIC_ROOT = os.path.join(BASE_DIR, 'staticfiles')
STATICFILES_DIRS = [os.path.join(BASE_DIR, 'weatherapp/static/weatherapp')]

# Media files
MEDIA_URL = '/media/'
MEDIA_ROOT = os.path.join(BASE_DIR, 'media')

# Security settings for production
SECURE_BROWSER_XSS_FILTER = True
SECURE_CONTENT_TYPE_NOSNIFF = True
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_HSTS_SECONDS = 31536000
SECURE_REDIRECT_EXEMPT = []
SECURE_SSL_REDIRECT = False  # Set to True when SSL is configured
SESSION_COOKIE_SECURE = False  # Set to True when SSL is configured
CSRF_COOKIE_SECURE = False  # Set to True when SSL is configured

# Logging configuration
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'verbose': {
            'format': '{levelname} {asctime} {module} {process:d} {thread:d} {message}',
            'style': '{',
        },
    },
    'handlers': {
        'file': {
            'level': 'INFO',
            'class': 'logging.FileHandler',
            'filename': '$LOG_DIR/django.log',
            'formatter': 'verbose',
        },
        'console': {
            'level': 'INFO',
            'class': 'logging.StreamHandler',
            'formatter': 'verbose',
        },
    },
    'root': {
        'handlers': ['file', 'console'],
        'level': 'INFO',
    },
    'loggers': {
        'django': {
            'handlers': ['file', 'console'],
            'level': 'INFO',
            'propagate': False,
        },
        'weatherapp': {
            'handlers': ['file', 'console'],
            'level': 'INFO',
            'propagate': False,
        },
    },
}
EOF

    print_success "Django settings configured"
}

# Function to run database migrations
run_migrations() {
    print_status "Running database migrations..."
    
    cd $APP_DIR
    source venv/bin/activate
    
    # Set Django settings module
    export DJANGO_SETTINGS_MODULE=weatheralert.settings_production
    
    # Run migrations
    python manage.py makemigrations
    python manage.py migrate
    
    # Create superuser if it doesn't exist
    echo "from django.contrib.auth import get_user_model; User = get_user_model(); User.objects.filter(username='admin').exists() or User.objects.create_superuser('admin', 'admin@example.com', 'admin123')" | python manage.py shell
    
    # Collect static files
    python manage.py collectstatic --noinput
    
    deactivate
    
    print_success "Database migrations completed"
}

# Function to create systemd services
create_systemd_services() {
    print_status "Creating systemd services..."
    
    # Django service
    cat > /etc/systemd/system/django-$APP_NAME.service << EOF
[Unit]
Description=Django $APP_NAME application
After=network.target mysql.service redis.service
Requires=mysql.service redis.service

[Service]
Type=notify
User=django-$APP_NAME
Group=django-$APP_NAME
WorkingDirectory=$APP_DIR
Environment=PATH=$APP_DIR/venv/bin
Environment=DJANGO_SETTINGS_MODULE=weatheralert.settings_production
ExecStart=$APP_DIR/venv/bin/gunicorn --bind 127.0.0.1:8001 --workers 3 --timeout 120 --access-logfile $LOG_DIR/access.log --error-logfile $LOG_DIR/error.log weatheralert.wsgi:application
ExecReload=/bin/kill -s HUP \$MAINPID
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Celery worker service
    cat > /etc/systemd/system/celery-$APP_NAME.service << EOF
[Unit]
Description=Celery worker for $APP_NAME
After=network.target redis.service
Requires=redis.service

[Service]
Type=forking
User=django-$APP_NAME
Group=django-$APP_NAME
WorkingDirectory=$APP_DIR
Environment=PATH=$APP_DIR/venv/bin
Environment=DJANGO_SETTINGS_MODULE=weatheralert.settings_production
ExecStart=$APP_DIR/venv/bin/celery -A weatheralert worker --loglevel=info --logfile=$LOG_DIR/celery.log --pidfile=/var/run/celery-$APP_NAME.pid
ExecReload=/bin/kill -s HUP \$MAINPID
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Celery beat service
    cat > /etc/systemd/system/celerybeat-$APP_NAME.service << EOF
[Unit]
Description=Celery beat for $APP_NAME
After=network.target redis.service
Requires=redis.service

[Service]
Type=forking
User=django-$APP_NAME
Group=django-$APP_NAME
WorkingDirectory=$APP_DIR
Environment=PATH=$APP_DIR/venv/bin
Environment=DJANGO_SETTINGS_MODULE=weatheralert.settings_production
ExecStart=$APP_DIR/venv/bin/celery -A weatheralert beat --loglevel=info --logfile=$LOG_DIR/celerybeat.log --pidfile=/var/run/celerybeat-$APP_NAME.pid
ExecReload=/bin/kill -s HUP \$MAINPID
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Create user for the app
    useradd -r -s /bin/false -d $APP_DIR django-$APP_NAME 2>/dev/null || true
    
    # Set permissions
    chown -R django-$APP_NAME:django-$APP_NAME $APP_DIR
    chown -R django-$APP_NAME:django-$APP_NAME $LOG_DIR
    
    # Reload systemd
    systemctl daemon-reload
    
    print_success "Systemd services created"
}

# Function to create Nginx configuration
create_nginx_config() {
    print_status "Creating Nginx configuration..."
    
    cat > /etc/nginx/sites-available/$APP_NAME << EOF
# Nginx configuration for $APP_NAME
server {
    listen 80;
    server_name $SERVER_IP;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;
    
    # Static files
    location /static/ {
        alias $APP_DIR/staticfiles/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    location /media/ {
        alias $APP_DIR/media/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # Main application
    location /$APP_URL/ {
        proxy_pass http://127.0.0.1:8001/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffer settings
        proxy_buffering on;
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
    }
    
    # Health check
    location /$APP_URL/health/ {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF

    # Enable the site
    ln -sf /etc/nginx/sites-available/$APP_NAME /etc/nginx/sites-enabled/$APP_NAME
    
    # Test nginx configuration
    nginx -t
    systemctl reload nginx
    
    print_success "Nginx configuration created"
}

# Function to start services
start_services() {
    print_status "Starting services..."
    
    # Enable and start services
    systemctl enable django-$APP_NAME
    systemctl enable celery-$APP_NAME
    systemctl enable celerybeat-$APP_NAME
    
    systemctl start django-$APP_NAME
    systemctl start celery-$APP_NAME
    systemctl start celerybeat-$APP_NAME
    
    # Check service status
    sleep 5
    if systemctl is-active --quiet django-$APP_NAME; then
        print_success "Django service started successfully"
    else
        print_error "Django service failed to start"
        systemctl status django-$APP_NAME --no-pager
    fi
    
    if systemctl is-active --quiet celery-$APP_NAME; then
        print_success "Celery service started successfully"
    else
        print_warning "Celery service failed to start"
    fi
    
    if systemctl is-active --quiet celerybeat-$APP_NAME; then
        print_success "Celery beat service started successfully"
    else
        print_warning "Celery beat service failed to start"
    fi
}

# Function to create monitoring script
create_monitoring() {
    print_status "Creating monitoring script..."
    
    cat > /usr/local/bin/monitor-$APP_NAME.sh << EOF
#!/bin/bash

# WeatherAlert Monitoring Script
LOG_FILE="$LOG_DIR/monitor.log"

log_message() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1" >> \$LOG_FILE
}

check_service() {
    local service=\$1
    local name=\$2
    
    if systemctl is-active --quiet \$service; then
        log_message "✅ \$name is running"
        return 0
    else
        log_message "❌ \$name is not running - attempting restart"
        systemctl restart \$service
        sleep 5
        if systemctl is-active --quiet \$service; then
            log_message "✅ \$name restarted successfully"
        else
            log_message "🚨 \$name failed to restart"
        fi
        return 1
    fi
}

# Check all services
check_service "django-$APP_NAME" "Django"
check_service "celery-$APP_NAME" "Celery Worker"
check_service "celerybeat-$APP_NAME" "Celery Beat"

# Check application health
HTTP_STATUS=\$(curl -s -o /dev/null -w "%{http_code}" http://$SERVER_IP/$APP_URL/health/ || echo "000")
if [ "\$HTTP_STATUS" = "200" ]; then
    log_message "✅ Application is responding"
else
    log_message "❌ Application is not responding (HTTP \$HTTP_STATUS)"
fi
EOF

    chmod +x /usr/local/bin/monitor-$APP_NAME.sh
    
    # Add to cron
    cat > /etc/cron.d/monitor-$APP_NAME << EOF
# WeatherAlert Monitoring
*/5 * * * * root /usr/local/bin/monitor-$APP_NAME.sh
EOF

    print_success "Monitoring script created"
}

# Main deployment function
main() {
    print_status "Starting WeatherAlert deployment..."
    print_status "App: $APP_NAME"
    print_status "URL: http://$SERVER_IP/$APP_URL"
    
    check_root
    create_app_structure
    copy_app_files
    setup_virtualenv
    create_env_config
    configure_django
    run_migrations
    create_systemd_services
    create_nginx_config
    start_services
    create_monitoring
    
    print_success "WeatherAlert deployment completed successfully!"
    print_status ""
    print_status "Application is now available at:"
    print_status "  http://$SERVER_IP/$APP_URL"
    print_status ""
    print_status "Admin credentials:"
    print_status "  Username: admin"
    print_status "  Password: admin123"
    print_status ""
    print_status "Use the following commands to manage the application:"
    print_status "  systemctl status django-$APP_NAME"
    print_status "  systemctl restart django-$APP_NAME"
    print_status "  journalctl -u django-$APP_NAME -f"
    print_status ""
    print_status "Logs are available at:"
    print_status "  $LOG_DIR/"
}

# Run main function
main "$@"
