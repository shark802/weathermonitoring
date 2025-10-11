#!/bin/bash

# =============================================================================
# WeatherAlert Deployment Verification Script
# Tests if the deployment is working correctly
# =============================================================================

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SERVER_IP="119.93.148.180"
APP_URL_PATH="weatherapp"
APP_DIR="/opt/django-apps/weatherapp"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}WeatherAlert Deployment Verification${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Function to print test result
test_result() {
    local test_name=$1
    local result=$2
    
    if [ $result -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $test_name"
        ((TESTS_FAILED++))
    fi
}

echo -e "${YELLOW}Running system checks...${NC}"
echo ""

# Test 1: Check if Django service is running
echo -n "Checking Django service... "
systemctl is-active --quiet django-weatherapp
test_result "Django service is running" $?

# Test 2: Check if Celery service is running
echo -n "Checking Celery service... "
systemctl is-active --quiet celery-weatherapp
test_result "Celery worker is running" $?

# Test 3: Check if Celery Beat is running
echo -n "Checking Celery Beat... "
systemctl is-active --quiet celerybeat-weatherapp
test_result "Celery beat is running" $?

# Test 4: Check if Nginx is running
echo -n "Checking Nginx... "
systemctl is-active --quiet nginx
test_result "Nginx is running" $?

# Test 5: Check if Redis is running
echo -n "Checking Redis... "
systemctl is-active --quiet redis-server
test_result "Redis is running" $?

# Test 6: Check if application directory exists
echo -n "Checking application directory... "
[ -d "$APP_DIR" ]
test_result "Application directory exists" $?

# Test 7: Check if virtual environment exists
echo -n "Checking Python virtual environment... "
[ -f "$APP_DIR/venv/bin/python" ]
test_result "Virtual environment exists" $?

# Test 8: Check if static files exist
echo -n "Checking static files... "
[ -d "$APP_DIR/staticfiles" ] && [ "$(ls -A $APP_DIR/staticfiles)" ]
test_result "Static files collected" $?

# Test 9: Check if Nginx config exists
echo -n "Checking Nginx configuration... "
[ -f "/etc/nginx/sites-enabled/weatherapp" ]
test_result "Nginx configuration exists" $?

# Test 10: Test Nginx configuration
echo -n "Testing Nginx configuration... "
nginx -t &>/dev/null
test_result "Nginx configuration valid" $?

# Test 11: Check if port 8001 is listening (Gunicorn)
echo -n "Checking Gunicorn port... "
netstat -tlnp | grep -q ":8001"
test_result "Gunicorn listening on port 8001" $?

# Test 12: Check if port 80 is listening (Nginx)
echo -n "Checking Nginx port... "
netstat -tlnp | grep -q ":80"
test_result "Nginx listening on port 80" $?

# Test 13: Test HTTP response
echo -n "Testing HTTP response... "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$SERVER_IP/$APP_URL_PATH/ 2>/dev/null)
[ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]
test_result "Application responding (HTTP $HTTP_CODE)" $?

# Test 14: Test static files access
echo -n "Testing static files... "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$SERVER_IP/$APP_URL_PATH/static/ 2>/dev/null)
[ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "403" ] || [ "$HTTP_CODE" = "301" ]
test_result "Static files accessible" $?

# Test 15: Check log files
echo -n "Checking log files... "
[ -f "/var/log/django-apps/weatherapp/error.log" ]
test_result "Log files exist" $?

# Test 16: Check database connectivity
echo -n "Testing database connection... "
cd $APP_DIR && source venv/bin/activate && python -c "
import django
import os
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'weatheralert.settings')
django.setup()
from django.db import connection
connection.ensure_connection()
" &>/dev/null
test_result "Database connection successful" $?
deactivate 2>/dev/null

# Test 17: Check Redis connectivity
echo -n "Testing Redis connection... "
redis-cli ping &>/dev/null
test_result "Redis connection successful" $?

# Test 18: Check disk space
echo -n "Checking disk space... "
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
[ $DISK_USAGE -lt 90 ]
test_result "Disk space available (${DISK_USAGE}% used)" $?

# Test 19: Check memory
echo -n "Checking memory... "
MEMORY_AVAILABLE=$(free | awk 'NR==2{printf "%.0f", $7*100/$2}')
[ $MEMORY_AVAILABLE -gt 10 ]
test_result "Memory available (${MEMORY_AVAILABLE}% free)" $?

# Test 20: Check management script
echo -n "Checking management script... "
[ -x "/usr/local/bin/weatherapp-manage.sh" ]
test_result "Management script installed" $?

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test Results${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))
echo -e "Total tests: ${TOTAL_TESTS}"
echo -e "${GREEN}Passed: ${TESTS_PASSED}${NC}"
echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ All tests passed! Deployment is successful.${NC}"
    echo ""
    echo -e "${GREEN}Your application is accessible at:${NC}"
    echo -e "${GREEN}http://$SERVER_IP/$APP_URL_PATH${NC}"
    echo ""
    exit 0
else
    echo ""
    echo -e "${YELLOW}⚠ Some tests failed. Please review the results above.${NC}"
    echo ""
    echo -e "${YELLOW}Troubleshooting steps:${NC}"
    echo "1. Check service logs: journalctl -u django-weatherapp -n 50"
    echo "2. Check error logs: tail -f /var/log/django-apps/weatherapp/error.log"
    echo "3. Restart services: weatherapp-manage.sh restart"
    echo "4. Review deployment guide: cat deploy_scripts/README_SERVER_DEPLOYMENT.md"
    echo ""
    exit 1
fi

