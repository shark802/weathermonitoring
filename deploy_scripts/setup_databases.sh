#!/bin/bash

# =============================================================================
# Database Setup Script for Multiple Django Applications
# Creates isolated databases for each application
# =============================================================================

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MYSQL_ROOT_PASSWORD=""
DB_CONFIG_DIR="/etc/django-apps"
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

# Function to install MySQL
install_mysql() {
    print_status "Installing MySQL server..."
    
    # Update package list
    apt update
    
    # Install MySQL server
    DEBIAN_FRONTEND=noninteractive apt install -y mysql-server
    
    # Start and enable MySQL
    systemctl start mysql
    systemctl enable mysql
    
    print_success "MySQL server installed and started"
}

# Function to secure MySQL installation
secure_mysql() {
    print_status "Securing MySQL installation..."
    
    # Generate random root password if not provided
    if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
        MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32)
        print_warning "Generated MySQL root password: $MYSQL_ROOT_PASSWORD"
        print_warning "Please save this password securely!"
    fi
    
    # Create MySQL configuration file
    cat > /etc/mysql/mysql.conf.d/99-django-apps.cnf << EOF
[mysqld]
# Django Apps MySQL Configuration

# Basic settings
default-storage-engine=INNODB
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci

# Performance settings
innodb_buffer_pool_size=256M
innodb_log_file_size=64M
innodb_flush_log_at_trx_commit=2
innodb_flush_method=O_DIRECT

# Connection settings
max_connections=200
max_connect_errors=1000
connect_timeout=60
wait_timeout=28800
interactive_timeout=28800

# Query cache
query_cache_type=1
query_cache_size=32M
query_cache_limit=2M

# Logging
log-error=/var/log/mysql/error.log
slow_query_log=1
slow_query_log_file=/var/log/mysql/slow.log
long_query_time=2

# Security
local-infile=0
skip-show-database

# Binary logging
log-bin=mysql-bin
binlog_format=ROW
expire_logs_days=7
EOF

    # Restart MySQL to apply configuration
    systemctl restart mysql
    
    # Run MySQL secure installation
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASSWORD';"
    mysql -e "DELETE FROM mysql.user WHERE User='';"
    mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
    mysql -e "DROP DATABASE IF EXISTS test;"
    mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
    mysql -e "FLUSH PRIVILEGES;"
    
    print_success "MySQL secured with root password"
}

# Function to create application databases
create_app_databases() {
    print_status "Creating application databases..."
    
    # Create configuration directory
    mkdir -p $DB_CONFIG_DIR
    
    for app in "${APPS[@]}"; do
        print_status "Creating database for $app..."
        
        # Generate database credentials
        db_name="${app}_db"
        db_user="${app}_user"
        db_password=$(openssl rand -base64 32)
        
        # Create database and user
        mysql -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE IF NOT EXISTS \`${db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
        mysql -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE USER IF NOT EXISTS '${db_user}'@'localhost' IDENTIFIED BY '${db_password}';"
        mysql -u root -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'localhost';"
        mysql -u root -p$MYSQL_ROOT_PASSWORD -e "FLUSH PRIVILEGES;"
        
        # Save database credentials
        cat > $DB_CONFIG_DIR/${app}_db.conf << EOF
# Database configuration for $app
DB_NAME=$db_name
DB_USER=$db_user
DB_PASSWORD=$db_password
DB_HOST=localhost
DB_PORT=3306
DB_ENGINE=django.db.backends.mysql
DB_OPTIONS={'charset': 'utf8mb4'}
EOF
        
        # Set secure permissions
        chmod 600 $DB_CONFIG_DIR/${app}_db.conf
        chown root:root $DB_CONFIG_DIR/${app}_db.conf
        
        print_success "Database created for $app"
        print_status "  Database: $db_name"
        print_status "  User: $db_user"
        print_status "  Password: $db_password"
    done
    
    print_success "All application databases created"
}

# Function to create database backup script
create_backup_script() {
    print_status "Creating database backup script..."
    
    cat > /usr/local/bin/backup-databases.sh << 'EOF'
#!/bin/bash

# Database Backup Script for Django Applications
BACKUP_DIR="/opt/backups/databases"
DATE=$(date +%Y%m%d_%H%M%S)
APPS=("weatherapp" "irmss" "fireguard")
RETENTION_DAYS=7

# Create backup directory
mkdir -p $BACKUP_DIR

# Function to backup database
backup_database() {
    local app=$1
    local config_file="/etc/django-apps/${app}_db.conf"
    
    if [ ! -f "$config_file" ]; then
        echo "Configuration file not found for $app"
        return 1
    fi
    
    # Load database configuration
    source $config_file
    
    # Create backup filename
    local backup_file="$BACKUP_DIR/${app}_${DATE}.sql"
    
    # Create database backup
    mysqldump -u$DB_USER -p$DB_PASSWORD \
        --single-transaction \
        --routines \
        --triggers \
        --events \
        --hex-blob \
        --opt \
        $DB_NAME > $backup_file
    
    # Compress backup
    gzip $backup_file
    
    echo "Backup created: ${backup_file}.gz"
}

# Create backups for all apps
for app in "${APPS[@]}"; do
    echo "Backing up $app database..."
    backup_database $app
done

# Clean up old backups
find $BACKUP_DIR -name "*.sql.gz" -mtime +$RETENTION_DAYS -delete

echo "Database backup completed"
EOF

    chmod +x /usr/local/bin/backup-databases.sh
    
    # Create cron job for daily backups
    cat > /etc/cron.d/backup-databases << EOF
# Database backup cron job
0 2 * * * root /usr/local/bin/backup-databases.sh
EOF

    print_success "Database backup script created"
}

# Function to create database restore script
create_restore_script() {
    print_status "Creating database restore script..."
    
    cat > /usr/local/bin/restore-database.sh << 'EOF'
#!/bin/bash

# Database Restore Script for Django Applications
BACKUP_DIR="/opt/backups/databases"

# Function to show usage
show_usage() {
    echo "Database Restore Script"
    echo "Usage: $0 <app_name> <backup_file>"
    echo ""
    echo "Available apps: weatherapp, irmss, fireguard"
    echo "Backup files are located in: $BACKUP_DIR"
    echo ""
    echo "Example: $0 weatherapp weatherapp_20240101_120000.sql.gz"
}

# Check arguments
if [ $# -ne 2 ]; then
    show_usage
    exit 1
fi

APP_NAME=$1
BACKUP_FILE=$2

# Check if backup file exists
if [ ! -f "$BACKUP_DIR/$BACKUP_FILE" ]; then
    echo "Backup file not found: $BACKUP_DIR/$BACKUP_FILE"
    exit 1
fi

# Load database configuration
CONFIG_FILE="/etc/django-apps/${APP_NAME}_db.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

source $CONFIG_FILE

# Confirm restore
echo "This will restore the database for $APP_NAME"
echo "Backup file: $BACKUP_FILE"
echo "Database: $DB_NAME"
echo "User: $DB_USER"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Restore cancelled"
    exit 0
fi

# Stop the application
echo "Stopping Django application..."
systemctl stop django-$APP_NAME 2>/dev/null || true

# Create database backup before restore
echo "Creating current database backup..."
mysqldump -u$DB_USER -p$DB_PASSWORD $DB_NAME > $BACKUP_DIR/${APP_NAME}_pre_restore_$(date +%Y%m%d_%H%M%S).sql

# Restore database
echo "Restoring database from backup..."
if [[ $BACKUP_FILE == *.gz ]]; then
    gunzip -c $BACKUP_DIR/$BACKUP_FILE | mysql -u$DB_USER -p$DB_PASSWORD $DB_NAME
else
    mysql -u$DB_USER -p$DB_PASSWORD $DB_NAME < $BACKUP_DIR/$BACKUP_FILE
fi

# Start the application
echo "Starting Django application..."
systemctl start django-$APP_NAME

echo "Database restore completed for $APP_NAME"
EOF

    chmod +x /usr/local/bin/restore-database.sh
    
    print_success "Database restore script created"
}

# Function to create database monitoring script
create_monitoring_script() {
    print_status "Creating database monitoring script..."
    
    cat > /usr/local/bin/monitor-databases.sh << 'EOF'
#!/bin/bash

# Database Monitoring Script for Django Applications
LOG_FILE="/var/log/django-apps/database-monitor.log"
APPS=("weatherapp" "irmss" "fireguard")

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> $LOG_FILE
}

check_database() {
    local app=$1
    local config_file="/etc/django-apps/${app}_db.conf"
    
    if [ ! -f "$config_file" ]; then
        log_message "❌ Configuration file not found for $app"
        return 1
    fi
    
    # Load database configuration
    source $config_file
    
    # Test database connection
    if mysql -u$DB_USER -p$DB_PASSWORD -e "SELECT 1;" $DB_NAME >/dev/null 2>&1; then
        log_message "✅ Database connection successful for $app"
        
        # Check database size
        local db_size=$(mysql -u$DB_USER -p$DB_PASSWORD -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'DB Size in MB' FROM information_schema.tables WHERE table_schema='$DB_NAME';" -s -N)
        log_message "📊 Database size for $app: ${db_size}MB"
        
        # Check table count
        local table_count=$(mysql -u$DB_USER -p$DB_PASSWORD -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB_NAME';" -s -N)
        log_message "📋 Table count for $app: $table_count"
        
        return 0
    else
        log_message "❌ Database connection failed for $app"
        return 1
    fi
}

# Check all databases
for app in "${APPS[@]}"; do
    check_database $app
done

# Check MySQL service
if systemctl is-active --quiet mysql; then
    log_message "✅ MySQL service is running"
else
    log_message "❌ MySQL service is not running"
    systemctl restart mysql
    sleep 5
    if systemctl is-active --quiet mysql; then
        log_message "✅ MySQL service restarted successfully"
    else
        log_message "🚨 MySQL service failed to restart"
    fi
fi

# Check disk space
DISK_USAGE=$(df /var/lib/mysql | awk 'NR==2 {print $5}' | sed 's/%//')
if [ $DISK_USAGE -gt 80 ]; then
    log_message "⚠️ High disk usage for MySQL data directory: ${DISK_USAGE}%"
fi
EOF

    chmod +x /usr/local/bin/monitor-databases.sh
    
    # Create cron job for database monitoring
    cat > /etc/cron.d/monitor-databases << EOF
# Database monitoring cron job
*/10 * * * * root /usr/local/bin/monitor-databases.sh
EOF

    print_success "Database monitoring script created"
}

# Function to create database management script
create_management_script() {
    print_status "Creating database management script..."
    
    cat > /usr/local/bin/db-manager.sh << 'EOF'
#!/bin/bash

# Database Management Script for Django Applications
APPS=("weatherapp" "irmss" "fireguard")

show_help() {
    echo "Database Manager for Django Applications"
    echo "Usage: $0 <command> [app_name]"
    echo ""
    echo "Commands:"
    echo "  status [app]     - Show database status for app(s)"
    echo "  backup [app]     - Create backup for app(s)"
    echo "  restore <app>    - Restore database for app"
    echo "  optimize [app]    - Optimize database for app(s)"
    echo "  repair [app]     - Repair database for app(s)"
    echo "  info [app]       - Show database information for app(s)"
    echo ""
    echo "Available apps: ${APPS[*]}"
}

get_db_config() {
    local app=$1
    local config_file="/etc/django-apps/${app}_db.conf"
    
    if [ ! -f "$config_file" ]; then
        echo "Configuration file not found for $app"
        return 1
    fi
    
    source $config_file
}

show_status() {
    local app=$1
    
    if [ -z "$app" ]; then
        # Show status for all apps
        for app in "${APPS[@]}"; do
            show_status $app
        done
        return
    fi
    
    get_db_config $app || return 1
    
    echo "=== Database Status for $app ==="
    echo "Database: $DB_NAME"
    echo "User: $DB_USER"
    echo "Host: $DB_HOST"
    echo "Port: $DB_PORT"
    
    # Test connection
    if mysql -u$DB_USER -p$DB_PASSWORD -e "SELECT 1;" $DB_NAME >/dev/null 2>&1; then
        echo "Status: ✅ Connected"
        
        # Get database size
        local db_size=$(mysql -u$DB_USER -p$DB_PASSWORD -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'DB Size in MB' FROM information_schema.tables WHERE table_schema='$DB_NAME';" -s -N)
        echo "Size: ${db_size}MB"
        
        # Get table count
        local table_count=$(mysql -u$DB_USER -p$DB_PASSWORD -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB_NAME';" -s -N)
        echo "Tables: $table_count"
    else
        echo "Status: ❌ Connection failed"
    fi
    echo ""
}

create_backup() {
    local app=$1
    
    if [ -z "$app" ]; then
        # Create backup for all apps
        for app in "${APPS[@]}"; do
            create_backup $app
        done
        return
    fi
    
    get_db_config $app || return 1
    
    local backup_file="/opt/backups/databases/${app}_$(date +%Y%m%d_%H%M%S).sql"
    mkdir -p /opt/backups/databases
    
    echo "Creating backup for $app..."
    mysqldump -u$DB_USER -p$DB_PASSWORD \
        --single-transaction \
        --routines \
        --triggers \
        --events \
        --hex-blob \
        --opt \
        $DB_NAME > $backup_file
    
    gzip $backup_file
    echo "Backup created: ${backup_file}.gz"
}

optimize_database() {
    local app=$1
    
    if [ -z "$app" ]; then
        # Optimize all databases
        for app in "${APPS[@]}"; do
            optimize_database $app
        done
        return
    fi
    
    get_db_config $app || return 1
    
    echo "Optimizing database for $app..."
    mysql -u$DB_USER -p$DB_PASSWORD -e "OPTIMIZE TABLE \`$DB_NAME\`.*;" $DB_NAME
    echo "Database optimized for $app"
}

repair_database() {
    local app=$1
    
    if [ -z "$app" ]; then
        echo "Please specify an app name for repair"
        return 1
    fi
    
    get_db_config $app || return 1
    
    echo "Repairing database for $app..."
    mysql -u$DB_USER -p$DB_PASSWORD -e "REPAIR TABLE \`$DB_NAME\`.*;" $DB_NAME
    echo "Database repaired for $app"
}

show_info() {
    local app=$1
    
    if [ -z "$app" ]; then
        # Show info for all apps
        for app in "${APPS[@]}"; do
            show_info $app
        done
        return
    fi
    
    get_db_config $app || return 1
    
    echo "=== Database Information for $app ==="
    mysql -u$DB_USER -p$DB_PASSWORD -e "
        SELECT 
            table_name as 'Table',
            ROUND(((data_length + index_length) / 1024 / 1024), 2) as 'Size (MB)',
            table_rows as 'Rows'
        FROM information_schema.tables 
        WHERE table_schema = '$DB_NAME'
        ORDER BY (data_length + index_length) DESC;
    " $DB_NAME
    echo ""
}

# Main script logic
if [ $# -lt 1 ]; then
    show_help
    exit 1
fi

command=$1
app=$2

case $command in
    "status")
        show_status $app
        ;;
    "backup")
        create_backup $app
        ;;
    "restore")
        if [ -z "$app" ]; then
            echo "Please specify an app name for restore"
            exit 1
        fi
        /usr/local/bin/restore-database.sh $app $3
        ;;
    "optimize")
        optimize_database $app
        ;;
    "repair")
        repair_database $app
        ;;
    "info")
        show_info $app
        ;;
    *)
        echo "Unknown command: $command"
        show_help
        ;;
esac
EOF

    chmod +x /usr/local/bin/db-manager.sh
    
    print_success "Database management script created"
}

# Main function
main() {
    print_status "Starting database setup for Django applications..."
    
    check_root
    install_mysql
    secure_mysql
    create_app_databases
    create_backup_script
    create_restore_script
    create_monitoring_script
    create_management_script
    
    print_success "Database setup completed successfully!"
    print_status ""
    print_status "Database credentials are stored in:"
    for app in "${APPS[@]}"; do
        print_status "  /etc/django-apps/${app}_db.conf"
    done
    print_status ""
    print_status "Use the following commands to manage databases:"
    print_status "  /usr/local/bin/db-manager.sh status"
    print_status "  /usr/local/bin/db-manager.sh backup"
    print_status "  /usr/local/bin/db-manager.sh optimize"
    print_status ""
    print_status "MySQL root password: $MYSQL_ROOT_PASSWORD"
    print_warning "Please save the MySQL root password securely!"
}

# Run main function
main "$@"
