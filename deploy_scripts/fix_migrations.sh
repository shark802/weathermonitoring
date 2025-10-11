#!/bin/bash

# =============================================================================
# Fix Migrations Script for WeatherAlert
# This script fixes the Django settings issue and runs migrations
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

# Function to run database migrations with correct settings
run_migrations() {
    print_status "Running database migrations with correct settings..."
    
    cd $APP_DIR
    source venv/bin/activate
    
    # Use the existing settings file
    export DJANGO_SETTINGS_MODULE=weatheralert.settings
    
    print_status "Using Django settings: weatheralert.settings"
    
    # Run migrations
    print_status "Running makemigrations..."
    python manage.py makemigrations
    
    print_status "Running migrate..."
    python manage.py migrate
    
    # Create superuser if it doesn't exist
    print_status "Creating superuser..."
    echo "from django.contrib.auth import get_user_model; User = get_user_model(); User.objects.filter(username='admin').exists() or User.objects.create_superuser('admin', 'admin@example.com', 'admin123')" | python manage.py shell
    
    # Collect static files
    print_status "Collecting static files..."
    python manage.py collectstatic --noinput
    
    deactivate
    print_success "Database migrations completed successfully"
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
    print_status "Fixing WeatherAlert migrations..."
    print_status "This will run migrations with the correct Django settings"
    
    check_root
    run_migrations
    start_services
    test_application
    
    print_success "WeatherAlert deployment fixed successfully!"
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
}

# Run main function
main "$@"
