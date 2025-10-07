#!/bin/bash
# Validation script to check if deployment is working correctly

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_status() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
APP_NAME="weatherapp"
APP_DIR="/home/bccbsis-py-admin/$APP_NAME"
VENV_DIR="$APP_DIR/venv"

print_header "Weather Application Deployment Validation"
echo ""

# Check 1: Application directory exists
print_header "1. Checking Application Directory"
if [ -d "$APP_DIR" ]; then
    print_status "Application directory exists: $APP_DIR"
else
    print_error "Application directory not found: $APP_DIR"
    exit 1
fi

# Check 2: Virtual environment exists
print_header "2. Checking Virtual Environment"
if [ -d "$VENV_DIR" ]; then
    print_status "Virtual environment exists: $VENV_DIR"
else
    print_error "Virtual environment not found: $VENV_DIR"
    exit 1
fi

# Check 3: Django project structure
print_header "3. Checking Django Project Structure"
cd "$APP_DIR"

if [ -f "manage.py" ]; then
    print_status "manage.py found"
else
    print_error "manage.py not found"
    exit 1
fi

if [ -d "weatheralert" ]; then
    print_status "weatheralert directory found"
else
    print_error "weatheralert directory not found"
    exit 1
fi

# Check 4: Supervisor services
print_header "4. Checking Supervisor Services"
if sudo supervisorctl status weatherapp | grep -q "RUNNING"; then
    print_status "weatherapp service is running"
else
    print_error "weatherapp service is not running"
    sudo supervisorctl status weatherapp
fi

if sudo supervisorctl status weatherapp-celery-worker | grep -q "RUNNING"; then
    print_status "celery worker is running"
else
    print_warning "celery worker is not running"
fi

if sudo supervisorctl status weatherapp-celery-beat | grep -q "RUNNING"; then
    print_status "celery beat is running"
else
    print_warning "celery beat is not running"
fi

# Check 5: Nginx configuration
print_header "5. Checking Nginx Configuration"
if sudo nginx -t >/dev/null 2>&1; then
    print_status "Nginx configuration is valid"
else
    print_error "Nginx configuration has errors"
    sudo nginx -t
fi

# Check 6: Port 8001 is listening
print_header "6. Checking Port 8001"
if netstat -tlnp | grep -q ":8001"; then
    print_status "Port 8001 is listening"
else
    print_error "Port 8001 is not listening"
fi

# Check 7: Health endpoint
print_header "7. Checking Health Endpoint"
if curl -s -o /dev/null -w "%{http_code}" "http://192.168.3.5/health" | grep -q "200"; then
    print_status "Health endpoint is responding"
else
    print_error "Health endpoint is not responding"
fi

# Check 8: Weather app endpoint
print_header "8. Checking Weather App Endpoint"
response_code=$(curl -s -o /dev/null -w "%{http_code}" "http://192.168.3.5/weatherapp/")
if [ "$response_code" = "200" ]; then
    print_status "Weather app endpoint is responding (200)"
elif [ "$response_code" = "302" ]; then
    print_status "Weather app endpoint is redirecting (302) - likely to login"
else
    print_warning "Weather app endpoint returned: $response_code"
fi

# Check 9: Log files
print_header "9. Checking Log Files"
if [ -f "/var/log/weatherapp/gunicorn.log" ]; then
    print_status "Gunicorn log file exists"
    log_size=$(stat -c%s "/var/log/weatherapp/gunicorn.log" 2>/dev/null || echo "0")
    if [ "$log_size" -gt 0 ]; then
        print_status "Gunicorn log has content ($log_size bytes)"
    else
        print_warning "Gunicorn log is empty"
    fi
else
    print_warning "Gunicorn log file not found"
fi

# Check 10: Database connection
print_header "10. Checking Database Connection"
cd "$APP_DIR"
source "$VENV_DIR/bin/activate"
export DJANGO_SETTINGS_MODULE=weatheralert.settings

if python manage.py check --database default >/dev/null 2>&1; then
    print_status "Database connection is working"
else
    print_error "Database connection failed"
fi

# Summary
print_header "Validation Summary"
echo ""
print_status "Deployment validation completed!"
echo ""
print_status "Your application should be accessible at:"
echo "  Main URL: http://192.168.3.5/weatherapp/"
echo "  Health Check: http://192.168.3.5/health"
echo "  Admin Panel: http://192.168.3.5/weatherapp/admin/"
echo ""

print_status "Useful commands:"
echo "  Check status: sudo supervisorctl status"
echo "  View logs: sudo tail -f /var/log/weatherapp/gunicorn.log"
echo "  Restart app: sudo supervisorctl restart weatherapp"
echo "  Check nginx: sudo nginx -t && sudo systemctl status nginx"
