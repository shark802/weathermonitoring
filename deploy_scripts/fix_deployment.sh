#!/bin/bash

# =============================================================================
# Fix Deployment Script for WeatherAlert
# Resolves the "same file" error and completes the deployment
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

# Function to copy application files correctly
copy_app_files_fixed() {
    print_status "Copying application files (fixed method)..."
    
    # Ensure target directory exists
    mkdir -p $APP_DIR
    
    # Copy from current directory (where the script is run from)
    print_status "Copying from current directory: $(pwd)"
    
    # Copy Django project files
    if [ -d "weatheralert" ]; then
        print_status "Copying weatheralert directory..."
        cp -r weatheralert $APP_DIR/
    else
        print_warning "weatheralert directory not found"
    fi
    
    if [ -d "weatherapp" ]; then
        print_status "Copying weatherapp directory..."
        cp -r weatherapp $APP_DIR/
    else
        print_warning "weatherapp directory not found"
    fi
    
    if [ -d "esp32" ]; then
        print_status "Copying esp32 directory..."
        cp -r esp32 $APP_DIR/
    else
        print_warning "esp32 directory not found"
    fi
    
    if [ -f "manage.py" ]; then
        print_status "Copying manage.py..."
        cp manage.py $APP_DIR/
    else
        print_warning "manage.py not found"
    fi
    
    if [ -f "requirements.txt" ]; then
        print_status "Copying requirements.txt..."
        cp requirements.txt $APP_DIR/
    else
        print_warning "requirements.txt not found"
    fi
    
    if [ -f "Procfile" ]; then
        print_status "Copying Procfile..."
        cp Procfile $APP_DIR/
    fi
    
    if [ -f "Procfile.dev" ]; then
        print_status "Copying Procfile.dev..."
        cp Procfile.dev $APP_DIR/
    fi
    
    # Copy static files if they exist
    if [ -d "staticfiles" ]; then
        print_status "Copying staticfiles..."
        mkdir -p $APP_DIR/staticfiles
        cp -r staticfiles/* $APP_DIR/staticfiles/ 2>/dev/null || true
    fi
    
    # Copy media files if they exist
    if [ -d "media" ]; then
        print_status "Copying media files..."
        mkdir -p $APP_DIR/media
        cp -r media/* $APP_DIR/media/ 2>/dev/null || true
    fi
    
    # Set proper permissions
    chown -R django-$APP_NAME:django-$APP_NAME $APP_DIR 2>/dev/null || true
    
    print_success "Application files copied successfully"
}

# Function to create virtual environment
setup_virtualenv() {
    print_status "Setting up Python virtual environment..."
    
    cd $APP_DIR
    
    # Create virtual environment
    python3 -m venv venv
    source venv/bin/activate
    
    # Install Python dependencies
    if [ -f "requirements.txt" ]; then
        pip install --upgrade pip
        pip install -r requirements.txt
    else
        print_warning "requirements.txt not found, installing basic dependencies..."
        pip install django gunicorn celery redis mysqlclient
        pip install psycopg2-binary dj-database-url
        pip install whitenoise django-heroku
    fi
    
    deactivate
    
    print_success "Virtual environment setup completed"
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
    local health_url="http://$SERVER_IP/$APP_URL/health/"
    local http_status=$(curl -s -o /dev/null -w "%{http_code}" $health_url 2>/dev/null || echo "000")
    
    if [ "$http_status" = "200" ]; then
        print_success "Application health check passed"
    else
        print_warning "Application health check failed (HTTP $http_status)"
        print_status "Trying main application URL..."
        
        local main_url="http://$SERVER_IP/$APP_URL/"
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
    print_status "Starting deployment fix for WeatherAlert..."
    print_status "This will resolve the 'same file' error and complete the deployment"
    
    check_root
    copy_app_files_fixed
    setup_virtualenv
    run_migrations
    start_services
    test_application
    
    print_success "WeatherAlert deployment fix completed successfully!"
    print_status ""
    print_status "Application should now be available at:"
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
    print_status "  /var/log/django-apps/$APP_NAME/"
}

# Run main function
main "$@"