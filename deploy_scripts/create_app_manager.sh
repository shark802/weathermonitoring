#!/bin/bash

# =============================================================================
# Application Management Script Creator for Django Applications
# Creates comprehensive management scripts for weatherapp, irmss, fireguard
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
LOG_DIR="/var/log/django-apps"

# App configurations
APPS=("weatherapp" "irmss" "fireguard")

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

# Function to create main application manager
create_main_manager() {
    print_status "Creating main application manager..."
    
    cat > /usr/local/bin/django-manager.sh << 'EOF'
#!/bin/bash

# =============================================================================
# Django Applications Manager
# Comprehensive management script for all Django applications
# =============================================================================

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
APPS=("weatherapp" "irmss" "fireguard")
BASE_DIR="/opt/django-apps"
LOG_DIR="/var/log/django-apps"
SERVER_IP="192.168.3.5"

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

show_help() {
    echo "Django Applications Manager"
    echo "Usage: $0 <command> [app_name] [options]"
    echo ""
    echo "Commands:"
    echo "  status [app]           - Show status of app(s)"
    echo "  start [app]            - Start app(s)"
    echo "  stop [app]             - Stop app(s)"
    echo "  restart [app]          - Restart app(s)"
    echo "  reload [app]           - Reload app configuration"
    echo "  logs [app]             - Show logs for app"
    echo "  health [app]           - Check app health"
    echo "  deploy <app> <env>      - Deploy app with environment"
    echo "  backup [app]           - Backup app data"
    echo "  restore <app> <file>   - Restore app from backup"
    echo "  update <app>           - Update app code"
    echo "  remove <app>           - Remove app completely"
    echo "  config [app]          - Show app configuration"
    echo "  monitor               - Show monitoring dashboard"
    echo "  maintenance <app>     - Put app in maintenance mode"
    echo "  unmaintenance <app>   - Remove app from maintenance mode"
    echo ""
    echo "Available apps: ${APPS[*]}"
    echo ""
    echo "Examples:"
    echo "  $0 status                    # Show status of all apps"
    echo "  $0 start weatherapp         # Start WeatherAlert"
    echo "  $0 restart irmss            # Restart IRMSS"
    echo "  $0 logs fireguard           # Show FireGuard logs"
    echo "  $0 deploy weatherapp prod   # Deploy WeatherAlert to production"
}

check_app_exists() {
    local app=$1
    if [[ ! " ${APPS[@]} " =~ " $app " ]]; then
        print_error "Invalid app name: $app"
        print_error "Available apps: ${APPS[*]}"
        return 1
    fi
    return 0
}

show_status() {
    local app=$1
    
    if [ -z "$app" ]; then
        # Show status for all apps
        echo "=== Django Applications Status ==="
        echo ""
        for app in "${APPS[@]}"; do
            show_status $app
        done
        return
    fi
    
    check_app_exists $app || return 1
    
    echo "=== Status for $app ==="
    
    # Check Django service
    if systemctl is-active --quiet django-$app; then
        print_success "Django service: Running"
    else
        print_error "Django service: Not running"
    fi
    
    # Check Celery service
    if systemctl is-active --quiet celery-$app; then
        print_success "Celery service: Running"
    else
        print_warning "Celery service: Not running"
    fi
    
    # Check Celery Beat service
    if systemctl is-active --quiet celerybeat-$app; then
        print_success "Celery Beat service: Running"
    else
        print_warning "Celery Beat service: Not running"
    fi
    
    # Check health
    local app_url=""
    case $app in
        "weatherapp") app_url="bccweatherapp" ;;
        "irmss") app_url="irrms" ;;
        "fireguard") app_url="fireguard" ;;
    esac
    
    local health_url="http://$SERVER_IP/$app_url/health/"
    local http_status=$(curl -s -o /dev/null -w "%{http_code}" $health_url 2>/dev/null || echo "000")
    
    if [ "$http_status" = "200" ]; then
        print_success "Health check: OK"
    else
        print_error "Health check: Failed (HTTP $http_status)"
    fi
    
    # Check database
    local config_file="/etc/django-apps/${app}_db.conf"
    if [ -f "$config_file" ]; then
        source $config_file
        if mysql -u$DB_USER -p$DB_PASSWORD -e "SELECT 1;" $DB_NAME >/dev/null 2>&1; then
            print_success "Database: Connected"
        else
            print_error "Database: Connection failed"
        fi
    else
        print_warning "Database: Config not found"
    fi
    
    echo ""
}

start_app() {
    local app=$1
    
    if [ -z "$app" ]; then
        # Start all apps
        for app in "${APPS[@]}"; do
            start_app $app
        done
        return
    fi
    
    check_app_exists $app || return 1
    
    print_status "Starting $app..."
    
    systemctl start django-$app
    systemctl start celery-$app 2>/dev/null || true
    systemctl start celerybeat-$app 2>/dev/null || true
    
    sleep 3
    
    if systemctl is-active --quiet django-$app; then
        print_success "$app started successfully"
    else
        print_error "$app failed to start"
        systemctl status django-$app --no-pager
    fi
}

stop_app() {
    local app=$1
    
    if [ -z "$app" ]; then
        # Stop all apps
        for app in "${APPS[@]}"; do
            stop_app $app
        done
        return
    fi
    
    check_app_exists $app || return 1
    
    print_status "Stopping $app..."
    
    systemctl stop django-$app
    systemctl stop celery-$app 2>/dev/null || true
    systemctl stop celerybeat-$app 2>/dev/null || true
    
    print_success "$app stopped"
}

restart_app() {
    local app=$1
    
    if [ -z "$app" ]; then
        # Restart all apps
        for app in "${APPS[@]}"; do
            restart_app $app
        done
        return
    fi
    
    check_app_exists $app || return 1
    
    print_status "Restarting $app..."
    
    stop_app $app
    sleep 2
    start_app $app
}

reload_app() {
    local app=$1
    
    if [ -z "$app" ]; then
        print_error "Please specify an app name for reload"
        return 1
    fi
    
    check_app_exists $app || return 1
    
    print_status "Reloading $app configuration..."
    
    # Reload systemd services
    systemctl daemon-reload
    systemctl reload django-$app 2>/dev/null || systemctl restart django-$app
    
    # Reload nginx
    nginx -t && systemctl reload nginx
    
    print_success "$app configuration reloaded"
}

show_logs() {
    local app=$1
    
    if [ -z "$app" ]; then
        print_error "Please specify an app name for logs"
        return 1
    fi
    
    check_app_exists $app || return 1
    
    print_status "Showing logs for $app (Press Ctrl+C to exit)..."
    tail -f $LOG_DIR/$app/error.log
}

check_health() {
    local app=$1
    
    if [ -z "$app" ]; then
        # Check health for all apps
        for app in "${APPS[@]}"; do
            check_health $app
        done
        return
    fi
    
    check_app_exists $app || return 1
    
    local app_url=""
    case $app in
        "weatherapp") app_url="bccweatherapp" ;;
        "irmss") app_url="irrms" ;;
        "fireguard") app_url="fireguard" ;;
    esac
    
    print_status "Checking health for $app..."
    
    local health_url="http://$SERVER_IP/$app_url/health/"
    local http_status=$(curl -s -o /dev/null -w "%{http_code}" $health_url 2>/dev/null || echo "000")
    
    if [ "$http_status" = "200" ]; then
        print_success "$app health check: OK"
        return 0
    else
        print_error "$app health check: Failed (HTTP $http_status)"
        return 1
    fi
}

deploy_app() {
    local app=$1
    local env=$2
    
    if [ -z "$app" ] || [ -z "$env" ]; then
        print_error "Please specify app name and environment"
        print_error "Usage: $0 deploy <app> <env>"
        return 1
    fi
    
    check_app_exists $app || return 1
    
    print_status "Deploying $app in $env environment..."
    
    # Use the deployment script
    /usr/local/bin/deploy-app.sh $app $env
}

backup_app() {
    local app=$1
    
    if [ -z "$app" ]; then
        # Backup all apps
        for app in "${APPS[@]}"; do
            backup_app $app
        done
        return
    fi
    
    check_app_exists $app || return 1
    
    print_status "Creating backup for $app..."
    
    /usr/local/bin/backup-all.sh
}

restore_app() {
    local app=$1
    local backup_file=$2
    
    if [ -z "$app" ] || [ -z "$backup_file" ]; then
        print_error "Please specify app name and backup file"
        print_error "Usage: $0 restore <app> <backup_file>"
        return 1
    fi
    
    check_app_exists $app || return 1
    
    print_status "Restoring $app from $backup_file..."
    
    /usr/local/bin/restore-app.sh $app $backup_file
}

update_app() {
    local app=$1
    
    if [ -z "$app" ]; then
        print_error "Please specify an app name for update"
        return 1
    fi
    
    check_app_exists $app || return 1
    
    print_status "Updating $app..."
    
    # Stop the app
    stop_app $app
    
    # Update code (this would be customized per app)
    print_status "Updating application code..."
    # git pull, rsync, or other update mechanism would go here
    
    # Install dependencies
    print_status "Installing dependencies..."
    cd $BASE_DIR/$app
    source venv/bin/activate
    pip install -r requirements.txt
    deactivate
    
    # Run migrations
    print_status "Running database migrations..."
    cd $BASE_DIR/$app
    source venv/bin/activate
    python manage.py migrate
    python manage.py collectstatic --noinput
    deactivate
    
    # Start the app
    start_app $app
    
    print_success "$app updated successfully"
}

remove_app() {
    local app=$1
    
    if [ -z "$app" ]; then
        print_error "Please specify an app name for removal"
        return 1
    fi
    
    check_app_exists $app || return 1
    
    print_warning "This will completely remove $app and all its data!"
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        print_status "Removal cancelled"
        return 0
    fi
    
    print_status "Removing $app..."
    
    # Stop services
    stop_app $app
    
    # Disable services
    systemctl disable django-$app
    systemctl disable celery-$app 2>/dev/null || true
    systemctl disable celerybeat-$app 2>/dev/null || true
    
    # Remove service files
    rm -f /etc/systemd/system/django-$app.service
    rm -f /etc/systemd/system/celery-$app.service
    rm -f /etc/systemd/system/celerybeat-$app.service
    
    # Remove nginx configuration
    rm -f /etc/nginx/sites-enabled/$app
    rm -f /etc/nginx/sites-available/$app
    
    # Remove application directory
    rm -rf $BASE_DIR/$app
    
    # Remove logs
    rm -rf $LOG_DIR/$app
    
    # Remove database (optional)
    read -p "Remove database for $app? (yes/no): " remove_db
    if [ "$remove_db" = "yes" ]; then
        local config_file="/etc/django-apps/${app}_db.conf"
        if [ -f "$config_file" ]; then
            source $config_file
            mysql -u root -p -e "DROP DATABASE IF EXISTS $DB_NAME;"
            mysql -u root -p -e "DROP USER IF EXISTS '$DB_USER'@'localhost';"
        fi
        rm -f $config_file
    fi
    
    # Reload systemd and nginx
    systemctl daemon-reload
    systemctl reload nginx
    
    print_success "$app removed successfully"
}

show_config() {
    local app=$1
    
    if [ -z "$app" ]; then
        print_error "Please specify an app name for configuration"
        return 1
    fi
    
    check_app_exists $app || return 1
    
    print_status "Configuration for $app:"
    echo ""
    
    # Show environment configuration
    if [ -f "$BASE_DIR/$app/.env" ]; then
        echo "=== Environment Configuration ==="
        cat $BASE_DIR/$app/.env
        echo ""
    fi
    
    # Show database configuration
    local config_file="/etc/django-apps/${app}_db.conf"
    if [ -f "$config_file" ]; then
        echo "=== Database Configuration ==="
        cat $config_file
        echo ""
    fi
    
    # Show service status
    echo "=== Service Status ==="
    systemctl status django-$app --no-pager
    echo ""
}

show_monitor() {
    print_status "Opening monitoring dashboard..."
    
    # Check if monitoring dashboard exists
    if [ -f "/var/www/html/monitoring.html" ]; then
        print_status "Monitoring dashboard available at: http://$SERVER_IP/monitoring.html"
    else
        print_warning "Monitoring dashboard not found. Run setup_monitoring.sh first."
    fi
    
    # Show system resources
    echo "=== System Resources ==="
    echo "CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')%"
    echo "Memory Usage: $(free | awk 'NR==2{printf "%.2f", $3*100/$2}')%"
    echo "Disk Usage: $(df / | awk 'NR==2 {print $5}')"
    echo "Load Average: $(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}')"
    echo ""
    
    # Show app status
    show_status
}

maintenance_mode() {
    local app=$1
    
    if [ -z "$app" ]; then
        print_error "Please specify an app name for maintenance mode"
        return 1
    fi
    
    check_app_exists $app || return 1
    
    print_status "Putting $app in maintenance mode..."
    
    # Create maintenance page
    cat > $BASE_DIR/$app/maintenance.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Maintenance Mode</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        .container { max-width: 600px; margin: 0 auto; }
        h1 { color: #e74c3c; }
        p { color: #7f8c8d; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Application Under Maintenance</h1>
        <p>We are currently performing maintenance on this application.</p>
        <p>Please check back later.</p>
        <p>Thank you for your patience.</p>
    </div>
</body>
</html>
EOF
    
    # Update nginx configuration to show maintenance page
    # This would require modifying the nginx config for the specific app
    
    print_success "$app is now in maintenance mode"
}

unmaintenance_mode() {
    local app=$1
    
    if [ -z "$app" ]; then
        print_error "Please specify an app name to remove from maintenance mode"
        return 1
    fi
    
    check_app_exists $app || return 1
    
    print_status "Removing $app from maintenance mode..."
    
    # Remove maintenance page
    rm -f $BASE_DIR/$app/maintenance.html
    
    # Restore normal nginx configuration
    # This would require restoring the normal nginx config for the specific app
    
    print_success "$app is no longer in maintenance mode"
}

# Main script logic
if [ $# -lt 1 ]; then
    show_help
    exit 1
fi

command=$1
app=$2
option=$3

case $command in
    "status")
        show_status $app
        ;;
    "start")
        start_app $app
        ;;
    "stop")
        stop_app $app
        ;;
    "restart")
        restart_app $app
        ;;
    "reload")
        reload_app $app
        ;;
    "logs")
        show_logs $app
        ;;
    "health")
        check_health $app
        ;;
    "deploy")
        deploy_app $app $option
        ;;
    "backup")
        backup_app $app
        ;;
    "restore")
        restore_app $app $option
        ;;
    "update")
        update_app $app
        ;;
    "remove")
        remove_app $app
        ;;
    "config")
        show_config $app
        ;;
    "monitor")
        show_monitor
        ;;
    "maintenance")
        maintenance_mode $app
        ;;
    "unmaintenance")
        unmaintenance_mode $app
        ;;
    *)
        print_error "Unknown command: $command"
        show_help
        ;;
esac
EOF

    chmod +x /usr/local/bin/django-manager.sh
    
    print_success "Main application manager created"
}

# Function to create quick management scripts
create_quick_scripts() {
    print_status "Creating quick management scripts..."
    
    # Start all apps
    cat > /usr/local/bin/start-all-apps.sh << 'EOF'
#!/bin/bash
echo "Starting all Django applications..."
/usr/local/bin/django-manager.sh start
EOF
    chmod +x /usr/local/bin/start-all-apps.sh
    
    # Stop all apps
    cat > /usr/local/bin/stop-all-apps.sh << 'EOF'
#!/bin/bash
echo "Stopping all Django applications..."
/usr/local/bin/django-manager.sh stop
EOF
    chmod +x /usr/local/bin/stop-all-apps.sh
    
    # Restart all apps
    cat > /usr/local/bin/restart-all-apps.sh << 'EOF'
#!/bin/bash
echo "Restarting all Django applications..."
/usr/local/bin/django-manager.sh restart
EOF
    chmod +x /usr/local/bin/restart-all-apps.sh
    
    # Status check
    cat > /usr/local/bin/check-all-apps.sh << 'EOF'
#!/bin/bash
echo "Checking status of all Django applications..."
/usr/local/bin/django-manager.sh status
EOF
    chmod +x /usr/local/bin/check-all-apps.sh
    
    # Health check
    cat > /usr/local/bin/health-check-all.sh << 'EOF'
#!/bin/bash
echo "Performing health check on all Django applications..."
/usr/local/bin/django-manager.sh health
EOF
    chmod +x /usr/local/bin/health-check-all.sh
    
    print_success "Quick management scripts created"
}

# Function to create service management aliases
create_service_aliases() {
    print_status "Creating service management aliases..."
    
    # Create aliases for common operations
    cat > /etc/profile.d/django-aliases.sh << 'EOF'
# Django Applications Management Aliases
alias django-status='/usr/local/bin/django-manager.sh status'
alias django-start='/usr/local/bin/django-manager.sh start'
alias django-stop='/usr/local/bin/django-manager.sh stop'
alias django-restart='/usr/local/bin/django-manager.sh restart'
alias django-logs='/usr/local/bin/django-manager.sh logs'
alias django-health='/usr/local/bin/django-manager.sh health'
alias django-monitor='/usr/local/bin/django-manager.sh monitor'

# Quick aliases for specific apps
alias weather-status='/usr/local/bin/django-manager.sh status weatherapp'
alias weather-start='/usr/local/bin/django-manager.sh start weatherapp'
alias weather-stop='/usr/local/bin/django-manager.sh stop weatherapp'
alias weather-restart='/usr/local/bin/django-manager.sh restart weatherapp'
alias weather-logs='/usr/local/bin/django-manager.sh logs weatherapp'

alias irmss-status='/usr/local/bin/django-manager.sh status irmss'
alias irmss-start='/usr/local/bin/django-manager.sh start irmss'
alias irmss-stop='/usr/local/bin/django-manager.sh stop irmss'
alias irmss-restart='/usr/local/bin/django-manager.sh restart irmss'
alias irmss-logs='/usr/local/bin/django-manager.sh logs irmss'

alias fireguard-status='/usr/local/bin/django-manager.sh status fireguard'
alias fireguard-start='/usr/local/bin/django-manager.sh start fireguard'
alias fireguard-stop='/usr/local/bin/django-manager.sh stop fireguard'
alias fireguard-restart='/usr/local/bin/django-manager.sh restart fireguard'
alias fireguard-logs='/usr/local/bin/django-manager.sh logs fireguard'
EOF

    print_success "Service management aliases created"
}

# Function to create desktop shortcuts (if GUI is available)
create_desktop_shortcuts() {
    print_status "Creating desktop shortcuts..."
    
    # Create desktop directory
    mkdir -p /usr/share/applications
    
    # Django Manager desktop file
    cat > /usr/share/applications/django-manager.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Django Applications Manager
Comment=Manage Django applications on the server
Exec=/usr/local/bin/django-manager.sh
Icon=applications-development
Terminal=true
Categories=Development;System;
EOF

    # WeatherAlert desktop file
    cat > /usr/share/applications/weatherapp.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=WeatherAlert
Comment=Weather monitoring and alert system
Exec=firefox http://192.168.3.5/bccweatherapp/
Icon=weather-storm
Terminal=false
Categories=Network;Weather;
EOF

    # IRMSS desktop file
    cat > /usr/share/applications/irmss.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=IRMSS
Comment=Integrated Resource Management System
Exec=firefox http://192.168.3.5/irrms/
Icon=applications-office
Terminal=false
Categories=Office;Network;
EOF

    # FireGuard desktop file
    cat > /usr/share/applications/fireguard.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=FireGuard
Comment=Fire detection and monitoring system
Exec=firefox http://192.168.3.5/fireguard/
Icon=applications-games
Terminal=false
Categories=Network;Security;
EOF

    print_success "Desktop shortcuts created"
}

# Function to create systemd service for the manager
create_manager_service() {
    print_status "Creating systemd service for application manager..."
    
    cat > /etc/systemd/system/django-manager.service << 'EOF'
[Unit]
Description=Django Applications Manager Service
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/django-manager.sh start
ExecStop=/usr/local/bin/django-manager.sh stop
ExecReload=/usr/local/bin/django-manager.sh restart

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable django-manager.service
    
    print_success "Django manager service created"
}

# Main function
main() {
    print_status "Starting application management script creation..."
    
    check_root
    create_main_manager
    create_quick_scripts
    create_service_aliases
    create_desktop_shortcuts
    create_manager_service
    
    print_success "Application management scripts created successfully!"
    print_status ""
    print_status "Available management commands:"
    print_status "  /usr/local/bin/django-manager.sh <command> [app] [options]"
    print_status ""
    print_status "Quick commands:"
    print_status "  /usr/local/bin/start-all-apps.sh"
    print_status "  /usr/local/bin/stop-all-apps.sh"
    print_status "  /usr/local/bin/restart-all-apps.sh"
    print_status "  /usr/local/bin/check-all-apps.sh"
    print_status "  /usr/local/bin/health-check-all.sh"
    print_status ""
    print_status "Service aliases available:"
    print_status "  django-status, django-start, django-stop, django-restart"
    print_status "  weather-status, weather-start, weather-stop, weather-restart"
    print_status "  irmss-status, irmss-start, irmss-stop, irmss-restart"
    print_status "  fireguard-status, fireguard-start, fireguard-stop, fireguard-restart"
    print_status ""
    print_status "Application URLs:"
    print_status "  WeatherAlert: http://$SERVER_IP/bccweatherapp"
    print_status "  IRMSS: http://$SERVER_IP/irrms"
    print_status "  FireGuard: http://$SERVER_IP/fireguard"
    print_status ""
    print_status "Use 'django-manager.sh help' for detailed usage information"
}

# Run main function
main "$@"
