#!/bin/bash
# Application monitoring script

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

# Function to check if a service is running
check_service() {
    local service_name="$1"
    if systemctl is-active --quiet "$service_name"; then
        print_status "$service_name is running"
        return 0
    else
        print_error "$service_name is not running"
        return 1
    fi
}

# Function to check if a supervisor program is running
check_supervisor_program() {
    local program_name="$1"
    local status=$(sudo supervisorctl status "$program_name" 2>/dev/null | awk '{print $2}')
    
    if [ "$status" = "RUNNING" ]; then
        print_status "$program_name is running"
        return 0
    elif [ "$status" = "STOPPED" ]; then
        print_error "$program_name is stopped"
        return 1
    elif [ "$status" = "STARTING" ]; then
        print_warning "$program_name is starting"
        return 1
    else
        print_error "$program_name status unknown: $status"
        return 1
    fi
}

# Function to check disk usage
check_disk_usage() {
    local path="$1"
    local usage=$(df -h "$path" | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [ "$usage" -lt 80 ]; then
        print_status "Disk usage for $path: ${usage}%"
    elif [ "$usage" -lt 90 ]; then
        print_warning "Disk usage for $path: ${usage}% (getting high)"
    else
        print_error "Disk usage for $path: ${usage}% (critical)"
    fi
}

# Function to check memory usage
check_memory_usage() {
    local mem_info=$(free -h | awk 'NR==2{printf "%.0f", $3/$2 * 100.0}')
    
    if [ "$mem_info" -lt 80 ]; then
        print_status "Memory usage: ${mem_info}%"
    elif [ "$mem_info" -lt 90 ]; then
        print_warning "Memory usage: ${mem_info}% (getting high)"
    else
        print_error "Memory usage: ${mem_info}% (critical)"
    fi
}

# Function to check application endpoints
check_endpoints() {
    local base_url="http://192.168.3.5"
    
    print_header "Application Endpoints"
    
    # Check health endpoint
    if curl -s -o /dev/null -w "%{http_code}" "$base_url/health" | grep -q "200"; then
        print_status "Health check endpoint: OK"
    else
        print_error "Health check endpoint: FAILED"
    fi
    
    # Check weather app
    if curl -s -o /dev/null -w "%{http_code}" "$base_url/weatherapp/" | grep -q "200"; then
        print_status "Weather app endpoint: OK"
    else
        print_error "Weather app endpoint: FAILED"
    fi
    
    # Check for other apps (you can add more here)
    for app in $(ls /var/www/apps/ 2>/dev/null | grep -v weatherapp); do
        if curl -s -o /dev/null -w "%{http_code}" "$base_url/$app/" | grep -q "200"; then
            print_status "$app endpoint: OK"
        else
            print_error "$app endpoint: FAILED"
        fi
    done
}

# Function to show recent logs
show_recent_logs() {
    local app_name="$1"
    local log_file="/var/log/$app_name/gunicorn.log"
    
    if [ -f "$log_file" ]; then
        print_header "Recent logs for $app_name (last 10 lines)"
        sudo tail -n 10 "$log_file"
    else
        print_warning "Log file not found for $app_name"
    fi
}

# Function to show system information
show_system_info() {
    print_header "System Information"
    echo "Hostname: $(hostname)"
    echo "Uptime: $(uptime -p)"
    echo "Load Average: $(uptime | awk -F'load average:' '{print $2}')"
    echo "Date: $(date)"
    echo ""
}

# Function to show process information
show_process_info() {
    print_header "Process Information"
    echo "Top processes by CPU usage:"
    ps aux --sort=-%cpu | head -10
    echo ""
    echo "Top processes by memory usage:"
    ps aux --sort=-%mem | head -10
    echo ""
}

# Main monitoring function
main() {
    print_header "Multi-App Server Monitoring Report"
    echo "Generated on: $(date)"
    echo ""
    
    # System information
    show_system_info
    
    # Check system services
    print_header "System Services"
    check_service "nginx"
    check_service "mysql"
    check_service "redis-server"
    check_service "supervisor"
    echo ""
    
    # Check supervisor programs
    print_header "Application Services"
    check_supervisor_program "weatherapp"
    check_supervisor_program "weatherapp-celery-worker"
    check_supervisor_program "weatherapp-celery-beat"
    
    # Check for other applications
    for conf_file in /etc/supervisor/conf.d/*.conf; do
        if [ -f "$conf_file" ]; then
            app_name=$(basename "$conf_file" .conf)
            if [ "$app_name" != "weatherapp" ]; then
                check_supervisor_program "$app_name"
            fi
        fi
    done
    echo ""
    
    # Check resource usage
    print_header "Resource Usage"
    check_memory_usage
    check_disk_usage "/var/www/apps"
    check_disk_usage "/var/log"
    echo ""
    
    # Check application endpoints
    check_endpoints
    echo ""
    
    # Show recent logs for weather app
    show_recent_logs "weatherapp"
    echo ""
    
    # Show process information
    show_process_info
    
    # Show supervisor status
    print_header "Supervisor Status"
    sudo supervisorctl status
    echo ""
    
    # Show nginx status
    print_header "Nginx Status"
    sudo systemctl status nginx --no-pager -l
    echo ""
    
    print_header "Monitoring Complete"
}

# Check if script is run with specific options
case "${1:-}" in
    "logs")
        if [ -n "$2" ]; then
            show_recent_logs "$2"
        else
            print_error "Please specify app name for logs"
            echo "Usage: $0 logs <app_name>"
            exit 1
        fi
        ;;
    "status")
        sudo supervisorctl status
        ;;
    "restart")
        if [ -n "$2" ]; then
            print_status "Restarting $2..."
            sudo supervisorctl restart "$2"
        else
            print_error "Please specify app name to restart"
            echo "Usage: $0 restart <app_name>"
            exit 1
        fi
        ;;
    "endpoints")
        check_endpoints
        ;;
    *)
        main
        ;;
esac
