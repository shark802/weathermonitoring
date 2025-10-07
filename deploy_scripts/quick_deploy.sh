#!/bin/bash
# Quick deployment script - runs all setup steps in sequence

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
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root. Please run as a regular user with sudo privileges."
   exit 1
fi

print_header "Quick Deployment Script for Weather Application"
echo "This script will set up the complete environment and deploy the weather application."
echo ""

# Ask for confirmation
read -p "Do you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_status "Deployment cancelled."
    exit 0
fi

# Step 1: Environment Setup
print_header "Step 1: Setting up environment"
if [ -f "deploy_scripts/setup_environment.sh" ]; then
    chmod +x deploy_scripts/setup_environment.sh
    ./deploy_scripts/setup_environment.sh
else
    print_error "setup_environment.sh not found!"
    print_status "Please make sure you're in the correct directory."
    exit 1
fi

# Step 2: Copy application code
print_header "Step 2: Preparing application code"
if [ ! -d "/var/www/apps/weatherapp" ]; then
    print_status "Creating application directory..."
    sudo mkdir -p /var/www/apps/weatherapp
fi

print_status "Copying application code..."
sudo cp -r . /var/www/apps/weatherapp/
sudo chown -R www-data:www-data /var/www/apps/weatherapp
sudo chmod -R 755 /var/www/apps/weatherapp

# Step 3: Deploy application
print_header "Step 3: Deploying application"
if [ -f "deploy_scripts/deploy_app.sh" ]; then
    chmod +x deploy_scripts/deploy_app.sh
    ./deploy_scripts/deploy_app.sh
else
    print_error "deploy_app.sh not found!"
    exit 1
fi

# Step 4: Final verification
print_header "Step 4: Final verification"
print_status "Checking if all services are running..."

# Check nginx
if systemctl is-active --quiet nginx; then
    print_status "Nginx: Running"
else
    print_error "Nginx: Not running"
fi

# Check MySQL
if systemctl is-active --quiet mysql; then
    print_status "MySQL: Running"
else
    print_error "MySQL: Not running"
fi

# Check Redis
if systemctl is-active --quiet redis-server; then
    print_status "Redis: Running"
else
    print_error "Redis: Not running"
fi

# Check Supervisor
if systemctl is-active --quiet supervisor; then
    print_status "Supervisor: Running"
else
    print_error "Supervisor: Not running"
fi

# Check application services
print_status "Checking application services..."
sudo supervisorctl status

# Test endpoints
print_status "Testing application endpoints..."
if curl -s -o /dev/null -w "%{http_code}" "http://192.168.3.5/health" | grep -q "200"; then
    print_status "Health check: OK"
else
    print_warning "Health check: Failed"
fi

if curl -s -o /dev/null -w "%{http_code}" "http://192.168.3.5/weatherapp/" | grep -q "200"; then
    print_status "Weather app: OK"
else
    print_warning "Weather app: Failed"
fi

# Step 5: Show final information
print_header "Deployment Complete!"
echo ""
print_status "Your weather application is now deployed and accessible at:"
echo "  Main URL: http://192.168.3.5/weatherapp/"
echo "  Health Check: http://192.168.3.5/health"
echo "  Admin Panel: http://192.168.3.5/weatherapp/admin/"
echo ""

print_status "Useful commands:"
echo "  Monitor apps: ./deploy_scripts/monitor_apps.sh"
echo "  Add new app: ./deploy_scripts/add_new_app.sh <app_name> <port> <path>"
echo "  Check logs: sudo tail -f /var/log/weatherapp/gunicorn.log"
echo "  Restart app: sudo supervisorctl restart weatherapp"
echo ""

print_status "Important notes:"
echo "  1. Make sure to update the .env file with your actual configuration"
echo "  2. Create a superuser account: sudo -u www-data /var/www/apps/weatherapp/venv/bin/python /var/www/apps/weatherapp/manage.py createsuperuser"
echo "  3. Check the logs if you encounter any issues"
echo "  4. The application is configured to run on subfolder /weatherapp/"
echo ""

print_warning "Security reminders:"
echo "  - Change default passwords in .env file"
echo "  - Configure firewall properly"
echo "  - Set up SSL certificates for production"
echo "  - Regular security updates"
echo ""

print_status "Deployment completed successfully!"
