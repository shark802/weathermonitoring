#!/bin/bash

# =============================================================================
# Environment Configuration Templates Creator for Django Applications
# Creates environment templates for weatherapp, irmss, fireguard applications
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
TEMPLATE_DIR="/opt/django-apps/env-templates"

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

# Function to create template directory
create_template_directory() {
    print_status "Creating template directory..."
    
    mkdir -p $TEMPLATE_DIR
    mkdir -p $TEMPLATE_DIR/production
    mkdir -p $TEMPLATE_DIR/development
    mkdir -p $TEMPLATE_DIR/staging
    
    print_success "Template directory created"
}

# Function to create WeatherAlert environment template
create_weatherapp_template() {
    print_status "Creating WeatherAlert environment template..."
    
    # Production template
    cat > $TEMPLATE_DIR/production/weatherapp.env << 'EOF'
# WeatherAlert Production Environment Configuration
# Copy this file to /opt/django-apps/weatherapp/.env and customize

# Django Settings
DEBUG=False
SECRET_KEY=your-secret-key-here
ALLOWED_HOSTS=192.168.3.5,localhost,127.0.0.1,yourdomain.com
DJANGO_SETTINGS_MODULE=weatheralert.settings_production

# Database Configuration
DATABASE_URL=mysql://weatherapp_user:your-db-password@localhost:3306/weatherapp_db
DB_NAME=weatherapp_db
DB_USER=weatherapp_user
DB_PASSWORD=your-db-password-here
DB_HOST=localhost
DB_PORT=3306
DB_ENGINE=django.db.backends.mysql

# Redis Configuration
REDIS_URL=redis://localhost:6379/0
CELERY_BROKER_URL=redis://localhost:6379/0
CELERY_RESULT_BACKEND=redis://localhost:6379/0
CELERY_ACCEPT_CONTENT=json
CELERY_TASK_SERIALIZER=json
CELERY_RESULT_SERIALIZER=json
CELERY_TIMEZONE=Asia/Manila

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

# PhilSys QR Verification Keys
PSA_PUBLIC_KEY=your-psa-public-key-here
PSA_ED25519_PUBLIC_KEY=your-psa-ed25519-public-key-here

# App Settings
APP_NAME=weatherapp
APP_URL=http://192.168.3.5/bccweatherapp
TIME_ZONE=Asia/Manila
LANGUAGE_CODE=en-us

# Security Settings
SESSION_EXPIRE_AT_BROWSER_CLOSE=False
SESSION_ENGINE=django.contrib.sessions.backends.db
SESSION_COOKIE_HTTPONLY=True
SESSION_SAVE_EVERY_REQUEST=True
SECURE_BROWSER_XSS_FILTER=True
SECURE_CONTENT_TYPE_NOSNIFF=True
SECURE_HSTS_INCLUDE_SUBDOMAINS=True
SECURE_HSTS_SECONDS=31536000
SECURE_SSL_REDIRECT=False
SESSION_COOKIE_SECURE=False
CSRF_COOKIE_SECURE=False

# Static Files
STATIC_URL=/static/
STATIC_ROOT=/opt/django-apps/weatherapp/staticfiles
MEDIA_URL=/media/
MEDIA_ROOT=/opt/django-apps/weatherapp/media

# Logging
LOG_LEVEL=INFO
LOG_FILE=/var/log/django-apps/weatherapp/django.log

# AI/ML Settings
AI_MODEL_PATH=/opt/django-apps/weatherapp/ai/rain_model.h5
AI_SCALER_X_PATH=/opt/django-apps/weatherapp/ai/scaler_X.pkl
AI_SCALER_Y_PATH=/opt/django-apps/weatherapp/ai/scaler_y.pkl

# Weather API
OPENWEATHER_API_KEY=c340398fbf11b1f8ccd73c40f006a0fe
WEATHER_LAT=10.5283
WEATHER_LON=122.8338

# IoT Settings
IOT_ENABLED=True
IOT_DATA_ENDPOINT=/api/data/
IOT_SENSOR_TIMEOUT=300

# Alert Settings
ALERT_EMAIL_ENABLED=True
ALERT_SMS_ENABLED=True
ALERT_THRESHOLD_RAIN=10.0
ALERT_THRESHOLD_WIND=15.0
EOF

    # Development template
    cat > $TEMPLATE_DIR/development/weatherapp.env << 'EOF'
# WeatherAlert Development Environment Configuration
# Copy this file to /opt/django-apps/weatherapp/.env and customize

# Django Settings
DEBUG=True
SECRET_KEY=dev-secret-key-change-in-production
ALLOWED_HOSTS=192.168.3.5,localhost,127.0.0.1,*
DJANGO_SETTINGS_MODULE=weatheralert.settings

# Database Configuration (SQLite for development)
DATABASE_URL=sqlite:///opt/django-apps/weatherapp/db.sqlite3
DB_NAME=weatherapp_dev
DB_USER=weatherapp_dev
DB_PASSWORD=dev_password
DB_HOST=localhost
DB_PORT=3306
DB_ENGINE=django.db.backends.sqlite3

# Redis Configuration
REDIS_URL=redis://localhost:6379/1
CELERY_BROKER_URL=redis://localhost:6379/1
CELERY_RESULT_BACKEND=redis://localhost:6379/1

# Email Configuration (Console backend for development)
EMAIL_BACKEND=django.core.mail.backends.console.EmailBackend
EMAIL_HOST=localhost
EMAIL_PORT=587
EMAIL_USE_TLS=False
EMAIL_HOST_USER=
EMAIL_HOST_PASSWORD=
DEFAULT_FROM_EMAIL=WeatherAlert Dev <dev@localhost>

# SMS Configuration (Disabled for development)
SMS_API_URL=
SMS_API_KEY=
SMS_DEVICE_ID=

# PhilSys QR Verification Keys (Disabled for development)
PSA_PUBLIC_KEY=
PSA_ED25519_PUBLIC_KEY=

# App Settings
APP_NAME=weatherapp
APP_URL=http://192.168.3.5/bccweatherapp
TIME_ZONE=Asia/Manila
LANGUAGE_CODE=en-us

# Security Settings (Relaxed for development)
SESSION_EXPIRE_AT_BROWSER_CLOSE=False
SESSION_ENGINE=django.contrib.sessions.backends.db
SESSION_COOKIE_HTTPONLY=False
SESSION_SAVE_EVERY_REQUEST=True
SECURE_BROWSER_XSS_FILTER=False
SECURE_CONTENT_TYPE_NOSNIFF=False
SECURE_SSL_REDIRECT=False
SESSION_COOKIE_SECURE=False
CSRF_COOKIE_SECURE=False

# Static Files
STATIC_URL=/static/
STATIC_ROOT=/opt/django-apps/weatherapp/staticfiles
MEDIA_URL=/media/
MEDIA_ROOT=/opt/django-apps/weatherapp/media

# Logging (Verbose for development)
LOG_LEVEL=DEBUG
LOG_FILE=/var/log/django-apps/weatherapp/django.log

# AI/ML Settings
AI_MODEL_PATH=/opt/django-apps/weatherapp/ai/rain_model.h5
AI_SCALER_X_PATH=/opt/django-apps/weatherapp/ai/scaler_X.pkl
AI_SCALER_Y_PATH=/opt/django-apps/weatherapp/ai/scaler_y.pkl

# Weather API
OPENWEATHER_API_KEY=c340398fbf11b1f8ccd73c40f006a0fe
WEATHER_LAT=10.5283
WEATHER_LON=122.8338

# IoT Settings
IOT_ENABLED=True
IOT_DATA_ENDPOINT=/api/data/
IOT_SENSOR_TIMEOUT=300

# Alert Settings (Disabled for development)
ALERT_EMAIL_ENABLED=False
ALERT_SMS_ENABLED=False
ALERT_THRESHOLD_RAIN=10.0
ALERT_THRESHOLD_WIND=15.0
EOF

    # Staging template
    cat > $TEMPLATE_DIR/staging/weatherapp.env << 'EOF'
# WeatherAlert Staging Environment Configuration
# Copy this file to /opt/django-apps/weatherapp/.env and customize

# Django Settings
DEBUG=False
SECRET_KEY=staging-secret-key-change-in-production
ALLOWED_HOSTS=192.168.3.5,localhost,127.0.0.1,staging.yourdomain.com
DJANGO_SETTINGS_MODULE=weatheralert.settings_production

# Database Configuration
DATABASE_URL=mysql://weatherapp_staging_user:staging-db-password@localhost:3306/weatherapp_staging_db
DB_NAME=weatherapp_staging_db
DB_USER=weatherapp_staging_user
DB_PASSWORD=staging-db-password-here
DB_HOST=localhost
DB_PORT=3306
DB_ENGINE=django.db.backends.mysql

# Redis Configuration
REDIS_URL=redis://localhost:6379/2
CELERY_BROKER_URL=redis://localhost:6379/2
CELERY_RESULT_BACKEND=redis://localhost:6379/2

# Email Configuration (Test backend for staging)
EMAIL_BACKEND=django.core.mail.backends.filebased.EmailBackend
EMAIL_FILE_PATH=/var/log/django-apps/weatherapp/emails.log
EMAIL_HOST=smtp.gmail.com
EMAIL_PORT=587
EMAIL_USE_TLS=True
EMAIL_HOST_USER=test@example.com
EMAIL_HOST_PASSWORD=test-password
DEFAULT_FROM_EMAIL=WeatherAlert Staging <test@example.com>

# SMS Configuration (Test mode for staging)
SMS_API_URL=https://sms.pagenet.info/api/v1/sms/send
SMS_API_KEY=test-api-key
SMS_DEVICE_ID=test-device-id

# PhilSys QR Verification Keys (Test keys for staging)
PSA_PUBLIC_KEY=test-psa-public-key
PSA_ED25519_PUBLIC_KEY=test-psa-ed25519-public-key

# App Settings
APP_NAME=weatherapp
APP_URL=http://192.168.3.5/bccweatherapp
TIME_ZONE=Asia/Manila
LANGUAGE_CODE=en-us

# Security Settings
SESSION_EXPIRE_AT_BROWSER_CLOSE=False
SESSION_ENGINE=django.contrib.sessions.backends.db
SESSION_COOKIE_HTTPONLY=True
SESSION_SAVE_EVERY_REQUEST=True
SECURE_BROWSER_XSS_FILTER=True
SECURE_CONTENT_TYPE_NOSNIFF=True
SECURE_SSL_REDIRECT=False
SESSION_COOKIE_SECURE=False
CSRF_COOKIE_SECURE=False

# Static Files
STATIC_URL=/static/
STATIC_ROOT=/opt/django-apps/weatherapp/staticfiles
MEDIA_URL=/media/
MEDIA_ROOT=/opt/django-apps/weatherapp/media

# Logging
LOG_LEVEL=INFO
LOG_FILE=/var/log/django-apps/weatherapp/django.log

# AI/ML Settings
AI_MODEL_PATH=/opt/django-apps/weatherapp/ai/rain_model.h5
AI_SCALER_X_PATH=/opt/django-apps/weatherapp/ai/scaler_X.pkl
AI_SCALER_Y_PATH=/opt/django-apps/weatherapp/ai/scaler_y.pkl

# Weather API
OPENWEATHER_API_KEY=c340398fbf11b1f8ccd73c40f006a0fe
WEATHER_LAT=10.5283
WEATHER_LON=122.8338

# IoT Settings
IOT_ENABLED=True
IOT_DATA_ENDPOINT=/api/data/
IOT_SENSOR_TIMEOUT=300

# Alert Settings (Test mode for staging)
ALERT_EMAIL_ENABLED=True
ALERT_SMS_ENABLED=False
ALERT_THRESHOLD_RAIN=10.0
ALERT_THRESHOLD_WIND=15.0
EOF

    print_success "WeatherAlert environment templates created"
}

# Function to create IRMSS environment template
create_irmss_template() {
    print_status "Creating IRMSS environment template..."
    
    # Production template
    cat > $TEMPLATE_DIR/production/irmss.env << 'EOF'
# IRMSS Production Environment Configuration
# Copy this file to /opt/django-apps/irmss/.env and customize

# Django Settings
DEBUG=False
SECRET_KEY=your-secret-key-here
ALLOWED_HOSTS=192.168.3.5,localhost,127.0.0.1,yourdomain.com
DJANGO_SETTINGS_MODULE=irmss.settings_production

# Database Configuration
DATABASE_URL=mysql://irmss_user:your-db-password@localhost:3306/irmss_db
DB_NAME=irmss_db
DB_USER=irmss_user
DB_PASSWORD=your-db-password-here
DB_HOST=localhost
DB_PORT=3306
DB_ENGINE=django.db.backends.mysql

# Redis Configuration
REDIS_URL=redis://localhost:6379/0
CELERY_BROKER_URL=redis://localhost:6379/0
CELERY_RESULT_BACKEND=redis://localhost:6379/0

# Email Configuration
EMAIL_BACKEND=django.core.mail.backends.smtp.EmailBackend
EMAIL_HOST=smtp.gmail.com
EMAIL_PORT=587
EMAIL_USE_TLS=True
EMAIL_HOST_USER=irmss@example.com
EMAIL_HOST_PASSWORD=your-email-password
DEFAULT_FROM_EMAIL=IRMSS <irmss@example.com>

# App Settings
APP_NAME=irmss
APP_URL=http://192.168.3.5/irrms
TIME_ZONE=Asia/Manila
LANGUAGE_CODE=en-us

# Security Settings
SESSION_EXPIRE_AT_BROWSER_CLOSE=False
SESSION_ENGINE=django.contrib.sessions.backends.db
SESSION_COOKIE_HTTPONLY=True
SESSION_SAVE_EVERY_REQUEST=True
SECURE_BROWSER_XSS_FILTER=True
SECURE_CONTENT_TYPE_NOSNIFF=True
SECURE_HSTS_INCLUDE_SUBDOMAINS=True
SECURE_HSTS_SECONDS=31536000
SECURE_SSL_REDIRECT=False
SESSION_COOKIE_SECURE=False
CSRF_COOKIE_SECURE=False

# Static Files
STATIC_URL=/static/
STATIC_ROOT=/opt/django-apps/irmss/staticfiles
MEDIA_URL=/media/
MEDIA_ROOT=/opt/django-apps/irmss/media

# Logging
LOG_LEVEL=INFO
LOG_FILE=/var/log/django-apps/irmss/django.log

# IRMSS Specific Settings
IRMSS_API_ENABLED=True
IRMSS_DATA_RETENTION_DAYS=365
IRMSS_REPORT_GENERATION=True
IRMSS_BACKUP_ENABLED=True

# Integration Settings
EXTERNAL_API_URL=
EXTERNAL_API_KEY=
WEBHOOK_URL=

# Notification Settings
NOTIFICATION_EMAIL_ENABLED=True
NOTIFICATION_SMS_ENABLED=False
NOTIFICATION_THRESHOLD=80
EOF

    # Development template
    cat > $TEMPLATE_DIR/development/irmss.env << 'EOF'
# IRMSS Development Environment Configuration
# Copy this file to /opt/django-apps/irmss/.env and customize

# Django Settings
DEBUG=True
SECRET_KEY=dev-secret-key-change-in-production
ALLOWED_HOSTS=192.168.3.5,localhost,127.0.0.1,*
DJANGO_SETTINGS_MODULE=irmss.settings

# Database Configuration (SQLite for development)
DATABASE_URL=sqlite:///opt/django-apps/irmss/db.sqlite3
DB_NAME=irmss_dev
DB_USER=irmss_dev
DB_PASSWORD=dev_password
DB_HOST=localhost
DB_PORT=3306
DB_ENGINE=django.db.backends.sqlite3

# Redis Configuration
REDIS_URL=redis://localhost:6379/1
CELERY_BROKER_URL=redis://localhost:6379/1
CELERY_RESULT_BACKEND=redis://localhost:6379/1

# Email Configuration (Console backend for development)
EMAIL_BACKEND=django.core.mail.backends.console.EmailBackend
EMAIL_HOST=localhost
EMAIL_PORT=587
EMAIL_USE_TLS=False
EMAIL_HOST_USER=
EMAIL_HOST_PASSWORD=
DEFAULT_FROM_EMAIL=IRMSS Dev <dev@localhost>

# App Settings
APP_NAME=irmss
APP_URL=http://192.168.3.5/irrms
TIME_ZONE=Asia/Manila
LANGUAGE_CODE=en-us

# Security Settings (Relaxed for development)
SESSION_EXPIRE_AT_BROWSER_CLOSE=False
SESSION_ENGINE=django.contrib.sessions.backends.db
SESSION_COOKIE_HTTPONLY=False
SESSION_SAVE_EVERY_REQUEST=True
SECURE_BROWSER_XSS_FILTER=False
SECURE_CONTENT_TYPE_NOSNIFF=False
SECURE_SSL_REDIRECT=False
SESSION_COOKIE_SECURE=False
CSRF_COOKIE_SECURE=False

# Static Files
STATIC_URL=/static/
STATIC_ROOT=/opt/django-apps/irmss/staticfiles
MEDIA_URL=/media/
MEDIA_ROOT=/opt/django-apps/irmss/media

# Logging (Verbose for development)
LOG_LEVEL=DEBUG
LOG_FILE=/var/log/django-apps/irmss/django.log

# IRMSS Specific Settings
IRMSS_API_ENABLED=True
IRMSS_DATA_RETENTION_DAYS=30
IRMSS_REPORT_GENERATION=True
IRMSS_BACKUP_ENABLED=False

# Integration Settings
EXTERNAL_API_URL=
EXTERNAL_API_KEY=
WEBHOOK_URL=

# Notification Settings (Disabled for development)
NOTIFICATION_EMAIL_ENABLED=False
NOTIFICATION_SMS_ENABLED=False
NOTIFICATION_THRESHOLD=80
EOF

    print_success "IRMSS environment templates created"
}

# Function to create FireGuard environment template
create_fireguard_template() {
    print_status "Creating FireGuard environment template..."
    
    # Production template
    cat > $TEMPLATE_DIR/production/fireguard.env << 'EOF'
# FireGuard Production Environment Configuration
# Copy this file to /opt/django-apps/fireguard/.env and customize

# Django Settings
DEBUG=False
SECRET_KEY=your-secret-key-here
ALLOWED_HOSTS=192.168.3.5,localhost,127.0.0.1,yourdomain.com
DJANGO_SETTINGS_MODULE=fireguard.settings_production

# Database Configuration
DATABASE_URL=mysql://fireguard_user:your-db-password@localhost:3306/fireguard_db
DB_NAME=fireguard_db
DB_USER=fireguard_user
DB_PASSWORD=your-db-password-here
DB_HOST=localhost
DB_PORT=3306
DB_ENGINE=django.db.backends.mysql

# Redis Configuration
REDIS_URL=redis://localhost:6379/0
CELERY_BROKER_URL=redis://localhost:6379/0
CELERY_RESULT_BACKEND=redis://localhost:6379/0

# Email Configuration
EMAIL_BACKEND=django.core.mail.backends.smtp.EmailBackend
EMAIL_HOST=smtp.gmail.com
EMAIL_PORT=587
EMAIL_USE_TLS=True
EMAIL_HOST_USER=fireguard@example.com
EMAIL_HOST_PASSWORD=your-email-password
DEFAULT_FROM_EMAIL=FireGuard <fireguard@example.com>

# App Settings
APP_NAME=fireguard
APP_URL=http://192.168.3.5/fireguard
TIME_ZONE=Asia/Manila
LANGUAGE_CODE=en-us

# Security Settings
SESSION_EXPIRE_AT_BROWSER_CLOSE=False
SESSION_ENGINE=django.contrib.sessions.backends.db
SESSION_COOKIE_HTTPONLY=True
SESSION_SAVE_EVERY_REQUEST=True
SECURE_BROWSER_XSS_FILTER=True
SECURE_CONTENT_TYPE_NOSNIFF=True
SECURE_HSTS_INCLUDE_SUBDOMAINS=True
SECURE_HSTS_SECONDS=31536000
SECURE_SSL_REDIRECT=False
SESSION_COOKIE_SECURE=False
CSRF_COOKIE_SECURE=False

# Static Files
STATIC_URL=/static/
STATIC_ROOT=/opt/django-apps/fireguard/staticfiles
MEDIA_URL=/media/
MEDIA_ROOT=/opt/django-apps/fireguard/media

# Logging
LOG_LEVEL=INFO
LOG_FILE=/var/log/django-apps/fireguard/django.log

# FireGuard Specific Settings
FIREGUARD_API_ENABLED=True
FIREGUARD_DATA_RETENTION_DAYS=365
FIREGUARD_ALERT_ENABLED=True
FIREGUARD_BACKUP_ENABLED=True

# Fire Detection Settings
FIRE_DETECTION_ENABLED=True
FIRE_SENSOR_TIMEOUT=300
FIRE_ALERT_THRESHOLD=75.0
FIRE_ALERT_COOLDOWN=300

# Integration Settings
EXTERNAL_API_URL=
EXTERNAL_API_KEY=
WEBHOOK_URL=
FIRE_DEPARTMENT_CONTACT=+1234567890

# Notification Settings
NOTIFICATION_EMAIL_ENABLED=True
NOTIFICATION_SMS_ENABLED=True
NOTIFICATION_THRESHOLD=80
EMERGENCY_CONTACT_ENABLED=True
EOF

    # Development template
    cat > $TEMPLATE_DIR/development/fireguard.env << 'EOF'
# FireGuard Development Environment Configuration
# Copy this file to /opt/django-apps/fireguard/.env and customize

# Django Settings
DEBUG=True
SECRET_KEY=dev-secret-key-change-in-production
ALLOWED_HOSTS=192.168.3.5,localhost,127.0.0.1,*
DJANGO_SETTINGS_MODULE=fireguard.settings

# Database Configuration (SQLite for development)
DATABASE_URL=sqlite:///opt/django-apps/fireguard/db.sqlite3
DB_NAME=fireguard_dev
DB_USER=fireguard_dev
DB_PASSWORD=dev_password
DB_HOST=localhost
DB_PORT=3306
DB_ENGINE=django.db.backends.sqlite3

# Redis Configuration
REDIS_URL=redis://localhost:6379/1
CELERY_BROKER_URL=redis://localhost:6379/1
CELERY_RESULT_BACKEND=redis://localhost:6379/1

# Email Configuration (Console backend for development)
EMAIL_BACKEND=django.core.mail.backends.console.EmailBackend
EMAIL_HOST=localhost
EMAIL_PORT=587
EMAIL_USE_TLS=False
EMAIL_HOST_USER=
EMAIL_HOST_PASSWORD=
DEFAULT_FROM_EMAIL=FireGuard Dev <dev@localhost>

# App Settings
APP_NAME=fireguard
APP_URL=http://192.168.3.5/fireguard
TIME_ZONE=Asia/Manila
LANGUAGE_CODE=en-us

# Security Settings (Relaxed for development)
SESSION_EXPIRE_AT_BROWSER_CLOSE=False
SESSION_ENGINE=django.contrib.sessions.backends.db
SESSION_COOKIE_HTTPONLY=False
SESSION_SAVE_EVERY_REQUEST=True
SECURE_BROWSER_XSS_FILTER=False
SECURE_CONTENT_TYPE_NOSNIFF=False
SECURE_SSL_REDIRECT=False
SESSION_COOKIE_SECURE=False
CSRF_COOKIE_SECURE=False

# Static Files
STATIC_URL=/static/
STATIC_ROOT=/opt/django-apps/fireguard/staticfiles
MEDIA_URL=/media/
MEDIA_ROOT=/opt/django-apps/fireguard/media

# Logging (Verbose for development)
LOG_LEVEL=DEBUG
LOG_FILE=/var/log/django-apps/fireguard/django.log

# FireGuard Specific Settings
FIREGUARD_API_ENABLED=True
FIREGUARD_DATA_RETENTION_DAYS=30
FIREGUARD_ALERT_ENABLED=False
FIREGUARD_BACKUP_ENABLED=False

# Fire Detection Settings
FIRE_DETECTION_ENABLED=True
FIRE_SENSOR_TIMEOUT=300
FIRE_ALERT_THRESHOLD=75.0
FIRE_ALERT_COOLDOWN=300

# Integration Settings
EXTERNAL_API_URL=
EXTERNAL_API_KEY=
WEBHOOK_URL=
FIRE_DEPARTMENT_CONTACT=+1234567890

# Notification Settings (Disabled for development)
NOTIFICATION_EMAIL_ENABLED=False
NOTIFICATION_SMS_ENABLED=False
NOTIFICATION_THRESHOLD=80
EMERGENCY_CONTACT_ENABLED=False
EOF

    print_success "FireGuard environment templates created"
}

# Function to create deployment script
create_deployment_script() {
    print_status "Creating deployment script..."
    
    cat > /usr/local/bin/deploy-app.sh << 'EOF'
#!/bin/bash

# Application Deployment Script for Django Applications
TEMPLATE_DIR="/opt/django-apps/env-templates"
BASE_DIR="/opt/django-apps"

show_usage() {
    echo "Application Deployment Script"
    echo "Usage: $0 <app_name> <environment> [--force]"
    echo ""
    echo "Available apps: weatherapp, irmss, fireguard"
    echo "Available environments: production, development, staging"
    echo ""
    echo "Options:"
    echo "  --force    Force deployment without confirmation"
    echo ""
    echo "Example: $0 weatherapp production"
    echo "Example: $0 irmss development --force"
}

deploy_app() {
    local app=$1
    local environment=$2
    local force=$3
    
    # Validate inputs
    if [[ ! " weatherapp irmss fireguard " =~ " $app " ]]; then
        echo "❌ Invalid app name: $app"
        return 1
    fi
    
    if [[ ! " production development staging " =~ " $environment " ]]; then
        echo "❌ Invalid environment: $environment"
        return 1
    fi
    
    # Check if template exists
    local template_file="$TEMPLATE_DIR/$environment/$app.env"
    if [ ! -f "$template_file" ]; then
        echo "❌ Template file not found: $template_file"
        return 1
    fi
    
    # Confirm deployment
    if [ "$force" != "--force" ]; then
        echo "This will deploy $app in $environment environment."
        echo "Template file: $template_file"
        echo "Target directory: $BASE_DIR/$app"
        echo ""
        read -p "Are you sure you want to continue? (yes/no): " confirm
        
        if [ "$confirm" != "yes" ]; then
            echo "Deployment cancelled"
            return 0
        fi
    fi
    
    echo "Starting deployment of $app in $environment environment..."
    
    # Create app directory if it doesn't exist
    mkdir -p $BASE_DIR/$app
    
    # Copy environment template
    cp $template_file $BASE_DIR/$app/.env
    
    # Set permissions
    chown -R django-$app:django-$app $BASE_DIR/$app
    chmod 600 $BASE_DIR/$app/.env
    
    # Create necessary directories
    mkdir -p $BASE_DIR/$app/staticfiles
    mkdir -p $BASE_DIR/$app/media
    mkdir -p $BASE_DIR/$app/logs
    
    # Set permissions for directories
    chown -R django-$app:django-$app $BASE_DIR/$app/staticfiles
    chown -R django-$app:django-$app $BASE_DIR/$app/media
    chown -R django-$app:django-$app $BASE_DIR/$app/logs
    
    echo "✅ Environment configuration deployed for $app in $environment"
    echo ""
    echo "Next steps:"
    echo "1. Review and customize the environment file: $BASE_DIR/$app/.env"
    echo "2. Install application dependencies"
    echo "3. Run database migrations"
    echo "4. Start the application services"
    echo ""
    echo "Use the following commands:"
    echo "  systemctl start django-$app"
    echo "  systemctl start celery-$app"
    echo "  systemctl start celerybeat-$app"
}

# Main script logic
if [ $# -lt 2 ]; then
    show_usage
    exit 1
fi

app=$1
environment=$2
force=$3

deploy_app $app $environment $force
EOF

    chmod +x /usr/local/bin/deploy-app.sh
    
    print_success "Deployment script created"
}

# Function to create environment management script
create_env_manager() {
    print_status "Creating environment management script..."
    
    cat > /usr/local/bin/env-manager.sh << 'EOF'
#!/bin/bash

# Environment Management Script for Django Applications
TEMPLATE_DIR="/opt/django-apps/env-templates"
BASE_DIR="/opt/django-apps"

show_usage() {
    echo "Environment Manager for Django Applications"
    echo "Usage: $0 <command> [app_name] [environment]"
    echo ""
    echo "Commands:"
    echo "  list                    - List all available templates"
    echo "  show <app> <env>        - Show environment configuration"
    echo "  deploy <app> <env>      - Deploy environment configuration"
    echo "  backup <app>            - Backup current environment"
    echo "  restore <app> <file>    - Restore environment from backup"
    echo "  validate <app> <env>    - Validate environment configuration"
    echo ""
    echo "Available apps: weatherapp, irmss, fireguard"
    echo "Available environments: production, development, staging"
}

list_templates() {
    echo "=== Available Environment Templates ==="
    for env in production development staging; do
        echo ""
        echo "Environment: $env"
        for app in weatherapp irmss fireguard; do
            if [ -f "$TEMPLATE_DIR/$env/$app.env" ]; then
                echo "  ✅ $app"
            else
                echo "  ❌ $app (missing)"
            fi
        done
    done
}

show_config() {
    local app=$1
    local env=$2
    
    if [ -z "$app" ] || [ -z "$env" ]; then
        echo "Please specify app name and environment"
        return 1
    fi
    
    local template_file="$TEMPLATE_DIR/$env/$app.env"
    if [ ! -f "$template_file" ]; then
        echo "❌ Template file not found: $template_file"
        return 1
    fi
    
    echo "=== Environment Configuration for $app ($env) ==="
    cat $template_file
}

deploy_config() {
    local app=$1
    local env=$2
    
    if [ -z "$app" ] || [ -z "$env" ]; then
        echo "Please specify app name and environment"
        return 1
    fi
    
    /usr/local/bin/deploy-app.sh $app $env
}

backup_config() {
    local app=$1
    
    if [ -z "$app" ]; then
        echo "Please specify app name"
        return 1
    fi
    
    local backup_file="$BASE_DIR/$app/.env.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [ -f "$BASE_DIR/$app/.env" ]; then
        cp $BASE_DIR/$app/.env $backup_file
        echo "✅ Environment backed up to: $backup_file"
    else
        echo "❌ No environment file found for $app"
        return 1
    fi
}

restore_config() {
    local app=$1
    local backup_file=$2
    
    if [ -z "$app" ] || [ -z "$backup_file" ]; then
        echo "Please specify app name and backup file"
        return 1
    fi
    
    if [ ! -f "$backup_file" ]; then
        echo "❌ Backup file not found: $backup_file"
        return 1
    fi
    
    cp $backup_file $BASE_DIR/$app/.env
    chown django-$app:django-$app $BASE_DIR/$app/.env
    chmod 600 $BASE_DIR/$app/.env
    
    echo "✅ Environment restored from: $backup_file"
}

validate_config() {
    local app=$1
    local env=$2
    
    if [ -z "$app" ] || [ -z "$env" ]; then
        echo "Please specify app name and environment"
        return 1
    fi
    
    local template_file="$TEMPLATE_DIR/$env/$app.env"
    if [ ! -f "$template_file" ]; then
        echo "❌ Template file not found: $template_file"
        return 1
    fi
    
    echo "=== Validating environment configuration for $app ($env) ==="
    
    # Check for required variables
    local required_vars=("SECRET_KEY" "DEBUG" "DATABASE_URL" "REDIS_URL")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if ! grep -q "^$var=" $template_file; then
            missing_vars+=($var)
        fi
    done
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        echo "❌ Missing required variables: ${missing_vars[*]}"
        return 1
    else
        echo "✅ All required variables present"
    fi
    
    # Check for placeholder values
    local placeholder_vars=$(grep -E "your-|change-|test-" $template_file | wc -l)
    if [ $placeholder_vars -gt 0 ]; then
        echo "⚠️ Found $placeholder_vars placeholder values that need to be customized"
        grep -E "your-|change-|test-" $template_file
    else
        echo "✅ No placeholder values found"
    fi
    
    echo "✅ Environment configuration validation completed"
}

# Main script logic
if [ $# -lt 1 ]; then
    show_usage
    exit 1
fi

command=$1
app=$2
env=$3

case $command in
    "list")
        list_templates
        ;;
    "show")
        show_config $app $env
        ;;
    "deploy")
        deploy_config $app $env
        ;;
    "backup")
        backup_config $app
        ;;
    "restore")
        restore_config $app $env
        ;;
    "validate")
        validate_config $app $env
        ;;
    *)
        echo "Unknown command: $command"
        show_usage
        ;;
esac
EOF

    chmod +x /usr/local/bin/env-manager.sh
    
    print_success "Environment management script created"
}

# Main function
main() {
    print_status "Starting environment template creation..."
    
    check_root
    create_template_directory
    create_weatherapp_template
    create_irmss_template
    create_fireguard_template
    create_deployment_script
    create_env_manager
    
    print_success "Environment template creation completed successfully!"
    print_status ""
    print_status "Environment templates created in: $TEMPLATE_DIR"
    print_status ""
    print_status "Available templates:"
    print_status "  Production: $TEMPLATE_DIR/production/"
    print_status "  Development: $TEMPLATE_DIR/development/"
    print_status "  Staging: $TEMPLATE_DIR/staging/"
    print_status ""
    print_status "Use the following commands to manage environments:"
    print_status "  /usr/local/bin/env-manager.sh list"
    print_status "  /usr/local/bin/env-manager.sh show <app> <env>"
    print_status "  /usr/local/bin/deploy-app.sh <app> <env>"
    print_status "  /usr/local/bin/env-manager.sh validate <app> <env>"
    print_status ""
    print_status "To deploy an application:"
    print_status "  1. Copy the appropriate template to your app directory"
    print_status "  2. Customize the environment variables"
    print_status "  3. Start your application services"
}

# Run main function
main "$@"
