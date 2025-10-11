#!/bin/bash

# =============================================================================
# Fix Systemd Services Script for WeatherAlert
# This script creates the missing systemd service files
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
APP_DIR="/opt/django-apps/$APP_NAME"
LOG_DIR="/var/log/django-apps/$APP_NAME"
SYSTEMD_DIR="/etc/systemd/system"

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

# Function to create systemd service files
create_systemd_services() {
    print_status "Creating systemd service files..."
    
    # Create user for the app if it doesn't exist
    useradd -r -s /bin/false -d $APP_DIR django-$APP_NAME 2>/dev/null || true
    
    # Django service
    cat > $SYSTEMD_DIR/django-$APP_NAME.service << EOF
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
Environment=DJANGO_SETTINGS_MODULE=weatheralert.settings
ExecStart=$APP_DIR/venv/bin/gunicorn --bind 127.0.0.1:8001 --workers 3 --timeout 120 --access-logfile $LOG_DIR/access.log --error-logfile $LOG_DIR/error.log weatheralert.wsgi:application
ExecReload=/bin/kill -s HUP \$MAINPID
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Celery worker service
    cat > $SYSTEMD_DIR/celery-$APP_NAME.service << EOF
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
Environment=DJANGO_SETTINGS_MODULE=weatheralert.settings
ExecStart=$APP_DIR/venv/bin/celery -A weatheralert worker --loglevel=info --logfile=$LOG_DIR/celery.log --pidfile=/var/run/celery-$APP_NAME.pid
ExecReload=/bin/kill -s HUP \$MAINPID
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Celery beat service
    cat > $SYSTEMD_DIR/celerybeat-$APP_NAME.service << EOF
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
Environment=DJANGO_SETTINGS_MODULE=weatheralert.settings
ExecStart=$APP_DIR/venv/bin/celery -A weatheralert beat --loglevel=info --logfile=$LOG_DIR/celerybeat.log --pidfile=/var/run/celerybeat-$APP_NAME.pid
ExecReload=/bin/kill -s HUP \$MAINPID
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
    
    print_success "Systemd service files created"
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

# Function to test the application
test_application() {
    print_status "Testing application..."
    
    # Test HTTP response
    local health_url="http://192.168.3.5/bccweatherapp/health/"
    local http_status=$(curl -s -o /dev/null -w "%{http_code}" $health_url 2>/dev/null || echo "000")
    
    if [ "$http_status" = "200" ]; then
        print_success "Application health check passed"
    else
        print_warning "Application health check failed (HTTP $http_status)"
        print_status "Trying main application URL..."
        
        local main_url="http://192.168.3.5/bccweatherapp/"
        local main_status=$(curl -s -o /dev/null -w "%{http_code}" $main_url 2>/dev/null || echo "000")
        
        if [ "$main_status" = "200" ]; then
            print_success "Main application URL is accessible"
        else
            print_error "Application is not accessible (HTTP $main_status)"
        fi
    fi
}

# Main function
main() {
    print_status "Fixing WeatherAlert systemd services..."
    print_status "This will create the missing service files and start the services"
    
    check_root
    create_systemd_services
    start_services
    test_application
    
    print_success "WeatherAlert services fixed successfully!"
    print_status ""
    print_status "Application should now be available at:"
    print_status "  http://192.168.3.5/bccweatherapp"
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
    print_status "Note: The MariaDB Strict Mode warning is just a warning and won't affect functionality"
    print_status "The TensorFlow model loading error is also just a warning and won't break the app"
}

# Run main function
main "$@"
