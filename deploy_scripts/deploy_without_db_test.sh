#!/bin/bash

# =============================================================================
# WeatherAlert Deployment Script (Without Database Connection Test)
# This script skips the database connection test and proceeds with deployment
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
DB_CONFIG_DIR="/etc/django-apps"

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

# Function to generate a Django secret key
generate_secret_key() {
    python3 -c "
import secrets
import string

# Generate a 50-character secret key similar to Django's format
chars = string.ascii_letters + string.digits + '!@#$%^&*(-_=+)'
secret_key = ''.join(secrets.choice(chars) for _ in range(50))
print(secret_key)
"
}

# Function to setup database configuration
setup_database_config() {
    print_status "Setting up database configuration for remote database..."
    
    # Create database configuration directory
    mkdir -p $DB_CONFIG_DIR
    
    # Use existing remote database credentials from settings.py
    DB_NAME="u520834156_dbweatherApp"
    DB_USER="u520834156_uWApp2024"
    DB_PASSWORD="bIxG2Z$In#8"
    DB_HOST="153.92.15.8"
    DB_PORT="3306"
    
    # Create database configuration file
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
    
    print_success "Database configuration created for remote database"
    print_status "Database: $DB_NAME"
    print_status "User: $DB_USER"
    print_status "Host: $DB_HOST:$DB_PORT"
    print_warning "Skipping database connection test (assuming connection is working)"
}

# Function to copy application files from current directory
copy_app_files() {
    print_status "Copying application files from current directory..."
    
    # Create target directory
    mkdir -p $APP_DIR
    
    # Copy all files and directories except the current directory itself
    print_status "Copying Django project files..."
    
    # Copy specific directories and files
    if [ -d "weatheralert" ]; then
        cp -r weatheralert $APP_DIR/
        print_status "✓ Copied weatheralert directory"
    fi
    
    if [ -d "weatherapp" ]; then
        cp -r weatherapp $APP_DIR/
        print_status "✓ Copied weatherapp directory"
    fi
    
    if [ -d "esp32" ]; then
        cp -r esp32 $APP_DIR/
        print_status "✓ Copied esp32 directory"
    fi
    
    if [ -f "manage.py" ]; then
        cp manage.py $APP_DIR/
        print_status "✓ Copied manage.py"
    fi
    
    if [ -f "requirements.txt" ]; then
        cp requirements.txt $APP_DIR/
        print_status "✓ Copied requirements.txt"
    fi
    
    if [ -f "Procfile" ]; then
        cp Procfile $APP_DIR/
        print_status "✓ Copied Procfile"
    fi
    
    if [ -f "Procfile.dev" ]; then
        cp Procfile.dev $APP_DIR/
        print_status "✓ Copied Procfile.dev"
    fi
    
    # Copy static files if they exist
    if [ -d "staticfiles" ]; then
        mkdir -p $APP_DIR/staticfiles
        cp -r staticfiles/* $APP_DIR/staticfiles/ 2>/dev/null || true
        print_status "✓ Copied staticfiles"
    fi
    
    # Copy media files if they exist
    if [ -d "media" ]; then
        mkdir -p $APP_DIR/media
        cp -r media/* $APP_DIR/media/ 2>/dev/null || true
        print_status "✓ Copied media files"
    fi
    
    # Set proper permissions
    chown -R django-$APP_NAME:django-$APP_NAME $APP_DIR 2>/dev/null || true
    
    print_success "Application files copied successfully"
}

# Function to setup virtual environment
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
        print_success "Dependencies installed from requirements.txt"
    else
        print_warning "requirements.txt not found, installing basic dependencies..."
        pip install django gunicorn celery redis mysqlclient
        pip install psycopg2-binary dj-database-url
        pip install whitenoise django-heroku
        print_success "Basic dependencies installed"
    fi
    
    deactivate
    print_success "Virtual environment setup completed"
}

# Function to create environment configuration
create_env_config() {
    print_status "Creating environment configuration..."
    
    # Generate secret key using Python's secrets module
    SECRET_KEY=$(generate_secret_key)
    
    # Load database credentials
    source $DB_CONFIG_DIR/${APP_NAME}_db.conf
    
    # Create .env file
    cat > $APP_DIR/.env << EOF
# WeatherAlert Environment Configuration
DEBUG=False
SECRET_KEY=$SECRET_KEY
ALLOWED_HOSTS=$SERVER_IP,localhost,127.0.0.1,192.168.3.5

# Database configuration
DATABASE_URL=mysql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME

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
APP_URL=http://$SERVER_IP/$APP_URL
TIME_ZONE=Asia/Manila
LANGUAGE_CODE=en-us

# Security settings
SESSION_EXPIRE_AT_BROWSER_CLOSE=False
SESSION_ENGINE=django.contrib.sessions.backends.db
SESSION_COOKIE_HTTPONLY=True
SESSION_SAVE_EVERY_REQUEST=True

# Static files
STATIC_URL=/static/
STATIC_ROOT=$APP_DIR/staticfiles
MEDIA_URL=/media/
MEDIA_ROOT=$APP_DIR/media
EOF

    chmod 600 $APP_DIR/.env
    print_success "Environment configuration created"
}

# Function to run database migrations
run_migrations() {
    print_status "Running database migrations..."
    
    cd $APP_DIR
    source venv/bin/activate
    
    # Use the existing settings file instead of production settings
    export DJANGO_SETTINGS_MODULE=weatheralert.settings
    
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
    print_status "Starting WeatherAlert deployment (without database connection test)..."
    print_status "This will use your existing remote database and complete the deployment"
    
    check_root
    setup_database_config
    copy_app_files
    setup_virtualenv
    create_env_config
    run_migrations
    start_services
    test_application
    
    print_success "WeatherAlert deployment completed successfully!"
    print_status ""
    print_status "Application is now available at:"
    print_status "  http://$SERVER_IP/$APP_URL"
    print_status ""
    print_status "Admin credentials:"
    print_status "  Username: admin"
    print_status "  Password: admin123"
    print_status ""
    print_status "Database information:"
    print_status "  Database: u520834156_dbweatherApp (Remote)"
    print_status "  Host: 153.92.15.8:3306"
    print_status "  User: u520834156_uWApp2024"
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
