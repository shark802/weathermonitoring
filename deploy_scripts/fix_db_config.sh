#!/bin/bash

# =============================================================================
# Quick Fix for Database Configuration
# Fixes the database configuration file syntax error
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
DB_CONFIG_DIR="/etc/django-apps"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
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

# Function to fix database configuration
fix_database_config() {
    print_status "Fixing database configuration file..."
    
    # Create database configuration directory
    mkdir -p $DB_CONFIG_DIR
    
    # Use existing remote database credentials
    DB_NAME="u520834156_dbweatherApp"
    DB_USER="u520834156_uWApp2024"
    DB_PASSWORD="bIxG2Z$In#8"
    DB_HOST="153.92.15.8"
    DB_PORT="3306"
    
    # Create corrected database configuration file
    cat > $DB_CONFIG_DIR/${APP_NAME}_db.conf << 'EOF'
# Database configuration for weatherapp (Remote Database)
DB_NAME=u520834156_dbweatherApp
DB_USER=u520834156_uWApp2024
DB_PASSWORD=bIxG2Z$In#8
DB_HOST=153.92.15.8
DB_PORT=3306
DB_ENGINE=django.db.backends.mysql
DB_OPTIONS="{'charset': 'utf8mb4'}"
EOF
    
    # Set secure permissions
    chmod 600 $DB_CONFIG_DIR/${APP_NAME}_db.conf
    chown root:root $DB_CONFIG_DIR/${APP_NAME}_db.conf
    
    print_success "Database configuration file fixed"
    print_status "Database: $DB_NAME"
    print_status "User: $DB_USER"
    print_status "Host: $DB_HOST:$DB_PORT"
}

# Function to test database connection
test_database_connection() {
    print_status "Testing remote database connection..."
    
    # Load database configuration
    source $DB_CONFIG_DIR/${APP_NAME}_db.conf
    
    # Test database connection
    if mysql -h$DB_HOST -P$DB_PORT -u$DB_USER -p$DB_PASSWORD -e "SELECT 1;" $DB_NAME >/dev/null 2>&1; then
        print_success "Remote database connection successful"
    else
        print_error "Remote database connection failed"
        print_status "Please check your database credentials and network connectivity"
        exit 1
    fi
}

# Main function
main() {
    print_status "Fixing database configuration..."
    
    check_root
    fix_database_config
    test_database_connection
    
    print_success "Database configuration fixed successfully!"
    print_status ""
    print_status "You can now run the complete deployment script:"
    print_status "  sudo ./deploy_scripts/complete_deploy.sh"
}

# Run main function
main "$@"
