#!/bin/bash
# Environment setup script for weather application deployment

set -e

echo "=== Weather Application Environment Setup ==="
echo "Starting setup on $(date)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Check if sudo is available
if ! command -v sudo &> /dev/null; then
    print_error "sudo is not installed. Please install it first."
    exit 1
fi

print_status "Updating system packages..."
sudo apt update && sudo apt upgrade -y

print_status "Installing system dependencies..."
sudo apt install -y python3 python3-pip python3-venv python3-dev
sudo apt install -y nginx supervisor redis-server
sudo apt install -y mysql-server mysql-client
sudo apt install -y git curl wget unzip
sudo apt install -y build-essential libssl-dev libffi-dev
sudo apt install -y libmysqlclient-dev pkg-config
sudo apt install -y libhdf5-dev libhdf5-serial-dev

print_status "Creating application directory structure..."
sudo mkdir -p /home/$USER/weatherapp
sudo chown -R $USER:www-data /home/$USER/weatherapp
sudo chmod -R 755 /home/$USER/weatherapp

print_status "Creating log directories..."
sudo mkdir -p /var/log/weatherapp
sudo chown -R $USER:www-data /var/log/weatherapp
sudo chmod -R 755 /var/log/weatherapp

print_status "Setting up MySQL..."
sudo systemctl start mysql
sudo systemctl enable mysql

# Create MySQL database and user
print_status "Creating MySQL database and user..."
sudo mysql -e "CREATE DATABASE IF NOT EXISTS u520834156_dbweatherApp CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
sudo mysql -e "CREATE USER IF NOT EXISTS 'u520834156_uWApp2024'@'localhost' IDENTIFIED BY 'bIxG2Z$In#8';"
sudo mysql -e "GRANT ALL PRIVILEGES ON u520834156_dbweatherApp.* TO 'u520834156_uWApp2024'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

print_status "Configuring Redis..."
sudo systemctl start redis-server
sudo systemctl enable redis-server

print_status "Configuring Nginx..."
sudo systemctl start nginx
sudo systemctl enable nginx

print_status "Configuring Supervisor..."
sudo systemctl start supervisor
sudo systemctl enable supervisor

print_status "Setting up firewall..."
sudo ufw --force enable
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80
sudo ufw allow 443

print_status "Installing additional security tools..."
sudo apt install -y fail2ban unattended-upgrades

print_status "Environment setup completed successfully!"
print_status "Next steps:"
echo "1. Copy your application code to /home/$USER/weatherapp/"
echo "2. Create virtual environment and install dependencies"
echo "3. Configure environment variables"
echo "4. Run database migrations"
echo "5. Configure Nginx and Supervisor"
echo "6. Start the application services"

print_status "Setup completed on $(date)"
