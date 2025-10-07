#!/bin/bash
# Test script to verify deployment is working correctly

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
    echo -e "${GREEN}[PASS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNING=0

# Function to run a test
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="$3"
    
    echo -n "Testing $test_name... "
    
    if eval "$test_command" >/dev/null 2>&1; then
        if [ "$expected_result" = "pass" ]; then
            print_status "$test_name"
            ((TESTS_PASSED++))
        else
            print_error "$test_name (unexpected success)"
            ((TESTS_FAILED++))
        fi
    else
        if [ "$expected_result" = "fail" ]; then
            print_status "$test_name"
            ((TESTS_PASSED++))
        else
            print_error "$test_name"
            ((TESTS_FAILED++))
        fi
    fi
}

# Function to run a warning test
run_warning_test() {
    local test_name="$1"
    local test_command="$2"
    
    echo -n "Testing $test_name... "
    
    if eval "$test_command" >/dev/null 2>&1; then
        print_status "$test_name"
        ((TESTS_PASSED++))
    else
        print_warning "$test_name"
        ((TESTS_WARNING++))
    fi
}

print_header "Weather Application Deployment Test Suite"
echo ""

# Test 1: Application directory exists
run_test "Application Directory" "[ -d '/home/bccbsis-py-admin/weatherapp' ]" "pass"

# Test 2: Virtual environment exists
run_test "Virtual Environment" "[ -d '/home/bccbsis-py-admin/weatherapp/venv' ]" "pass"

# Test 3: Django manage.py exists
run_test "Django manage.py" "[ -f '/home/bccbsis-py-admin/weatherapp/manage.py' ]" "pass"

# Test 4: Supervisor configuration exists
run_test "Supervisor Config" "[ -f '/etc/supervisor/conf.d/weatherapp.conf' ]" "pass"

# Test 5: Nginx configuration exists
run_test "Nginx Config" "[ -f '/etc/nginx/sites-available/weatherapp' ]" "pass"

# Test 6: Nginx site is enabled
run_test "Nginx Site Enabled" "[ -L '/etc/nginx/sites-enabled/weatherapp' ]" "pass"

# Test 7: Nginx configuration is valid
run_test "Nginx Config Valid" "sudo nginx -t" "pass"

# Test 8: Supervisor services are running
run_test "Weather App Service" "sudo supervisorctl status weatherapp | grep -q RUNNING" "pass"

# Test 9: Port 8001 is listening
run_test "Port 8001 Listening" "netstat -tlnp | grep -q ':8001'" "pass"

# Test 10: Health endpoint responds
run_test "Health Endpoint" "curl -s -o /dev/null -w '%{http_code}' 'http://192.168.3.5/health' | grep -q '200'" "pass"

# Test 11: Weather app endpoint responds (may be 200 or 302)
run_warning_test "Weather App Endpoint" "curl -s -o /dev/null -w '%{http_code}' 'http://192.168.3.5/weatherapp/' | grep -qE '(200|302)'"

# Test 12: Log files exist
run_test "Gunicorn Log File" "[ -f '/var/log/weatherapp/gunicorn.log' ]" "pass"

# Test 13: Database connection (if possible)
run_warning_test "Database Connection" "cd /home/bccbsis-py-admin/weatherapp && source venv/bin/activate && export DJANGO_SETTINGS_MODULE=weatheralert.settings && python manage.py check --database default"

# Test 14: Static files collected
run_test "Static Files" "[ -d '/home/bccbsis-py-admin/weatherapp/staticfiles' ]" "pass"

# Test 15: Environment file exists
run_test "Environment File" "[ -f '/home/bccbsis-py-admin/weatherapp/.env' ]" "pass"

# Summary
print_header "Test Results Summary"
echo ""
echo "Tests Passed: $TESTS_PASSED"
echo "Tests Failed: $TESTS_FAILED"
echo "Tests Warning: $TESTS_WARNING"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    print_status "All critical tests passed! Deployment appears to be working correctly."
    echo ""
    print_status "Your application should be accessible at:"
    echo "  Main URL: http://192.168.3.5/weatherapp/"
    echo "  Health Check: http://192.168.3.5/health"
    echo "  Admin Panel: http://192.168.3.5/weatherapp/admin/"
else
    print_error "Some tests failed. Please check the issues above."
    echo ""
    print_status "Troubleshooting commands:"
    echo "  Check supervisor status: sudo supervisorctl status"
    echo "  Check nginx status: sudo systemctl status nginx"
    echo "  Check logs: sudo tail -f /var/log/weatherapp/gunicorn.log"
    echo "  Test nginx config: sudo nginx -t"
fi

if [ $TESTS_WARNING -gt 0 ]; then
    echo ""
    print_warning "Some tests had warnings. These are not critical but should be checked:"
    echo "  - Weather app endpoint may need Django setup"
    echo "  - Database connection may need configuration"
fi

echo ""
print_status "Test completed on $(date)"
