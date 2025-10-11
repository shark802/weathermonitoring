#!/bin/bash

# =============================================================================
# Multi-Application Django Deployment Script for Ubuntu Server
# Supports: weatherapp, irmss, fireguard and other Django applications
# Server IP: 192.168.3.5
# =============================================================================

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SERVER_IP="192.168.3.5"
BASE_DIR="/opt/django-apps"
NGINX_CONF_DIR="/etc/nginx/sites-available"
NGINX_ENABLED_DIR="/etc/nginx/sites-enabled"
SYSTEMD_DIR="/etc/systemd/system"
LOG_DIR="/var/log/django-apps"
BACKUP_DIR="/opt/backups"

# App configurations
declare -A APPS
APPS=(
    ["weatherapp"]="bccweatherapp"
    ["irmss"]="irrms" 
    ["fireguard"]="fireguard"
)

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
    apt install -y nginx mysql-server redis-server
    apt install -y git curl wget unzip
    apt install -y build-essential libssl-dev libffi-dev
    apt install -y libmysqlclient-dev pkg-config
    apt install -y supervisor
    apt install -y certbot python3-certbot-nginx
    
    # Python packages
    pip3 install --upgrade pip
    pip3 install gunicorn
    
    print_success "Dependencies installed"
}

# Function to create directory structure
create_directories() {
    print_status "Creating directory structure..."
    
    mkdir -p $BASE_DIR
    mkdir -p $LOG_DIR
    mkdir -p $BACKUP_DIR
    mkdir -p /etc/django-apps
    
    # Create directories for each app
    for app in "${!APPS[@]}"; do
        mkdir -p $BASE_DIR/$app
        mkdir -p $LOG_DIR/$app
        mkdir -p $BACKUP_DIR/$app
    done
    
    print_success "Directory structure created"
}

# Function to setup MySQL database
setup_database() {
    print_status "Setting up MySQL database..."
    
    # Start MySQL service
    systemctl start mysql
    systemctl enable mysql
    
    # Create databases for each app
    for app in "${!APPS[@]}"; do
        db_name="${app}_db"
        db_user="${app}_user"
        db_password=$(openssl rand -base64 32)
        
        mysql -e "CREATE DATABASE IF NOT EXISTS ${db_name} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
        mysql -e "CREATE USER IF NOT EXISTS '${db_user}'@'localhost' IDENTIFIED BY '${db_password}';"
        mysql -e "GRANT ALL PRIVILEGES ON ${db_name}.* TO '${db_user}'@'localhost';"
        mysql -e "FLUSH PRIVILEGES;"
        
        # Save database credentials
        cat > /etc/django-apps/${app}_db.conf << EOF
DB_NAME=${db_name}
DB_USER=${db_user}
DB_PASSWORD=${db_password}
DB_HOST=localhost
DB_PORT=3306
EOF
        chmod 600 /etc/django-apps/${app}_db.conf
        
        print_success "Database created for $app"
    done
    
    print_success "MySQL setup completed"
}

# Function to setup Redis
setup_redis() {
    print_status "Setting up Redis..."
    
    systemctl start redis-server
    systemctl enable redis-server
    
    # Configure Redis for multiple apps
    cat > /etc/redis/redis.conf << EOF
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

# Security
requirepass $(openssl rand -base64 32)
EOF
    
    systemctl restart redis-server
    print_success "Redis configured"
}

# Function to create virtual environment for an app
create_virtualenv() {
    local app_name=$1
    local app_path=$BASE_DIR/$app_name
    
    print_status "Creating virtual environment for $app_name..."
    
    cd $app_path
    python3 -m venv venv
    source venv/bin/activate
    
    # Install common Django packages
    pip install django gunicorn celery redis mysqlclient
    pip install psycopg2-binary dj-database-url
    pip install whitenoise django-heroku
    
    deactivate
    print_success "Virtual environment created for $app_name"
}

# Function to create systemd service files
create_systemd_services() {
    print_status "Creating systemd service files..."
    
    for app in "${!APPS[@]}"; do
        local app_path=$BASE_DIR/$app
        local app_user="django-${app}"
        local app_group="django-${app}"
        
        # Create user for the app
        useradd -r -s /bin/false -d $app_path $app_user 2>/dev/null || true
        
        # Django service
        cat > $SYSTEMD_DIR/django-${app}.service << EOF
[Unit]
Description=Django ${app} application
After=network.target mysql.service redis.service
Requires=mysql.service redis.service

[Service]
Type=notify
User=${app_user}
Group=${app_group}
WorkingDirectory=${app_path}
Environment=PATH=${app_path}/venv/bin
ExecStart=${app_path}/venv/bin/gunicorn --bind 127.0.0.1:800${app: -1} --workers 3 --timeout 120 --access-logfile ${LOG_DIR}/${app}/access.log --error-logfile ${LOG_DIR}/${app}/error.log weatheralert.wsgi:application
ExecReload=/bin/kill -s HUP \$MAINPID
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

        # Celery service (if needed)
        cat > $SYSTEMD_DIR/celery-${app}.service << EOF
[Unit]
Description=Celery worker for ${app}
After=network.target redis.service
Requires=redis.service

[Service]
Type=forking
User=${app_user}
Group=${app_group}
WorkingDirectory=${app_path}
Environment=PATH=${app_path}/venv/bin
ExecStart=${app_path}/venv/bin/celery -A weatheralert worker --loglevel=info --logfile=${LOG_DIR}/${app}/celery.log --pidfile=/var/run/celery-${app}.pid
ExecReload=/bin/kill -s HUP \$MAINPID
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

        # Celery beat service (if needed)
        cat > $SYSTEMD_DIR/celerybeat-${app}.service << EOF
[Unit]
Description=Celery beat for ${app}
After=network.target redis.service
Requires=redis.service

[Service]
Type=forking
User=${app_user}
Group=${app_group}
WorkingDirectory=${app_path}
Environment=PATH=${app_path}/venv/bin
ExecStart=${app_path}/venv/bin/celery -A weatheralert beat --loglevel=info --logfile=${LOG_DIR}/${app}/celerybeat.log --pidfile=/var/run/celerybeat-${app}.pid
ExecReload=/bin/kill -s HUP \$MAINPID
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

        # Set permissions
        chown -R $app_user:$app_group $app_path
        chown -R $app_user:$app_group $LOG_DIR/$app
        
        systemctl daemon-reload
        print_success "Systemd services created for $app"
    done
}

# Function to create Nginx configuration
create_nginx_config() {
    print_status "Creating Nginx configuration..."
    
    # Remove default nginx site
    rm -f $NGINX_ENABLED_DIR/default
    
    # Create main nginx configuration
    cat > /etc/nginx/nginx.conf << EOF
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    # Basic settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;
    
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # Logging
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml
        image/svg+xml;
    
    # Rate limiting
    limit_req_zone \$binary_remote_addr zone=login:10m rate=5r/m;
    limit_req_zone \$binary_remote_addr zone=api:10m rate=10r/s;
    
    # Include site configurations
    include /etc/nginx/sites-enabled/*;
}
EOF

    # Create configuration for each app
    for app in "${!APPS[@]}"; do
        local app_url="${APPS[$app]}"
        local port="800${app: -1}"
        
        cat > $NGINX_CONF_DIR/$app << EOF
# Nginx configuration for ${app}
server {
    listen 80;
    server_name ${SERVER_IP};
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;
    
    # Static files
    location /static/ {
        alias ${BASE_DIR}/${app}/staticfiles/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    location /media/ {
        alias ${BASE_DIR}/${app}/media/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # Main application
    location /${app_url}/ {
        proxy_pass http://127.0.0.1:${port}/;
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
    location /${app_url}/health/ {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF
        
        # Enable the site
        ln -sf $NGINX_CONF_DIR/$app $NGINX_ENABLED_DIR/$app
        print_success "Nginx configuration created for $app"
    done
    
    # Test nginx configuration
    nginx -t
    systemctl restart nginx
    systemctl enable nginx
    
    print_success "Nginx configuration completed"
}

# Function to setup SSL with Let's Encrypt
setup_ssl() {
    print_status "Setting up SSL certificates..."
    
    # Install certbot if not already installed
    apt install -y certbot python3-certbot-nginx
    
    # Create SSL configuration
    for app in "${!APPS[@]}"; do
        local app_url="${APPS[$app]}"
        
        # Note: For local IP, SSL setup would need a domain name
        # This is a template for when you have a domain
        print_warning "SSL setup requires a domain name. For local IP (${SERVER_IP}), SSL is not applicable."
        print_status "To enable SSL, you would need to:"
        print_status "1. Get a domain name pointing to ${SERVER_IP}"
        print_status "2. Run: certbot --nginx -d yourdomain.com"
    done
}

# Function to create monitoring script
create_monitoring() {
    print_status "Creating monitoring scripts..."
    
    cat > /usr/local/bin/django-monitor.sh << 'EOF'
#!/bin/bash

# Django Apps Monitoring Script
LOG_FILE="/var/log/django-apps/monitor.log"
APPS=("weatherapp" "irmss" "fireguard")

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> $LOG_FILE
}

check_app() {
    local app=$1
    local service="django-${app}"
    
    if systemctl is-active --quiet $service; then
        log_message "✅ $app is running"
        return 0
    else
        log_message "❌ $app is not running - attempting restart"
        systemctl restart $service
        sleep 5
        if systemctl is-active --quiet $service; then
            log_message "✅ $app restarted successfully"
        else
            log_message "🚨 $app failed to restart"
        fi
        return 1
    fi
}

# Check all apps
for app in "${APPS[@]}"; do
    check_app $app
done

# Check system resources
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
MEMORY_USAGE=$(free | awk 'NR==2{printf "%.2f", $3*100/$2}')

if [ $DISK_USAGE -gt 80 ]; then
    log_message "⚠️ High disk usage: ${DISK_USAGE}%"
fi

if (( $(echo "$MEMORY_USAGE > 80" | bc -l) )); then
    log_message "⚠️ High memory usage: ${MEMORY_USAGE}%"
fi
EOF

    chmod +x /usr/local/bin/django-monitor.sh
    
    # Create cron job for monitoring
    cat > /etc/cron.d/django-monitor << EOF
# Django Apps Monitoring
*/5 * * * * root /usr/local/bin/django-monitor.sh
EOF

    print_success "Monitoring scripts created"
}

# Function to create backup script
create_backup_script() {
    print_status "Creating backup scripts..."
    
    cat > /usr/local/bin/django-backup.sh << 'EOF'
#!/bin/bash

BACKUP_DIR="/opt/backups"
DATE=$(date +%Y%m%d_%H%M%S)
APPS=("weatherapp" "irmss" "fireguard")

create_backup() {
    local app=$1
    local backup_path="$BACKUP_DIR/$app/$DATE"
    
    mkdir -p $backup_path
    
    # Backup database
    if [ -f "/etc/django-apps/${app}_db.conf" ]; then
        source /etc/django-apps/${app}_db.conf
        mysqldump -u$DB_USER -p$DB_PASSWORD $DB_NAME > $backup_path/database.sql
    fi
    
    # Backup application files
    cp -r /opt/django-apps/$app $backup_path/
    
    # Backup logs
    cp -r /var/log/django-apps/$app $backup_path/logs/
    
    # Create archive
    cd $BACKUP_DIR/$app
    tar -czf $DATE.tar.gz $DATE/
    rm -rf $DATE/
    
    # Keep only last 7 days of backups
    find $BACKUP_DIR/$app -name "*.tar.gz" -mtime +7 -delete
    
    echo "Backup created: $backup_path/$DATE.tar.gz"
}

# Create backups for all apps
for app in "${APPS[@]}"; do
    create_backup $app
done
EOF

    chmod +x /usr/local/bin/django-backup.sh
    
    # Create cron job for backups
    cat > /etc/cron.d/django-backup << EOF
# Django Apps Backup
0 2 * * * root /usr/local/bin/django-backup.sh
EOF

    print_success "Backup scripts created"
}

# Function to create app management script
create_app_manager() {
    print_status "Creating app management script..."
    
    cat > /usr/local/bin/django-manager.sh << 'EOF'
#!/bin/bash

# Django Apps Management Script

APPS=("weatherapp" "irmss" "fireguard")

show_help() {
    echo "Django Apps Manager"
    echo "Usage: $0 <command> [app_name]"
    echo ""
    echo "Commands:"
    echo "  status [app]     - Show status of app(s)"
    echo "  start [app]      - Start app(s)"
    echo "  stop [app]       - Stop app(s)"
    echo "  restart [app]    - Restart app(s)"
    echo "  logs [app]       - Show logs for app"
    echo "  deploy <app>     - Deploy/update app"
    echo "  remove <app>     - Remove app completely"
    echo ""
    echo "Available apps: ${APPS[*]}"
}

manage_app() {
    local command=$1
    local app=$2
    
    if [ -z "$app" ]; then
        # Apply to all apps
        for app in "${APPS[@]}"; do
            manage_app $command $app
        done
        return
    fi
    
    case $command in
        "status")
            echo "=== Status for $app ==="
            systemctl status django-$app --no-pager
            systemctl status celery-$app --no-pager 2>/dev/null || echo "Celery not configured for $app"
            ;;
        "start")
            echo "Starting $app..."
            systemctl start django-$app
            systemctl start celery-$app 2>/dev/null || true
            systemctl start celerybeat-$app 2>/dev/null || true
            ;;
        "stop")
            echo "Stopping $app..."
            systemctl stop django-$app
            systemctl stop celery-$app 2>/dev/null || true
            systemctl stop celerybeat-$app 2>/dev/null || true
            ;;
        "restart")
            echo "Restarting $app..."
            systemctl restart django-$app
            systemctl restart celery-$app 2>/dev/null || true
            systemctl restart celerybeat-$app 2>/dev/null || true
            ;;
        "logs")
            echo "=== Logs for $app ==="
            tail -f /var/log/django-apps/$app/error.log
            ;;
        "deploy")
            echo "Deploying $app..."
            # This would be customized per app
            echo "Deployment logic for $app would go here"
            ;;
        "remove")
            echo "Removing $app..."
            systemctl stop django-$app
            systemctl disable django-$app
            systemctl stop celery-$app 2>/dev/null || true
            systemctl disable celery-$app 2>/dev/null || true
            systemctl stop celerybeat-$app 2>/dev/null || true
            systemctl disable celerybeat-$app 2>/dev/null || true
            rm -f /etc/systemd/system/django-$app.service
            rm -f /etc/systemd/system/celery-$app.service
            rm -f /etc/systemd/system/celerybeat-$app.service
            rm -f /etc/nginx/sites-enabled/$app
            rm -f /etc/nginx/sites-available/$app
            systemctl daemon-reload
            systemctl reload nginx
            echo "App $app removed. Manual cleanup of /opt/django-apps/$app required."
            ;;
        *)
            echo "Unknown command: $command"
            show_help
            ;;
    esac
}

# Main script logic
if [ $# -lt 1 ]; then
    show_help
    exit 1
fi

command=$1
app=$2

manage_app $command $app
EOF

    chmod +x /usr/local/bin/django-manager.sh
    
    print_success "App management script created"
}

# Function to create environment templates
create_env_templates() {
    print_status "Creating environment templates..."
    
    for app in "${!APPS[@]}"; do
        local app_path=$BASE_DIR/$app
        local app_url="${APPS[$app]}"
        
        cat > $app_path/.env.template << EOF
# Environment configuration for $app
DEBUG=False
SECRET_KEY=your-secret-key-here
ALLOWED_HOSTS=$SERVER_IP,localhost,127.0.0.1

# Database configuration
DB_NAME=${app}_db
DB_USER=${app}_user
DB_PASSWORD=your-db-password-here
DB_HOST=localhost
DB_PORT=3306

# Redis configuration
REDIS_URL=redis://localhost:6379/0

# Email configuration
EMAIL_HOST=smtp.gmail.com
EMAIL_PORT=587
EMAIL_USE_TLS=True
EMAIL_HOST_USER=your-email@gmail.com
EMAIL_HOST_PASSWORD=your-app-password

# SMS configuration (if needed)
SMS_API_URL=your-sms-api-url
SMS_API_KEY=your-sms-api-key

# App-specific settings
APP_NAME=$app
APP_URL=http://$SERVER_IP/$app_url
EOF
        
        print_success "Environment template created for $app"
    done
}

# Main deployment function
main() {
    print_status "Starting Django Multi-App Deployment on Ubuntu Server"
    print_status "Server IP: $SERVER_IP"
    print_status "Supported Apps: ${!APPS[@]}"
    
    check_root
    update_system
    install_dependencies
    create_directories
    setup_database
    setup_redis
    create_systemd_services
    create_nginx_config
    setup_ssl
    create_monitoring
    create_backup_script
    create_app_manager
    create_env_templates
    
    print_success "Deployment completed successfully!"
    print_status ""
    print_status "Next steps:"
    print_status "1. Copy your Django application code to /opt/django-apps/[app_name]/"
    print_status "2. Configure environment variables in /opt/django-apps/[app_name]/.env"
    print_status "3. Install app-specific dependencies in virtual environment"
    print_status "4. Run database migrations"
    print_status "5. Start services: /usr/local/bin/django-manager.sh start [app_name]"
    print_status ""
    print_status "App URLs will be available at:"
    for app in "${!APPS[@]}"; do
        print_status "  http://$SERVER_IP/${APPS[$app]}"
    done
    print_status ""
    print_status "Use 'django-manager.sh' to manage your applications"
}

# Run main function
main "$@"
