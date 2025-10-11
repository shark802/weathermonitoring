#!/bin/bash

# =============================================================================
# Comprehensive Monitoring and Backup Setup Script for Django Applications
# Monitors system resources, application health, and creates automated backups
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
BACKUP_DIR="/opt/backups"
MONITORING_DIR="/opt/monitoring"

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

# Function to install monitoring dependencies
install_monitoring_deps() {
    print_status "Installing monitoring dependencies..."
    
    # Update package list
    apt update
    
    # Install monitoring tools
    apt install -y htop iotop nethogs
    apt install -y sysstat
    apt install -y logrotate
    apt install -y rsync
    apt install -y jq curl wget
    
    # Install Python monitoring libraries
    pip3 install psutil requests
    
    print_success "Monitoring dependencies installed"
}

# Function to create monitoring directory structure
create_monitoring_structure() {
    print_status "Creating monitoring directory structure..."
    
    mkdir -p $MONITORING_DIR
    mkdir -p $MONITORING_DIR/scripts
    mkdir -p $MONITORING_DIR/configs
    mkdir -p $MONITORING_DIR/alerts
    mkdir -p $BACKUP_DIR/apps
    mkdir -p $BACKUP_DIR/databases
    mkdir -p $BACKUP_DIR/logs
    
    # Create log directories for each app
    for app in "${APPS[@]}"; do
        mkdir -p $LOG_DIR/$app
        mkdir -p $BACKUP_DIR/apps/$app
    done
    
    print_success "Monitoring directory structure created"
}

# Function to create system monitoring script
create_system_monitor() {
    print_status "Creating system monitoring script..."
    
    cat > /usr/local/bin/system-monitor.sh << 'EOF'
#!/bin/bash

# System Monitoring Script for Django Applications
LOG_FILE="/var/log/django-apps/system-monitor.log"
ALERT_FILE="/opt/monitoring/alerts/system-alerts.log"

# Thresholds
CPU_THRESHOLD=80
MEMORY_THRESHOLD=85
DISK_THRESHOLD=90
LOAD_THRESHOLD=5.0

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> $LOG_FILE
}

log_alert() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ALERT: $1" >> $ALERT_FILE
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ALERT: $1" >> $LOG_FILE
}

check_cpu() {
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')
    local cpu_int=${cpu_usage%.*}
    
    if [ $cpu_int -gt $CPU_THRESHOLD ]; then
        log_alert "High CPU usage: ${cpu_usage}%"
        return 1
    else
        log_message "CPU usage: ${cpu_usage}%"
        return 0
    fi
}

check_memory() {
    local memory_usage=$(free | awk 'NR==2{printf "%.2f", $3*100/$2}')
    local memory_int=${memory_usage%.*}
    
    if [ $memory_int -gt $MEMORY_THRESHOLD ]; then
        log_alert "High memory usage: ${memory_usage}%"
        return 1
    else
        log_message "Memory usage: ${memory_usage}%"
        return 0
    fi
}

check_disk() {
    local disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [ $disk_usage -gt $DISK_THRESHOLD ]; then
        log_alert "High disk usage: ${disk_usage}%"
        return 1
    else
        log_message "Disk usage: ${disk_usage}%"
        return 0
    fi
}

check_load() {
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    local load_int=${load_avg%.*}
    
    if (( $(echo "$load_avg > $LOAD_THRESHOLD" | bc -l) )); then
        log_alert "High load average: ${load_avg}"
        return 1
    else
        log_message "Load average: ${load_avg}"
        return 0
    fi
}

check_network() {
    local network_status=$(ping -c 1 8.8.8.8 >/dev/null 2>&1 && echo "OK" || echo "FAIL")
    
    if [ "$network_status" = "FAIL" ]; then
        log_alert "Network connectivity issues"
        return 1
    else
        log_message "Network: OK"
        return 0
    fi
}

check_services() {
    local services=("nginx" "mysql" "redis-server")
    local failed_services=()
    
    for service in "${services[@]}"; do
        if ! systemctl is-active --quiet $service; then
            failed_services+=($service)
        fi
    done
    
    if [ ${#failed_services[@]} -gt 0 ]; then
        log_alert "Failed services: ${failed_services[*]}"
        return 1
    else
        log_message "All system services running"
        return 0
    fi
}

# Main monitoring function
main() {
    log_message "=== System monitoring check started ==="
    
    local alerts=0
    
    check_cpu || ((alerts++))
    check_memory || ((alerts++))
    check_disk || ((alerts++))
    check_load || ((alerts++))
    check_network || ((alerts++))
    check_services || ((alerts++))
    
    if [ $alerts -gt 0 ]; then
        log_alert "System monitoring detected $alerts issues"
    else
        log_message "System monitoring: All checks passed"
    fi
    
    log_message "=== System monitoring check completed ==="
}

main
EOF

    chmod +x /usr/local/bin/system-monitor.sh
    
    print_success "System monitoring script created"
}

# Function to create application monitoring script
create_app_monitor() {
    print_status "Creating application monitoring script..."
    
    cat > /usr/local/bin/app-monitor.sh << 'EOF'
#!/bin/bash

# Application Monitoring Script for Django Applications
LOG_FILE="/var/log/django-apps/app-monitor.log"
ALERT_FILE="/opt/monitoring/alerts/app-alerts.log"
APPS=("weatherapp" "irmss" "fireguard")

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> $LOG_FILE
}

log_alert() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ALERT: $1" >> $ALERT_FILE
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ALERT: $1" >> $LOG_FILE
}

check_app_service() {
    local app=$1
    local service="django-$app"
    
    if systemctl is-active --quiet $service; then
        log_message "✅ $app service is running"
        return 0
    else
        log_alert "❌ $app service is not running"
        
        # Attempt to restart
        systemctl restart $service
        sleep 5
        
        if systemctl is-active --quiet $service; then
            log_message "✅ $app service restarted successfully"
        else
            log_alert "🚨 $app service failed to restart"
        fi
        return 1
    fi
}

check_app_health() {
    local app=$1
    local app_url=""
    
    case $app in
        "weatherapp") app_url="bccweatherapp" ;;
        "irmss") app_url="irrms" ;;
        "fireguard") app_url="fireguard" ;;
    esac
    
    local health_url="http://192.168.3.5/$app_url/health/"
    local http_status=$(curl -s -o /dev/null -w "%{http_code}" $health_url || echo "000")
    
    if [ "$http_status" = "200" ]; then
        log_message "✅ $app health check passed"
        return 0
    else
        log_alert "❌ $app health check failed (HTTP $http_status)"
        return 1
    fi
}

check_app_logs() {
    local app=$1
    local log_file="/var/log/django-apps/$app/error.log"
    
    if [ ! -f "$log_file" ]; then
        log_message "⚠️ Log file not found for $app"
        return 0
    fi
    
    # Check for errors in the last 5 minutes
    local error_count=$(find $log_file -mmin -5 -exec grep -c "ERROR" {} \; 2>/dev/null || echo "0")
    
    if [ $error_count -gt 10 ]; then
        log_alert "❌ High error rate in $app logs: $error_count errors in last 5 minutes"
        return 1
    else
        log_message "✅ $app logs: $error_count errors in last 5 minutes"
        return 0
    fi
}

check_app_database() {
    local app=$1
    local config_file="/etc/django-apps/${app}_db.conf"
    
    if [ ! -f "$config_file" ]; then
        log_message "⚠️ Database config not found for $app"
        return 0
    fi
    
    source $config_file
    
    if mysql -u$DB_USER -p$DB_PASSWORD -e "SELECT 1;" $DB_NAME >/dev/null 2>&1; then
        log_message "✅ $app database connection OK"
        return 0
    else
        log_alert "❌ $app database connection failed"
        return 1
    fi
}

check_app_disk_usage() {
    local app=$1
    local app_dir="/opt/django-apps/$app"
    
    if [ ! -d "$app_dir" ]; then
        log_message "⚠️ App directory not found for $app"
        return 0
    fi
    
    local disk_usage=$(du -sh $app_dir | awk '{print $1}')
    local disk_size=$(du -s $app_dir | awk '{print $1}')
    
    # Alert if app directory is larger than 1GB
    if [ $disk_size -gt 1048576 ]; then
        log_alert "⚠️ $app directory is large: $disk_usage"
        return 1
    else
        log_message "✅ $app directory size: $disk_usage"
        return 0
    fi
}

# Main monitoring function
main() {
    log_message "=== Application monitoring check started ==="
    
    local total_alerts=0
    
    for app in "${APPS[@]}"; do
        log_message "Checking $app..."
        
        local app_alerts=0
        
        check_app_service $app || ((app_alerts++))
        check_app_health $app || ((app_alerts++))
        check_app_logs $app || ((app_alerts++))
        check_app_database $app || ((app_alerts++))
        check_app_disk_usage $app || ((app_alerts++))
        
        if [ $app_alerts -gt 0 ]; then
            log_alert "$app monitoring detected $app_alerts issues"
            ((total_alerts += app_alerts))
        else
            log_message "✅ $app monitoring: All checks passed"
        fi
    done
    
    if [ $total_alerts -gt 0 ]; then
        log_alert "Application monitoring detected $total_alerts total issues"
    else
        log_message "Application monitoring: All checks passed"
    fi
    
    log_message "=== Application monitoring check completed ==="
}

main
EOF

    chmod +x /usr/local/bin/app-monitor.sh
    
    print_success "Application monitoring script created"
}

# Function to create backup script
create_backup_script() {
    print_status "Creating comprehensive backup script..."
    
    cat > /usr/local/bin/backup-all.sh << 'EOF'
#!/bin/bash

# Comprehensive Backup Script for Django Applications
BACKUP_DIR="/opt/backups"
DATE=$(date +%Y%m%d_%H%M%S)
APPS=("weatherapp" "irmss" "fireguard")
RETENTION_DAYS=30

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

create_app_backup() {
    local app=$1
    local backup_path="$BACKUP_DIR/apps/$app/$DATE"
    
    log_message "Creating backup for $app..."
    
    mkdir -p $backup_path
    
    # Backup application files
    if [ -d "/opt/django-apps/$app" ]; then
        cp -r /opt/django-apps/$app $backup_path/
        log_message "✅ Application files backed up for $app"
    else
        log_message "⚠️ Application directory not found for $app"
    fi
    
    # Backup logs
    if [ -d "/var/log/django-apps/$app" ]; then
        cp -r /var/log/django-apps/$app $backup_path/logs/
        log_message "✅ Logs backed up for $app"
    fi
    
    # Backup database
    local config_file="/etc/django-apps/${app}_db.conf"
    if [ -f "$config_file" ]; then
        source $config_file
        mysqldump -u$DB_USER -p$DB_PASSWORD \
            --single-transaction \
            --routines \
            --triggers \
            --events \
            --hex-blob \
            --opt \
            $DB_NAME > $backup_path/database.sql
        log_message "✅ Database backed up for $app"
    else
        log_message "⚠️ Database config not found for $app"
    fi
    
    # Create compressed archive
    cd $BACKUP_DIR/apps/$app
    tar -czf $DATE.tar.gz $DATE/
    rm -rf $DATE/
    
    log_message "✅ Backup archive created: $DATE.tar.gz"
}

create_system_backup() {
    local backup_path="$BACKUP_DIR/system/$DATE"
    
    log_message "Creating system backup..."
    
    mkdir -p $backup_path
    
    # Backup system configurations
    cp -r /etc/nginx $backup_path/
    cp -r /etc/systemd/system $backup_path/
    cp -r /etc/django-apps $backup_path/
    
    # Backup SSL certificates
    if [ -d "/etc/letsencrypt" ]; then
        cp -r /etc/letsencrypt $backup_path/
    fi
    
    # Create compressed archive
    cd $BACKUP_DIR/system
    tar -czf $DATE.tar.gz $DATE/
    rm -rf $DATE/
    
    log_message "✅ System backup created: $DATE.tar.gz"
}

cleanup_old_backups() {
    log_message "Cleaning up old backups (older than $RETENTION_DAYS days)..."
    
    find $BACKUP_DIR -name "*.tar.gz" -mtime +$RETENTION_DAYS -delete
    find $BACKUP_DIR -type d -empty -delete
    
    log_message "✅ Old backups cleaned up"
}

# Main backup function
main() {
    log_message "=== Backup process started ==="
    
    # Create backup directories
    mkdir -p $BACKUP_DIR/apps
    mkdir -p $BACKUP_DIR/system
    mkdir -p $BACKUP_DIR/databases
    
    # Backup each application
    for app in "${APPS[@]}"; do
        create_app_backup $app
    done
    
    # Create system backup
    create_system_backup
    
    # Cleanup old backups
    cleanup_old_backups
    
    log_message "=== Backup process completed ==="
}

main
EOF

    chmod +x /usr/local/bin/backup-all.sh
    
    print_success "Backup script created"
}

# Function to create restore script
create_restore_script() {
    print_status "Creating restore script..."
    
    cat > /usr/local/bin/restore-app.sh << 'EOF'
#!/bin/bash

# Application Restore Script for Django Applications
BACKUP_DIR="/opt/backups"

show_usage() {
    echo "Application Restore Script"
    echo "Usage: $0 <app_name> <backup_file> [--force]"
    echo ""
    echo "Available apps: weatherapp, irmss, fireguard"
    echo "Backup files are located in: $BACKUP_DIR/apps/<app_name>/"
    echo ""
    echo "Options:"
    echo "  --force    Force restore without confirmation"
    echo ""
    echo "Example: $0 weatherapp weatherapp_20240101_120000.tar.gz"
}

restore_app() {
    local app=$1
    local backup_file=$2
    local force=$3
    
    # Check if backup file exists
    local backup_path="$BACKUP_DIR/apps/$app/$backup_file"
    if [ ! -f "$backup_path" ]; then
        echo "❌ Backup file not found: $backup_path"
        return 1
    fi
    
    # Confirm restore
    if [ "$force" != "--force" ]; then
        echo "This will restore the application $app from backup: $backup_file"
        echo "This will overwrite the current application files."
        echo ""
        read -p "Are you sure you want to continue? (yes/no): " confirm
        
        if [ "$confirm" != "yes" ]; then
            echo "Restore cancelled"
            return 0
        fi
    fi
    
    echo "Starting restore for $app..."
    
    # Stop the application
    echo "Stopping application services..."
    systemctl stop django-$app 2>/dev/null || true
    systemctl stop celery-$app 2>/dev/null || true
    systemctl stop celerybeat-$app 2>/dev/null || true
    
    # Create current backup before restore
    echo "Creating current backup before restore..."
    /usr/local/bin/backup-all.sh
    
    # Extract backup
    local temp_dir="/tmp/restore_$app"
    mkdir -p $temp_dir
    cd $temp_dir
    tar -xzf $backup_path
    
    # Restore application files
    echo "Restoring application files..."
    if [ -d "$app" ]; then
        rm -rf /opt/django-apps/$app
        mv $app /opt/django-apps/
        chown -R django-$app:django-$app /opt/django-apps/$app
    fi
    
    # Restore logs
    if [ -d "logs" ]; then
        cp -r logs/* /var/log/django-apps/$app/ 2>/dev/null || true
    fi
    
    # Restore database
    if [ -f "database.sql" ]; then
        echo "Restoring database..."
        local config_file="/etc/django-apps/${app}_db.conf"
        if [ -f "$config_file" ]; then
            source $config_file
            mysql -u$DB_USER -p$DB_PASSWORD $DB_NAME < database.sql
        fi
    fi
    
    # Cleanup
    rm -rf $temp_dir
    
    # Start the application
    echo "Starting application services..."
    systemctl start django-$app
    systemctl start celery-$app 2>/dev/null || true
    systemctl start celerybeat-$app 2>/dev/null || true
    
    echo "✅ Restore completed for $app"
}

# Main script logic
if [ $# -lt 2 ]; then
    show_usage
    exit 1
fi

app=$1
backup_file=$2
force=$3

restore_app $app $backup_file $force
EOF

    chmod +x /usr/local/bin/restore-app.sh
    
    print_success "Restore script created"
}

# Function to create log rotation configuration
create_log_rotation() {
    print_status "Creating log rotation configuration..."
    
    cat > /etc/logrotate.d/django-apps << EOF
# Log rotation for Django applications
/var/log/django-apps/*/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 root root
    postrotate
        systemctl reload nginx > /dev/null 2>&1 || true
    endscript
}

/var/log/django-apps/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 root root
}

/opt/monitoring/alerts/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 644 root root
}
EOF

    print_success "Log rotation configuration created"
}

# Function to create monitoring dashboard
create_monitoring_dashboard() {
    print_status "Creating monitoring dashboard..."
    
    cat > /var/www/html/monitoring.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Django Applications Monitoring Dashboard</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; }
        .header { background: #2c3e50; color: white; padding: 20px; border-radius: 5px; margin-bottom: 20px; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
        .card { background: white; padding: 20px; border-radius: 5px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
        .status { padding: 5px 10px; border-radius: 3px; color: white; font-weight: bold; }
        .status.ok { background: #27ae60; }
        .status.warning { background: #f39c12; }
        .status.error { background: #e74c3c; }
        .metric { display: flex; justify-content: space-between; margin: 10px 0; }
        .refresh-btn { background: #3498db; color: white; padding: 10px 20px; border: none; border-radius: 3px; cursor: pointer; }
        .refresh-btn:hover { background: #2980b9; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Django Applications Monitoring Dashboard</h1>
            <p>Server: 192.168.3.5 | Last Updated: <span id="lastUpdate"></span></p>
            <button class="refresh-btn" onclick="location.reload()">Refresh</button>
        </div>
        
        <div class="grid">
            <div class="card">
                <h3>System Status</h3>
                <div class="metric">
                    <span>CPU Usage:</span>
                    <span id="cpuUsage">Loading...</span>
                </div>
                <div class="metric">
                    <span>Memory Usage:</span>
                    <span id="memoryUsage">Loading...</span>
                </div>
                <div class="metric">
                    <span>Disk Usage:</span>
                    <span id="diskUsage">Loading...</span>
                </div>
                <div class="metric">
                    <span>Load Average:</span>
                    <span id="loadAverage">Loading...</span>
                </div>
            </div>
            
            <div class="card">
                <h3>WeatherAlert</h3>
                <div class="metric">
                    <span>Status:</span>
                    <span id="weatherappStatus">Loading...</span>
                </div>
                <div class="metric">
                    <span>Health Check:</span>
                    <span id="weatherappHealth">Loading...</span>
                </div>
                <div class="metric">
                    <span>Database:</span>
                    <span id="weatherappDB">Loading...</span>
                </div>
            </div>
            
            <div class="card">
                <h3>IRMSS</h3>
                <div class="metric">
                    <span>Status:</span>
                    <span id="irmssStatus">Loading...</span>
                </div>
                <div class="metric">
                    <span>Health Check:</span>
                    <span id="irmssHealth">Loading...</span>
                </div>
                <div class="metric">
                    <span>Database:</span>
                    <span id="irmssDB">Loading...</span>
                </div>
            </div>
            
            <div class="card">
                <h3>FireGuard</h3>
                <div class="metric">
                    <span>Status:</span>
                    <span id="fireguardStatus">Loading...</span>
                </div>
                <div class="metric">
                    <span>Health Check:</span>
                    <span id="fireguardHealth">Loading...</span>
                </div>
                <div class="metric">
                    <span>Database:</span>
                    <span id="fireguardDB">Loading...</span>
                </div>
            </div>
        </div>
    </div>
    
    <script>
        function updateStatus() {
            document.getElementById('lastUpdate').textContent = new Date().toLocaleString();
            
            // This would typically fetch data from your monitoring API
            // For now, we'll simulate the data
            setTimeout(() => {
                document.getElementById('cpuUsage').textContent = '45%';
                document.getElementById('memoryUsage').textContent = '62%';
                document.getElementById('diskUsage').textContent = '38%';
                document.getElementById('loadAverage').textContent = '1.2';
                
                document.getElementById('weatherappStatus').innerHTML = '<span class="status ok">Running</span>';
                document.getElementById('weatherappHealth').innerHTML = '<span class="status ok">Healthy</span>';
                document.getElementById('weatherappDB').innerHTML = '<span class="status ok">Connected</span>';
                
                document.getElementById('irmssStatus').innerHTML = '<span class="status ok">Running</span>';
                document.getElementById('irmssHealth').innerHTML = '<span class="status ok">Healthy</span>';
                document.getElementById('irmssDB').innerHTML = '<span class="status ok">Connected</span>';
                
                document.getElementById('fireguardStatus').innerHTML = '<span class="status ok">Running</span>';
                document.getElementById('fireguardHealth').innerHTML = '<span class="status ok">Healthy</span>';
                document.getElementById('fireguardDB').innerHTML = '<span class="status ok">Connected</span>';
            }, 1000);
        }
        
        // Update status on page load
        updateStatus();
        
        // Auto-refresh every 30 seconds
        setInterval(updateStatus, 30000);
    </script>
</body>
</html>
EOF

    print_success "Monitoring dashboard created"
}

# Function to create cron jobs
create_cron_jobs() {
    print_status "Creating cron jobs for monitoring and backups..."
    
    # System monitoring every 5 minutes
    cat > /etc/cron.d/system-monitor << EOF
# System monitoring
*/5 * * * * root /usr/local/bin/system-monitor.sh
EOF

    # Application monitoring every 5 minutes
    cat > /etc/cron.d/app-monitor << EOF
# Application monitoring
*/5 * * * * root /usr/local/bin/app-monitor.sh
EOF

    # Daily backups at 2 AM
    cat > /etc/cron.d/daily-backup << EOF
# Daily backup
0 2 * * * root /usr/local/bin/backup-all.sh
EOF

    # Weekly log cleanup
    cat > /etc/cron.d/log-cleanup << EOF
# Weekly log cleanup
0 3 * * 0 root find /var/log/django-apps -name "*.log.*" -mtime +30 -delete
EOF

    print_success "Cron jobs created"
}

# Function to create alert notification script
create_alert_script() {
    print_status "Creating alert notification script..."
    
    cat > /usr/local/bin/send-alert.sh << 'EOF'
#!/bin/bash

# Alert Notification Script for Django Applications
ALERT_FILE="/opt/monitoring/alerts/app-alerts.log"
EMAIL_RECIPIENT="admin@example.com"  # Change this to your email
SMS_RECIPIENT="+1234567890"  # Change this to your phone number

send_email() {
    local subject=$1
    local message=$2
    
    echo "$message" | mail -s "$subject" $EMAIL_RECIPIENT
}

send_sms() {
    local message=$1
    
    # This would integrate with your SMS service
    # curl -X POST "https://api.sms-service.com/send" \
    #     -H "Authorization: Bearer YOUR_API_KEY" \
    #     -d "to=$SMS_RECIPIENT" \
    #     -d "message=$message"
    
    echo "SMS would be sent: $message"
}

process_alerts() {
    if [ ! -f "$ALERT_FILE" ]; then
        return
    fi
    
    # Get recent alerts (last 5 minutes)
    local recent_alerts=$(find $ALERT_FILE -mmin -5 -exec cat {} \; 2>/dev/null)
    
    if [ -n "$recent_alerts" ]; then
        local alert_count=$(echo "$recent_alerts" | wc -l)
        
        if [ $alert_count -gt 0 ]; then
            local subject="Django Applications Alert - $alert_count issues detected"
            local message="Recent alerts detected:\n\n$recent_alerts"
            
            send_email "$subject" "$message"
            send_sms "Django Apps Alert: $alert_count issues detected"
        fi
    fi
}

# Main function
process_alerts
EOF

    chmod +x /usr/local/bin/send-alert.sh
    
    # Create cron job for alert processing
    cat > /etc/cron.d/alert-processor << EOF
# Alert processing
*/10 * * * * root /usr/local/bin/send-alert.sh
EOF

    print_success "Alert notification script created"
}

# Main function
main() {
    print_status "Starting comprehensive monitoring and backup setup..."
    
    check_root
    install_monitoring_deps
    create_monitoring_structure
    create_system_monitor
    create_app_monitor
    create_backup_script
    create_restore_script
    create_log_rotation
    create_monitoring_dashboard
    create_cron_jobs
    create_alert_script
    
    print_success "Monitoring and backup setup completed successfully!"
    print_status ""
    print_status "Monitoring features:"
    print_status "  - System resource monitoring (CPU, Memory, Disk, Load)"
    print_status "  - Application health monitoring"
    print_status "  - Database connection monitoring"
    print_status "  - Log analysis and alerting"
    print_status "  - Automated backups"
    print_status "  - Web dashboard: http://$SERVER_IP/monitoring.html"
    print_status ""
    print_status "Use the following commands to manage monitoring:"
    print_status "  /usr/local/bin/system-monitor.sh"
    print_status "  /usr/local/bin/app-monitor.sh"
    print_status "  /usr/local/bin/backup-all.sh"
    print_status "  /usr/local/bin/restore-app.sh <app> <backup_file>"
    print_status ""
    print_status "Logs are available at:"
    print_status "  /var/log/django-apps/"
    print_status "  /opt/monitoring/alerts/"
}

# Run main function
main "$@"
