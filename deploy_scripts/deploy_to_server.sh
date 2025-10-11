#!/bin/bash

# =============================================================================
# WeatherAlert Django Application - Production Deployment Script
# Deploys to: 119.93.148.180/weatherapp
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
APP_URL_PATH="weatherapp"
SERVER_IP="119.93.148.180"
BASE_DIR="/opt/django-apps"
APP_DIR="$BASE_DIR/$APP_NAME"
LOG_DIR="/var/log/django-apps/$APP_NAME"
BACKUP_DIR="/opt/backups/$APP_NAME"

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

# Function to update system packages
update_system() {
    print_status "Updating system packages..."
    apt update && apt upgrade -y
    print_success "System packages updated"
}

# Function to install required packages
install_dependencies() {
    print_status "Installing system dependencies..."
    
    # Essential packages
    apt install -y python3 python3-pip python3-venv python3-dev
    apt install -y nginx redis-server
    apt install -y git curl wget unzip
    apt install -y build-essential libssl-dev libffi-dev
    apt install -y libmysqlclient-dev pkg-config
    apt install -y supervisor
    
    # Python packages
    pip3 install --upgrade pip
    pip3 install gunicorn
    
    print_success "Dependencies installed"
}

# Function to create directory structure
create_directories() {
    print_status "Creating directory structure..."
    
    mkdir -p $BASE_DIR
    mkdir -p $APP_DIR
    mkdir -p $LOG_DIR
    mkdir -p $BACKUP_DIR
    mkdir -p $APP_DIR/staticfiles
    mkdir -p $APP_DIR/media
    mkdir -p /etc/django-apps
    
    print_success "Directory structure created"
}

# Function to setup Redis
setup_redis() {
    print_status "Setting up Redis..."
    
    systemctl start redis-server
    systemctl enable redis-server
    
    # Configure Redis
    cat > /etc/redis/redis.conf << 'EOF'
# Redis configuration for Django apps
bind 127.0.0.1
port 6379
timeout 300
keepalive 60
tcp-keepalive 60

# Memory management
maxmemory 256mb
maxmemory-policy allkeys-lru

# Persistence
save 900 1
save 300 10
save 60 10000

# Logging
loglevel notice
logfile /var/log/redis/redis-server.log
EOF
    
    systemctl restart redis-server
    print_success "Redis configured"
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
    
    # Check if requirements.txt exists
    if [ -f "requirements.txt" ]; then
        pip install -r requirements.txt
    else
        print_warning "requirements.txt not found, installing basic packages"
        pip install django gunicorn celery[redis] mysqlclient whitenoise python-dotenv
    fi
    
    deactivate
    
    print_success "Virtual environment setup completed"
}

# Function to create environment configuration
create_env_config() {
    print_status "Creating environment configuration..."
    
    # Generate secret key
    SECRET_KEY=$(python3 -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())" 2>/dev/null || openssl rand -base64 32)
    
    # Create .env file
    cat > $APP_DIR/.env << EOF
# WeatherAlert Environment Configuration
DEBUG=False
SECRET_KEY=$SECRET_KEY
ALLOWED_HOSTS=$SERVER_IP,localhost,127.0.0.1
FORCE_SCRIPT_NAME=/$APP_URL_PATH

# Database configuration (using existing MySQL database)
DATABASE_URL=mysql://u520834156_uWApp2024:bIxG2Z\$In%238@153.92.15.8:3306/u520834156_dbweatherApp

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
APP_URL=http://$SERVER_IP/$APP_URL_PATH
TIME_ZONE=Asia/Manila
LANGUAGE_CODE=en-us

# Security settings
SESSION_EXPIRE_AT_BROWSER_CLOSE=False
SESSION_ENGINE=django.contrib.sessions.backends.db
SESSION_COOKIE_HTTPONLY=True
SESSION_SAVE_EVERY_REQUEST=True
SESSION_COOKIE_PATH=/$APP_URL_PATH

# Static files
STATIC_URL=/$APP_URL_PATH/static/
STATIC_ROOT=$APP_DIR/staticfiles
MEDIA_URL=/$APP_URL_PATH/media/
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
    
    print_status "Project directory: $PROJECT_DIR"
    
    # Copy Django project files
    if [ -d "$PROJECT_DIR/weatheralert" ]; then
        cp -r $PROJECT_DIR/weatheralert $APP_DIR/
        print_success "Copied weatheralert directory"
    fi
    
    if [ -d "$PROJECT_DIR/weatherapp" ]; then
        cp -r $PROJECT_DIR/weatherapp $APP_DIR/
        print_success "Copied weatherapp directory"
    fi
    
    if [ -f "$PROJECT_DIR/manage.py" ]; then
        cp $PROJECT_DIR/manage.py $APP_DIR/
        print_success "Copied manage.py"
    fi
    
    if [ -f "$PROJECT_DIR/requirements.txt" ]; then
        cp $PROJECT_DIR/requirements.txt $APP_DIR/
        print_success "Copied requirements.txt"
    fi
    
    # Copy static files
    if [ -d "$PROJECT_DIR/staticfiles" ]; then
        cp -r $PROJECT_DIR/staticfiles/* $APP_DIR/staticfiles/ 2>/dev/null || true
        print_success "Copied static files"
    fi
    
    print_success "Application files copied"
}

# Function to run database migrations
run_migrations() {
    print_status "Running database migrations..."
    
    cd $APP_DIR
    source venv/bin/activate
    
    # Load environment variables
    if [ -f ".env" ]; then
        export $(cat .env | grep -v '^#' | xargs)
    fi
    
    # Run migrations
    python manage.py makemigrations --noinput || true
    python manage.py migrate --noinput
    
    # Collect static files
    python manage.py collectstatic --noinput
    
    deactivate
    
    print_success "Database migrations completed"
}

# Function to create systemd services
create_systemd_services() {
    print_status "Creating systemd services..."
    
    # Create user for the app
    useradd -r -s /bin/false -d $APP_DIR django-$APP_NAME 2>/dev/null || true
    
    # Django/Gunicorn service
    cat > /etc/systemd/system/django-$APP_NAME.service << EOF
[Unit]
Description=Django $APP_NAME application
After=network.target redis.service
Requires=redis.service

[Service]
Type=notify
User=django-$APP_NAME
Group=django-$APP_NAME
WorkingDirectory=$APP_DIR
Environment=PATH=$APP_DIR/venv/bin
EnvironmentFile=$APP_DIR/.env
ExecStart=$APP_DIR/venv/bin/gunicorn \\
    --bind 127.0.0.1:8001 \\
    --workers 3 \\
    --timeout 120 \\
    --access-logfile $LOG_DIR/access.log \\
    --error-logfile $LOG_DIR/error.log \\
    weatheralert.wsgi:application
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
EnvironmentFile=$APP_DIR/.env
ExecStart=$APP_DIR/venv/bin/celery -A weatheralert worker \\
    --loglevel=info \\
    --logfile=$LOG_DIR/celery.log \\
    --pidfile=/var/run/celery-$APP_NAME.pid \\
    --detach
ExecStop=/bin/kill -s TERM \$MAINPID
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
EnvironmentFile=$APP_DIR/.env
ExecStart=$APP_DIR/venv/bin/celery -A weatheralert beat \\
    --loglevel=info \\
    --logfile=$LOG_DIR/celerybeat.log \\
    --pidfile=/var/run/celerybeat-$APP_NAME.pid \\
    --detach
ExecStop=/bin/kill -s TERM \$MAINPID
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

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
    
    # Backup existing nginx config
    if [ -f "/etc/nginx/sites-enabled/default" ]; then
        mv /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/default.backup 2>/dev/null || true
    fi
    
    cat > /etc/nginx/sites-available/$APP_NAME << EOF
# Nginx configuration for WeatherAlert Application
# Accessible at: http://$SERVER_IP/$APP_URL_PATH

server {
    listen 80;
    server_name $SERVER_IP;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' 'unsafe-inline' 'unsafe-eval' http: https: data: blob:;" always;
    
    # Client max body size
    client_max_body_size 10M;
    
    # Logging
    access_log $LOG_DIR/nginx-access.log;
    error_log $LOG_DIR/nginx-error.log;
    
    # Root redirect to weatherapp
    location = / {
        return 301 /$APP_URL_PATH/;
    }
    
    # Static files - serve directly from nginx
    location /$APP_URL_PATH/static/ {
        alias $APP_DIR/staticfiles/;
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
    
    # Media files - serve directly from nginx
    location /$APP_URL_PATH/media/ {
        alias $APP_DIR/media/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # Main application
    location /$APP_URL_PATH/ {
        # Rate limiting
        limit_req zone=general burst=20 nodelay;
        
        # Proxy to Django/Gunicorn backend
        proxy_pass http://127.0.0.1:8001/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Script-Name /$APP_URL_PATH;
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
        
        # WebSocket support (if needed)
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    # Health check
    location /$APP_URL_PATH/health/ {
        access_log off;
        return 200 "WeatherAlert is healthy\\n";
        add_header Content-Type text/plain;
    }
}
EOF

    # Update nginx.conf to add rate limiting
    if ! grep -q "limit_req_zone" /etc/nginx/nginx.conf; then
        sed -i '/http {/a \    # Rate limiting\n    limit_req_zone $binary_remote_addr zone=general:10m rate=20r/s;' /etc/nginx/nginx.conf
    fi
    
    # Enable the site
    ln -sf /etc/nginx/sites-available/$APP_NAME /etc/nginx/sites-enabled/$APP_NAME
    
    # Remove default nginx site
    rm -f /etc/nginx/sites-enabled/default
    
    # Test nginx configuration
    nginx -t
    
    # Restart nginx
    systemctl restart nginx
    systemctl enable nginx
    
    print_success "Nginx configuration created and enabled"
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
    
    # Wait a moment for services to start
    sleep 5
    
    # Check service status
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
        systemctl status celery-$APP_NAME --no-pager || true
    fi
    
    if systemctl is-active --quiet celerybeat-$APP_NAME; then
        print_success "Celery beat service started successfully"
    else
        print_warning "Celery beat service failed to start"
        systemctl status celerybeat-$APP_NAME --no-pager || true
    fi
}

# Function to create monitoring script
create_monitoring() {
    print_status "Creating monitoring script..."
    
    cat > /usr/local/bin/monitor-$APP_NAME.sh << 'MONITOR_SCRIPT'
#!/bin/bash

# WeatherAlert Monitoring Script
APP_NAME="weatherapp"
LOG_DIR="/var/log/django-apps/weatherapp"
SERVER_IP="119.93.148.180"
APP_URL_PATH="weatherapp"
LOG_FILE="$LOG_DIR/monitor.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> $LOG_FILE
}

check_service() {
    local service=$1
    local name=$2
    
    if systemctl is-active --quiet $service; then
        log_message "✅ $name is running"
        return 0
    else
        log_message "❌ $name is not running - attempting restart"
        systemctl restart $service
        sleep 5
        if systemctl is-active --quiet $service; then
            log_message "✅ $name restarted successfully"
        else
            log_message "🚨 $name failed to restart"
        fi
        return 1
    fi
}

# Check all services
check_service "django-$APP_NAME" "Django"
check_service "celery-$APP_NAME" "Celery Worker"
check_service "celerybeat-$APP_NAME" "Celery Beat"
check_service "redis-server" "Redis"
check_service "nginx" "Nginx"

# Check application health
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://$SERVER_IP/$APP_URL_PATH/ 2>/dev/null || echo "000")
if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "302" ]; then
    log_message "✅ Application is responding (HTTP $HTTP_STATUS)"
else
    log_message "❌ Application is not responding (HTTP $HTTP_STATUS)"
fi

# Check disk space
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ $DISK_USAGE -gt 80 ]; then
    log_message "⚠️ High disk usage: ${DISK_USAGE}%"
fi

# Check memory usage
MEMORY_USAGE=$(free | awk 'NR==2{printf "%.2f", $3*100/$2}')
if (( $(echo "$MEMORY_USAGE > 80" | bc -l 2>/dev/null || echo "0") )); then
    log_message "⚠️ High memory usage: ${MEMORY_USAGE}%"
fi
MONITOR_SCRIPT

    chmod +x /usr/local/bin/monitor-$APP_NAME.sh
    
    # Add to cron
    cat > /etc/cron.d/monitor-$APP_NAME << EOF
# WeatherAlert Monitoring
*/5 * * * * root /usr/local/bin/monitor-$APP_NAME.sh
EOF

    print_success "Monitoring script created"
}

# Function to create management script
create_management_script() {
    print_status "Creating management script..."
    
    cat > /usr/local/bin/weatherapp-manage.sh << 'MANAGE_SCRIPT'
#!/bin/bash

# WeatherAlert Management Script
APP_NAME="weatherapp"
APP_DIR="/opt/django-apps/weatherapp"
LOG_DIR="/var/log/django-apps/weatherapp"

show_help() {
    echo "WeatherAlert Management Script"
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  status      - Show status of all services"
    echo "  start       - Start all services"
    echo "  stop        - Stop all services"
    echo "  restart     - Restart all services"
    echo "  logs        - Show recent logs"
    echo "  update      - Update application (pull and restart)"
    echo "  shell       - Open Django shell"
    echo "  backup      - Create backup of database and files"
}

case "$1" in
    status)
        echo "=== Service Status ==="
        systemctl status django-$APP_NAME --no-pager
        echo ""
        systemctl status celery-$APP_NAME --no-pager
        echo ""
        systemctl status celerybeat-$APP_NAME --no-pager
        ;;
    start)
        echo "Starting all services..."
        systemctl start django-$APP_NAME
        systemctl start celery-$APP_NAME
        systemctl start celerybeat-$APP_NAME
        echo "Services started"
        ;;
    stop)
        echo "Stopping all services..."
        systemctl stop django-$APP_NAME
        systemctl stop celery-$APP_NAME
        systemctl stop celerybeat-$APP_NAME
        echo "Services stopped"
        ;;
    restart)
        echo "Restarting all services..."
        systemctl restart django-$APP_NAME
        systemctl restart celery-$APP_NAME
        systemctl restart celerybeat-$APP_NAME
        systemctl restart nginx
        echo "Services restarted"
        ;;
    logs)
        echo "=== Recent Logs ==="
        echo "Django logs:"
        tail -n 50 $LOG_DIR/error.log
        echo ""
        echo "Celery logs:"
        tail -n 50 $LOG_DIR/celery.log
        ;;
    update)
        echo "Updating application..."
        cd $APP_DIR
        source venv/bin/activate
        python manage.py migrate --noinput
        python manage.py collectstatic --noinput
        deactivate
        systemctl restart django-$APP_NAME
        systemctl restart celery-$APP_NAME
        systemctl restart celerybeat-$APP_NAME
        echo "Application updated and restarted"
        ;;
    shell)
        cd $APP_DIR
        source venv/bin/activate
        python manage.py shell
        ;;
    backup)
        echo "Creating backup..."
        BACKUP_DIR="/opt/backups/weatherapp"
        DATE=$(date +%Y%m%d_%H%M%S)
        mkdir -p $BACKUP_DIR
        tar -czf $BACKUP_DIR/app_$DATE.tar.gz -C /opt/django-apps weatherapp
        echo "Backup created: $BACKUP_DIR/app_$DATE.tar.gz"
        ;;
    *)
        show_help
        ;;
esac
MANAGE_SCRIPT

    chmod +x /usr/local/bin/weatherapp-manage.sh
    
    print_success "Management script created at /usr/local/bin/weatherapp-manage.sh"
}

# Function to configure firewall
configure_firewall() {
    print_status "Configuring firewall..."
    
    # Check if ufw is installed
    if command -v ufw &> /dev/null; then
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw allow 22/tcp
        ufw --force enable
        print_success "Firewall configured"
    else
        print_warning "UFW not installed, skipping firewall configuration"
    fi
}

# Main deployment function
main() {
    print_status "========================================="
    print_status "WeatherAlert Application Deployment"
    print_status "========================================="
    print_status "Server IP: $SERVER_IP"
    print_status "Application URL: http://$SERVER_IP/$APP_URL_PATH"
    print_status "========================================="
    echo ""
    
    check_root
    update_system
    install_dependencies
    create_directories
    setup_redis
    copy_app_files
    setup_virtualenv
    create_env_config
    run_migrations
    create_systemd_services
    create_nginx_config
    start_services
    create_monitoring
    create_management_script
    configure_firewall
    
    echo ""
    print_success "========================================="
    print_success "Deployment completed successfully!"
    print_success "========================================="
    echo ""
    print_status "Application is now available at:"
    print_status "  ➡️  http://$SERVER_IP/$APP_URL_PATH"
    echo ""
    print_status "Service Management:"
    print_status "  systemctl status django-$APP_NAME"
    print_status "  systemctl restart django-$APP_NAME"
    print_status "  journalctl -u django-$APP_NAME -f"
    echo ""
    print_status "Quick Management:"
    print_status "  weatherapp-manage.sh status"
    print_status "  weatherapp-manage.sh restart"
    print_status "  weatherapp-manage.sh logs"
    echo ""
    print_status "Logs are available at:"
    print_status "  $LOG_DIR/"
    echo ""
    print_success "========================================="
}

# Run main function
main "$@"

