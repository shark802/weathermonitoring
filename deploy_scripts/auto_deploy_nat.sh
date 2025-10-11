#!/bin/bash

# =============================================================================
# WeatherAlert - Automated NAT Deployment Script
# Automatically deploys to Ubuntu server behind router/NAT
# 
# Server Setup:
#   - Internal IP: 192.168.3.5
#   - Gateway/Router: 192.168.3.1 (assumed)
#   - Public IP: 119.93.148.180 (on router)
# =============================================================================

set -e  # Exit on any error

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
APP_NAME="weatherapp"
APP_URL_PATH="weatherapp"
SERVER_IP="192.168.3.5"              # Internal/Private IP
PUBLIC_IP="119.93.148.180"            # External/Public IP
GATEWAY_IP="192.168.3.1"              # Default gateway
BASE_DIR="/opt/django-apps"
APP_DIR="$BASE_DIR/$APP_NAME"
LOG_DIR="/var/log/django-apps/$APP_NAME"
BACKUP_DIR="/opt/backups/$APP_NAME"

# Function to print colored output
print_header() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
}

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Function to detect network configuration
detect_network() {
    print_header "Detecting Network Configuration"
    
    # Detect primary interface
    PRIMARY_IF=$(ip route | grep default | awk '{print $5}' | head -n1)
    print_status "Primary network interface: $PRIMARY_IF"
    
    # Get actual server IP
    DETECTED_IP=$(ip -4 addr show $PRIMARY_IF | grep inet | awk '{print $2}' | cut -d/ -f1)
    print_status "Detected server IP: $DETECTED_IP"
    
    # Get gateway
    DETECTED_GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n1)
    print_status "Detected gateway: $DETECTED_GATEWAY"
    
    # Update variables if different
    if [ "$DETECTED_IP" != "$SERVER_IP" ]; then
        print_warning "Server IP mismatch. Using detected: $DETECTED_IP"
        SERVER_IP=$DETECTED_IP
    fi
    
    if [ "$DETECTED_GATEWAY" != "$GATEWAY_IP" ]; then
        GATEWAY_IP=$DETECTED_GATEWAY
    fi
    
    # Check if behind NAT
    if [[ $SERVER_IP =~ ^10\. ]] || \
       [[ $SERVER_IP =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] || \
       [[ $SERVER_IP =~ ^192\.168\. ]]; then
        print_warning "Server is behind NAT (private IP detected)"
        print_status "Internal IP: $SERVER_IP"
        print_status "Gateway: $GATEWAY_IP"
        print_status "Port forwarding will be needed on gateway for external access"
        NAT_DETECTED=true
    else
        print_success "Server has public IP"
        PUBLIC_IP=$SERVER_IP
        NAT_DETECTED=false
    fi
    
    echo ""
}

# Function to update system packages
update_system() {
    print_header "Updating System Packages"
    
    export DEBIAN_FRONTEND=noninteractive
    apt update
    apt upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
    
    print_success "System packages updated"
}

# Function to install required packages
install_dependencies() {
    print_header "Installing Dependencies"
    
    print_status "Installing Python and development tools..."
    apt install -y python3 python3-pip python3-venv python3-dev
    
    print_status "Installing web servers..."
    apt install -y nginx
    
    print_status "Installing Redis..."
    apt install -y redis-server
    
    print_status "Installing system utilities..."
    apt install -y git curl wget unzip vim nano htop net-tools
    apt install -y build-essential libssl-dev libffi-dev
    apt install -y libmysqlclient-dev pkg-config
    apt install -y software-properties-common
    
    print_status "Upgrading pip..."
    pip3 install --upgrade pip
    
    print_success "All dependencies installed"
}

# Function to configure firewall
configure_firewall() {
    print_header "Configuring Firewall (UFW)"
    
    # Install ufw if not present
    apt install -y ufw
    
    # Configure UFW
    print_status "Setting up firewall rules..."
    
    # Allow SSH (important!)
    ufw allow 22/tcp
    print_success "SSH (22) allowed"
    
    # Allow HTTP
    ufw allow 80/tcp
    print_success "HTTP (80) allowed"
    
    # Allow HTTPS
    ufw allow 443/tcp
    print_success "HTTPS (443) allowed"
    
    # Set defaults
    ufw default deny incoming
    ufw default allow outgoing
    
    # Enable firewall (non-interactive)
    yes | ufw enable
    
    print_success "Firewall configured and enabled"
    
    # Show status
    echo ""
    ufw status verbose
    echo ""
}

# Function to create directory structure
create_directories() {
    print_header "Creating Directory Structure"
    
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
    print_header "Configuring Redis"
    
    # Backup original config
    cp /etc/redis/redis.conf /etc/redis/redis.conf.backup
    
    # Configure Redis
    cat > /etc/redis/redis.conf << 'EOF'
# Redis configuration for Django WeatherApp
bind 127.0.0.1 ::1
protected-mode yes
port 6379
tcp-backlog 511
timeout 300
tcp-keepalive 300

# Persistence
save 900 1
save 300 10
save 60 10000

# Memory management
maxmemory 256mb
maxmemory-policy allkeys-lru

# Logging
loglevel notice
logfile /var/log/redis/redis-server.log

# Other settings
databases 16
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir /var/lib/redis
EOF
    
    # Start and enable Redis
    systemctl start redis-server
    systemctl enable redis-server
    
    # Test Redis
    if redis-cli ping > /dev/null 2>&1; then
        print_success "Redis configured and running"
    else
        print_error "Redis failed to start"
        exit 1
    fi
}

# Function to setup virtual environment
setup_virtualenv() {
    print_header "Setting Up Python Virtual Environment"
    
    cd $APP_DIR
    
    print_status "Creating virtual environment..."
    python3 -m venv venv
    
    print_status "Activating virtual environment..."
    source venv/bin/activate
    
    print_status "Installing Python packages..."
    pip install --upgrade pip setuptools wheel
    
    # Install requirements if file exists
    if [ -f "requirements.txt" ]; then
        print_status "Installing from requirements.txt..."
        pip install -r requirements.txt
    else
        print_status "Installing core packages..."
        pip install django==4.1.13
        pip install gunicorn
        pip install celery[redis]
        pip install redis
        pip install mysqlclient
        pip install whitenoise
        pip install python-dotenv
        pip install requests
    fi
    
    deactivate
    
    print_success "Virtual environment configured"
}

# Function to create environment configuration
create_env_config() {
    print_header "Creating Environment Configuration"
    
    # Generate secret key
    SECRET_KEY=$(python3 -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())" 2>/dev/null || openssl rand -base64 32)
    
    # Create .env file
    cat > $APP_DIR/.env << EOF
# WeatherAlert Environment Configuration
# Auto-generated on $(date)

# Django Core Settings
DEBUG=False
SECRET_KEY=$SECRET_KEY
ALLOWED_HOSTS=$PUBLIC_IP,$SERVER_IP,localhost,127.0.0.1
FORCE_SCRIPT_NAME=/$APP_URL_PATH

# Database Configuration (MySQL)
DB_NAME=u520834156_dbweatherApp
DB_USER=u520834156_uWApp2024
DB_PASSWORD=bIxG2Z\$In#8
DB_HOST=153.92.15.8
DB_PORT=3306
DATABASE_URL=mysql://u520834156_uWApp2024:bIxG2Z\$In%238@153.92.15.8:3306/u520834156_dbweatherApp

# Redis Configuration
REDIS_URL=redis://localhost:6379/0
CELERY_BROKER_URL=redis://localhost:6379/0
CELERY_RESULT_BACKEND=redis://localhost:6379/0

# Email Configuration
EMAIL_BACKEND=django.core.mail.backends.smtp.EmailBackend
EMAIL_HOST=smtp.gmail.com
EMAIL_PORT=587
EMAIL_USE_TLS=True
EMAIL_HOST_USER=rainalertcaps@gmail.com
EMAIL_HOST_PASSWORD=clmz izuz zphx tnrw
DEFAULT_FROM_EMAIL=WeatherAlert <rainalertcaps@gmail.com>

# SMS Configuration
SMS_API_URL=https://sms.pagenet.info/api/v1/sms/send
SMS_API_KEY=6PLX3NFL2A2FLQ81RI7X6C4PJP68ANLJNYQ7XAR6
SMS_DEVICE_ID=97e8c4360d11fa51

# PhilSys QR Keys
PSA_PUBLIC_KEY=
PSA_ED25519_PUBLIC_KEY=

# App Settings
APP_NAME=$APP_NAME
TIME_ZONE=Asia/Manila
LANGUAGE_CODE=en-us

# Session Settings
SESSION_EXPIRE_AT_BROWSER_CLOSE=False
SESSION_ENGINE=django.contrib.sessions.backends.db
SESSION_COOKIE_HTTPONLY=True
SESSION_SAVE_EVERY_REQUEST=True
SESSION_COOKIE_PATH=/$APP_URL_PATH
CSRF_COOKIE_PATH=/$APP_URL_PATH

# Static and Media Files
STATIC_URL=/$APP_URL_PATH/static/
STATIC_ROOT=$APP_DIR/staticfiles
MEDIA_URL=/$APP_URL_PATH/media/
MEDIA_ROOT=$APP_DIR/media

# Network Configuration (for reference)
INTERNAL_IP=$SERVER_IP
PUBLIC_IP=$PUBLIC_IP
GATEWAY_IP=$GATEWAY_IP
EOF

    chmod 600 $APP_DIR/.env
    print_success "Environment configuration created"
}

# Function to copy application files
copy_app_files() {
    print_header "Copying Application Files"
    
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
    
    # Copy static files if they exist
    if [ -d "$PROJECT_DIR/staticfiles" ]; then
        cp -r $PROJECT_DIR/staticfiles/* $APP_DIR/staticfiles/ 2>/dev/null || true
        print_success "Copied static files"
    fi
    
    print_success "Application files copied"
}

# Function to run database migrations
run_migrations() {
    print_header "Running Database Migrations"
    
    cd $APP_DIR
    source venv/bin/activate
    
    # Load environment variables
    if [ -f ".env" ]; then
        export $(cat .env | grep -v '^#' | xargs)
    fi
    
    print_status "Running makemigrations..."
    python manage.py makemigrations --noinput || true
    
    print_status "Running migrate..."
    python manage.py migrate --noinput
    
    print_status "Collecting static files..."
    python manage.py collectstatic --noinput
    
    deactivate
    
    print_success "Database migrations completed"
}

# Function to create systemd services
create_systemd_services() {
    print_header "Creating Systemd Services"
    
    # Create user for the app
    if ! id "django-$APP_NAME" &>/dev/null; then
        useradd -r -s /bin/false -d $APP_DIR django-$APP_NAME
        print_success "Created django-$APP_NAME user"
    fi
    
    # Django/Gunicorn service
    cat > /etc/systemd/system/django-$APP_NAME.service << EOF
[Unit]
Description=Django $APP_NAME Application (Gunicorn)
After=network.target redis.service
Requires=redis.service

[Service]
Type=notify
User=django-$APP_NAME
Group=django-$APP_NAME
WorkingDirectory=$APP_DIR
Environment="PATH=$APP_DIR/venv/bin"
EnvironmentFile=$APP_DIR/.env
ExecStart=$APP_DIR/venv/bin/gunicorn \\
    --bind 0.0.0.0:8001 \\
    --workers 3 \\
    --timeout 120 \\
    --access-logfile $LOG_DIR/access.log \\
    --error-logfile $LOG_DIR/error.log \\
    --log-level info \\
    weatheralert.wsgi:application
ExecReload=/bin/kill -s HUP \$MAINPID
KillMode=mixed
TimeoutStopSec=5
PrivateTmp=true
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    print_success "Created django-$APP_NAME.service"
    
    # Celery worker service
    cat > /etc/systemd/system/celery-$APP_NAME.service << EOF
[Unit]
Description=Celery Worker for $APP_NAME
After=network.target redis.service
Requires=redis.service

[Service]
Type=forking
User=django-$APP_NAME
Group=django-$APP_NAME
WorkingDirectory=$APP_DIR
Environment="PATH=$APP_DIR/venv/bin"
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

    print_success "Created celery-$APP_NAME.service"
    
    # Celery beat service
    cat > /etc/systemd/system/celerybeat-$APP_NAME.service << EOF
[Unit]
Description=Celery Beat Scheduler for $APP_NAME
After=network.target redis.service
Requires=redis.service

[Service]
Type=forking
User=django-$APP_NAME
Group=django-$APP_NAME
WorkingDirectory=$APP_DIR
Environment="PATH=$APP_DIR/venv/bin"
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

    print_success "Created celerybeat-$APP_NAME.service"
    
    # Set permissions
    chown -R django-$APP_NAME:django-$APP_NAME $APP_DIR
    chown -R django-$APP_NAME:django-$APP_NAME $LOG_DIR
    
    # Reload systemd
    systemctl daemon-reload
    
    print_success "Systemd services created"
}

# Function to create Nginx configuration
create_nginx_config() {
    print_header "Configuring Nginx"
    
    # Backup existing default config
    if [ -f "/etc/nginx/sites-enabled/default" ]; then
        mv /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/default.backup 2>/dev/null || true
    fi
    
    # Create Nginx configuration
    cat > /etc/nginx/sites-available/$APP_NAME << EOF
# Nginx configuration for WeatherAlert
# Internal IP: http://$SERVER_IP/$APP_URL_PATH
# Public IP: http://$PUBLIC_IP/$APP_URL_PATH (requires port forwarding)

upstream weatherapp_backend {
    server 127.0.0.1:8001;
    keepalive 32;
}

server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name $PUBLIC_IP $SERVER_IP localhost _;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' 'unsafe-inline' 'unsafe-eval' http: https: data: blob:;" always;
    
    # Client settings
    client_max_body_size 10M;
    client_body_buffer_size 128k;
    
    # Timeouts
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
    send_timeout 60s;
    
    # Logging
    access_log $LOG_DIR/nginx-access.log;
    error_log $LOG_DIR/nginx-error.log;
    
    # Root redirect to weatherapp
    location = / {
        return 301 /$APP_URL_PATH/;
    }
    
    # Favicon
    location = /favicon.ico {
        access_log off;
        log_not_found off;
        return 204;
    }
    
    # Static files
    location /$APP_URL_PATH/static/ {
        alias $APP_DIR/staticfiles/;
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
        
        # Handle missing files gracefully
        try_files \$uri \$uri/ =404;
    }
    
    # Media files
    location /$APP_URL_PATH/media/ {
        alias $APP_DIR/media/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # Main application
    location /$APP_URL_PATH/ {
        # Rate limiting
        limit_req zone=general burst=20 nodelay;
        
        # Proxy to Django/Gunicorn
        proxy_pass http://weatherapp_backend/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Script-Name /$APP_URL_PATH;
        proxy_redirect off;
        
        # Buffer settings
        proxy_buffering on;
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    # Health check endpoint
    location /$APP_URL_PATH/health/ {
        access_log off;
        return 200 "WeatherAlert is healthy\\n";
        add_header Content-Type text/plain;
    }
    
    # System health check (for monitoring)
    location /system-health/ {
        access_log off;
        return 200 "System OK\\n";
        add_header Content-Type text/plain;
    }
}
EOF

    print_success "Created Nginx configuration"
    
    # Update main nginx.conf if needed
    if ! grep -q "limit_req_zone" /etc/nginx/nginx.conf; then
        print_status "Adding rate limiting to nginx.conf..."
        sed -i '/http {/a \    # Rate limiting\n    limit_req_zone $binary_remote_addr zone=general:10m rate=20r/s;' /etc/nginx/nginx.conf
    fi
    
    # Enable the site
    ln -sf /etc/nginx/sites-available/$APP_NAME /etc/nginx/sites-enabled/$APP_NAME
    
    # Test nginx configuration
    print_status "Testing Nginx configuration..."
    if nginx -t; then
        print_success "Nginx configuration valid"
    else
        print_error "Nginx configuration invalid"
        exit 1
    fi
    
    # Restart Nginx
    systemctl restart nginx
    systemctl enable nginx
    
    print_success "Nginx configured and running"
}

# Function to start services
start_services() {
    print_header "Starting Services"
    
    # Enable and start services
    print_status "Enabling services..."
    systemctl enable django-$APP_NAME
    systemctl enable celery-$APP_NAME
    systemctl enable celerybeat-$APP_NAME
    systemctl enable nginx
    systemctl enable redis-server
    
    print_status "Starting Django service..."
    systemctl start django-$APP_NAME
    sleep 3
    
    print_status "Starting Celery worker..."
    systemctl start celery-$APP_NAME
    sleep 2
    
    print_status "Starting Celery beat..."
    systemctl start celerybeat-$APP_NAME
    sleep 2
    
    # Check service status
    echo ""
    if systemctl is-active --quiet django-$APP_NAME; then
        print_success "Django service is running"
    else
        print_error "Django service failed to start"
        journalctl -u django-$APP_NAME -n 20 --no-pager
    fi
    
    if systemctl is-active --quiet celery-$APP_NAME; then
        print_success "Celery worker is running"
    else
        print_warning "Celery worker failed to start (non-critical)"
    fi
    
    if systemctl is-active --quiet celerybeat-$APP_NAME; then
        print_success "Celery beat is running"
    else
        print_warning "Celery beat failed to start (non-critical)"
    fi
    
    if systemctl is-active --quiet nginx; then
        print_success "Nginx is running"
    else
        print_error "Nginx failed to start"
    fi
    
    if systemctl is-active --quiet redis-server; then
        print_success "Redis is running"
    else
        print_error "Redis failed to start"
    fi
}

# Function to create monitoring script
create_monitoring() {
    print_header "Creating Monitoring Scripts"
    
    cat > /usr/local/bin/weatherapp-monitor.sh << 'MONITOR_EOF'
#!/bin/bash

APP_NAME="weatherapp"
LOG_DIR="/var/log/django-apps/weatherapp"
LOG_FILE="$LOG_DIR/monitor.log"
SERVER_IP="192.168.3.5"
PUBLIC_IP="119.93.148.180"
APP_URL_PATH="weatherapp"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> $LOG_FILE
}

check_service() {
    local service=$1
    local name=$2
    
    if systemctl is-active --quiet $service; then
        log_message "✓ $name is running"
        return 0
    else
        log_message "✗ $name is not running - attempting restart"
        systemctl restart $service
        sleep 5
        if systemctl is-active --quiet $service; then
            log_message "✓ $name restarted successfully"
        else
            log_message "✗✗ $name failed to restart"
        fi
        return 1
    fi
}

# Check all services
check_service "django-$APP_NAME" "Django"
check_service "celery-$APP_NAME" "Celery Worker"
check_service "celerybeat-$APP_NAME" "Celery Beat"
check_service "nginx" "Nginx"
check_service "redis-server" "Redis"

# Check application health (local)
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/$APP_URL_PATH/ 2>/dev/null || echo "000")
if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "302" ]; then
    log_message "✓ Application responding (HTTP $HTTP_STATUS)"
else
    log_message "✗ Application not responding (HTTP $HTTP_STATUS)"
fi

# Check system resources
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
MEMORY_USAGE=$(free | awk 'NR==2{printf "%.2f", $3*100/$2}')

if [ $DISK_USAGE -gt 80 ]; then
    log_message "⚠ High disk usage: ${DISK_USAGE}%"
fi

if (( $(echo "$MEMORY_USAGE > 80" | bc -l 2>/dev/null || echo "0") )); then
    log_message "⚠ High memory usage: ${MEMORY_USAGE}%"
fi
MONITOR_EOF

    chmod +x /usr/local/bin/weatherapp-monitor.sh
    
    # Create cron job
    cat > /etc/cron.d/weatherapp-monitor << 'CRON_EOF'
# WeatherAlert Monitoring - Every 5 minutes
*/5 * * * * root /usr/local/bin/weatherapp-monitor.sh
CRON_EOF

    print_success "Monitoring script created"
}

# Function to create management script
create_management_script() {
    print_header "Creating Management Tools"
    
    cat > /usr/local/bin/weatherapp-manage.sh << 'MANAGE_EOF'
#!/bin/bash

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
    echo "  update      - Update application"
    echo "  shell       - Open Django shell"
    echo "  backup      - Create backup"
    echo "  network     - Show network configuration"
    echo "  test        - Test application"
}

case "$1" in
    status)
        echo "=== Service Status ==="
        systemctl status django-$APP_NAME --no-pager | head -n 10
        echo ""
        systemctl status celery-$APP_NAME --no-pager | head -n 10
        echo ""
        systemctl status nginx --no-pager | head -n 10
        echo ""
        systemctl status redis-server --no-pager | head -n 10
        ;;
    start)
        echo "Starting all services..."
        systemctl start django-$APP_NAME celery-$APP_NAME celerybeat-$APP_NAME nginx redis-server
        echo "Services started"
        ;;
    stop)
        echo "Stopping all services..."
        systemctl stop django-$APP_NAME celery-$APP_NAME celerybeat-$APP_NAME
        echo "Services stopped"
        ;;
    restart)
        echo "Restarting all services..."
        systemctl restart django-$APP_NAME celery-$APP_NAME celerybeat-$APP_NAME nginx
        echo "Services restarted"
        ;;
    logs)
        echo "=== Recent Logs ==="
        echo "Django errors:"
        tail -n 30 $LOG_DIR/error.log
        echo ""
        echo "Celery:"
        tail -n 20 $LOG_DIR/celery.log
        ;;
    update)
        echo "Updating application..."
        systemctl stop django-$APP_NAME celery-$APP_NAME celerybeat-$APP_NAME
        cd $APP_DIR
        source venv/bin/activate
        pip install -r requirements.txt
        python manage.py migrate --noinput
        python manage.py collectstatic --noinput
        deactivate
        systemctl start django-$APP_NAME celery-$APP_NAME celerybeat-$APP_NAME
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
    network)
        echo "=== Network Configuration ==="
        echo "Interface Information:"
        ip -4 addr show | grep inet
        echo ""
        echo "Gateway:"
        ip route show default
        echo ""
        echo "Listening Ports:"
        netstat -tlnp | grep -E ':(80|443|8001|6379|3306)'
        ;;
    test)
        echo "=== Testing Application ==="
        echo "Local test:"
        curl -I http://localhost/weatherapp/ 2>/dev/null | head -n 1
        echo ""
        echo "Service status:"
        systemctl is-active django-$APP_NAME celery-$APP_NAME nginx redis-server
        ;;
    *)
        show_help
        ;;
esac
MANAGE_EOF

    chmod +x /usr/local/bin/weatherapp-manage.sh
    
    print_success "Management script created at /usr/local/bin/weatherapp-manage.sh"
}

# Function to create port forwarding helper
create_port_forwarding_helper() {
    print_header "Creating Port Forwarding Helper"
    
    cat > /usr/local/bin/check-port-forwarding.sh << EOF
#!/bin/bash

# Port Forwarding Check Script
GATEWAY="$GATEWAY_IP"
PUBLIC_IP="$PUBLIC_IP"
SERVER_IP="$SERVER_IP"

echo "==================================="
echo "Port Forwarding Configuration Check"
echo "==================================="
echo ""
echo "Network Configuration:"
echo "  Gateway/Router: $GATEWAY"
echo "  Server IP (Internal): $SERVER_IP"
echo "  Public IP (External): $PUBLIC_IP"
echo ""
echo "==================================="
echo "Required Port Forwarding Rules:"
echo "==================================="
echo ""
echo "On your router ($GATEWAY), configure:"
echo ""
echo "Rule 1 - HTTP Traffic:"
echo "  External Port: 80"
echo "  Internal IP:   $SERVER_IP"
echo "  Internal Port: 80"
echo "  Protocol:      TCP"
echo ""
echo "Rule 2 - HTTPS Traffic (optional):"
echo "  External Port: 443"
echo "  Internal IP:   $SERVER_IP"
echo "  Internal Port: 443"
echo "  Protocol:      TCP"
echo ""
echo "==================================="
echo "Access Router Configuration:"
echo "==================================="
echo ""
echo "1. Open browser: http://$GATEWAY"
echo "2. Login with router credentials"
echo "3. Find: Port Forwarding / Virtual Server / NAT"
echo "4. Add the rules above"
echo "5. Save and reboot router if needed"
echo ""
echo "==================================="
echo "After Configuration, Test Access:"
echo "==================================="
echo ""
echo "Internal (same network):"
echo "  http://$SERVER_IP/weatherapp"
echo ""
echo "External (internet):"
echo "  http://$PUBLIC_IP/weatherapp"
echo ""
EOF

    chmod +x /usr/local/bin/check-port-forwarding.sh
    
    print_success "Port forwarding helper created"
}

# Function to print final summary
print_summary() {
    print_header "Deployment Summary"
    
    echo ""
    echo -e "${GREEN}✓ Deployment Completed Successfully!${NC}"
    echo ""
    echo "==================================="
    echo "Network Configuration:"
    echo "==================================="
    echo "Internal IP: $SERVER_IP"
    echo "Gateway:     $GATEWAY_IP"
    echo "Public IP:   $PUBLIC_IP"
    echo ""
    
    if [ "$NAT_DETECTED" = true ]; then
        echo -e "${YELLOW}⚠ NAT Configuration Detected${NC}"
        echo ""
        echo "Your server is behind a router/NAT."
        echo "To access from internet, configure port forwarding:"
        echo ""
        echo "Run this command for instructions:"
        echo -e "${CYAN}sudo /usr/local/bin/check-port-forwarding.sh${NC}"
        echo ""
    fi
    
    echo "==================================="
    echo "Access URLs:"
    echo "==================================="
    echo ""
    echo "From Local Network:"
    echo -e "  ${CYAN}http://$SERVER_IP/weatherapp${NC}"
    echo ""
    
    if [ "$NAT_DETECTED" = true ]; then
        echo "From Internet (requires port forwarding):"
        echo -e "  ${CYAN}http://$PUBLIC_IP/weatherapp${NC}"
    else
        echo "From Internet:"
        echo -e "  ${CYAN}http://$PUBLIC_IP/weatherapp${NC}"
    fi
    echo ""
    
    echo "==================================="
    echo "Management Commands:"
    echo "==================================="
    echo ""
    echo "Check status:"
    echo "  weatherapp-manage.sh status"
    echo ""
    echo "Restart services:"
    echo "  weatherapp-manage.sh restart"
    echo ""
    echo "View logs:"
    echo "  weatherapp-manage.sh logs"
    echo ""
    echo "See all commands:"
    echo "  weatherapp-manage.sh"
    echo ""
    
    echo "==================================="
    echo "Service Status:"
    echo "==================================="
    echo ""
    systemctl is-active --quiet django-weatherapp && echo -e "${GREEN}✓${NC} Django is running" || echo -e "${RED}✗${NC} Django is not running"
    systemctl is-active --quiet celery-weatherapp && echo -e "${GREEN}✓${NC} Celery is running" || echo -e "${YELLOW}⚠${NC} Celery is not running"
    systemctl is-active --quiet nginx && echo -e "${GREEN}✓${NC} Nginx is running" || echo -e "${RED}✗${NC} Nginx is not running"
    systemctl is-active --quiet redis-server && echo -e "${GREEN}✓${NC} Redis is running" || echo -e "${RED}✗${NC} Redis is not running"
    echo ""
    
    echo "==================================="
    echo "Next Steps:"
    echo "==================================="
    echo ""
    if [ "$NAT_DETECTED" = true ]; then
        echo "1. Configure port forwarding on router"
        echo "   Run: check-port-forwarding.sh"
        echo ""
        echo "2. Test local access:"
        echo "   curl http://$SERVER_IP/weatherapp/"
        echo ""
        echo "3. After port forwarding, test external access:"
        echo "   curl http://$PUBLIC_IP/weatherapp/"
    else
        echo "1. Test application:"
        echo "   curl http://$PUBLIC_IP/weatherapp/"
    fi
    echo ""
    echo "4. Create Django superuser:"
    echo "   cd $APP_DIR"
    echo "   source venv/bin/activate"
    echo "   python manage.py createsuperuser"
    echo ""
    echo "5. Monitor logs:"
    echo "   tail -f $LOG_DIR/error.log"
    echo ""
    
    print_success "Deployment Complete!"
    echo ""
}

# Main deployment function
main() {
    clear
    
    print_header "WeatherAlert - Automated NAT Deployment"
    
    echo -e "${CYAN}Starting automated deployment for Ubuntu server behind NAT${NC}"
    echo -e "${CYAN}This will install and configure everything automatically${NC}"
    echo ""
    
    # Confirm before proceeding
    read -p "Press Enter to continue or Ctrl+C to cancel..."
    echo ""
    
    check_root
    detect_network
    update_system
    install_dependencies
    configure_firewall
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
    create_port_forwarding_helper
    print_summary
}

# Run main function
main "$@"

