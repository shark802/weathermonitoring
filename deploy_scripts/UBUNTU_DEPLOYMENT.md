# WeatherAlert - Ubuntu Server Deployment Guide

## Complete Ubuntu 20.04/22.04 LTS Deployment

This guide is specifically for deploying WeatherAlert to Ubuntu Server at **119.93.148.180/weatherapp**

---

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Server Preparation](#server-preparation)
3. [Deployment Methods](#deployment-methods)
4. [Post-Deployment](#post-deployment)
5. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Ubuntu Server Requirements
- **OS**: Ubuntu 20.04 LTS or 22.04 LTS
- **RAM**: Minimum 2GB (4GB recommended)
- **Disk**: Minimum 20GB free space
- **CPU**: 2+ cores recommended
- **Network**: Public IP configured (119.93.148.180)
- **Access**: Root or sudo privileges

### Network Requirements
```bash
# Required ports
80/tcp   - HTTP (Nginx)
443/tcp  - HTTPS (SSL - optional)
22/tcp   - SSH (for deployment)
6379/tcp - Redis (localhost only)
8001/tcp - Gunicorn (localhost only)
```

### From Your Windows Machine
- SSH client (built into Windows 10/11)
- SCP for file transfer
- Internet connection

---

## Server Preparation

### 1. Initial Server Setup (If Fresh Ubuntu)

```bash
# SSH to your Ubuntu server
ssh root@119.93.148.180

# Update system
apt update && apt upgrade -y

# Install essential tools
apt install -y curl wget git vim nano htop

# Setup firewall
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# Set timezone (optional)
timedatectl set-timezone Asia/Manila

# Check system
lsb_release -a
free -h
df -h
```

### 2. Verify Network Configuration

```bash
# Check IP address
ip addr show

# Should show 119.93.148.180
# If not, configure network:
nano /etc/netplan/00-installer-config.yaml

# Example netplan config:
network:
  version: 2
  ethernets:
    eth0:  # or your interface name
      addresses:
        - 119.93.148.180/24
      gateway4: 119.93.148.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4

# Apply network config
netplan apply
```

---

## Deployment Methods

### Method 1: Automated Deployment from Windows (Recommended)

#### Using PowerShell Script

**On your Windows machine:**

```powershell
# 1. Open PowerShell
cd "C:\Users\JaOsn\Desktop\BCC PythonApps\weatherapp"

# 2. Run deployment
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\deploy_scripts\windows_deploy.ps1

# 3. Select Option 1 (Full deployment)
# Enter password when prompted
```

The script will:
- ✅ Transfer all files to Ubuntu server
- ✅ Install all dependencies
- ✅ Configure services
- ✅ Setup Nginx
- ✅ Start application

**Time**: 10-20 minutes for first deployment

---

### Method 2: Manual Ubuntu Deployment

#### Step 1: Transfer Files to Ubuntu Server

**From Windows PowerShell:**

```powershell
# Create deployment directory on server
ssh root@119.93.148.180 "mkdir -p /tmp/weatherapp_deploy"

# Transfer application files
scp -r weatherapp root@119.93.148.180:/tmp/weatherapp_deploy/
scp -r weatheralert root@119.93.148.180:/tmp/weatherapp_deploy/
scp manage.py root@119.93.148.180:/tmp/weatherapp_deploy/
scp requirements.txt root@119.93.148.180:/tmp/weatherapp_deploy/

# Transfer deployment script
scp deploy_scripts/deploy_to_server.sh root@119.93.148.180:/tmp/
```

#### Step 2: SSH to Ubuntu Server

```bash
ssh root@119.93.148.180
```

#### Step 3: Run Deployment Script

```bash
# Navigate to temp directory
cd /tmp

# Make script executable
chmod +x deploy_to_server.sh

# Run deployment
./deploy_to_server.sh
```

**What the script does:**

1. **System Update** (2-5 minutes)
   ```
   ✓ Updates apt packages
   ✓ Installs security updates
   ```

2. **Dependencies Installation** (3-5 minutes)
   ```
   ✓ Python 3.8+
   ✓ pip, venv, python3-dev
   ✓ Nginx web server
   ✓ Redis server
   ✓ MySQL client libraries
   ✓ Build tools
   ```

3. **Directory Structure** (1 minute)
   ```
   ✓ /opt/django-apps/weatherapp/
   ✓ /var/log/django-apps/weatherapp/
   ✓ /opt/backups/weatherapp/
   ✓ /etc/django-apps/
   ```

4. **Python Environment** (2-3 minutes)
   ```
   ✓ Creates virtual environment
   ✓ Installs Django & dependencies
   ✓ Installs Gunicorn WSGI server
   ✓ Installs Celery & Redis
   ```

5. **Configuration** (1-2 minutes)
   ```
   ✓ Environment variables (.env)
   ✓ Database connection
   ✓ Static files path
   ✓ Secret key generation
   ```

6. **Database Setup** (1-2 minutes)
   ```
   ✓ Runs migrations
   ✓ Creates database tables
   ✓ Collects static files
   ```

7. **Systemd Services** (1 minute)
   ```
   ✓ django-weatherapp.service
   ✓ celery-weatherapp.service
   ✓ celerybeat-weatherapp.service
   ```

8. **Nginx Configuration** (1 minute)
   ```
   ✓ Reverse proxy setup
   ✓ Static file serving
   ✓ Security headers
   ✓ SSL ready (when certificate added)
   ```

9. **Service Startup** (1 minute)
   ```
   ✓ Starts Django/Gunicorn
   ✓ Starts Celery workers
   ✓ Starts Celery beat
   ✓ Restarts Nginx
   ```

10. **Monitoring Setup** (1 minute)
    ```
    ✓ Creates monitoring script
    ✓ Sets up cron jobs
    ✓ Configures log rotation
    ```

#### Step 4: Verify Deployment

```bash
# Check all services
systemctl status django-weatherapp
systemctl status celery-weatherapp
systemctl status nginx
systemctl status redis-server

# Quick status check
weatherapp-manage.sh status

# Run verification tests
bash /tmp/deploy_to_server.sh verify_deployment.sh
```

---

### Method 3: Docker Deployment (Alternative)

If you prefer Docker, here's a quick setup:

```bash
# Install Docker on Ubuntu
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Install Docker Compose
apt install docker-compose -y

# Note: Docker deployment would require additional Dockerfile
# Current scripts are optimized for native Ubuntu deployment
```

---

## Post-Deployment

### 1. Access Your Application

Open browser and navigate to:
```
http://119.93.148.180/weatherapp
```

You should see your WeatherAlert application! 🎉

### 2. Create Admin User

```bash
# SSH to server
ssh root@119.93.148.180

# Navigate to app directory
cd /opt/django-apps/weatherapp

# Activate virtual environment
source venv/bin/activate

# Create superuser
python manage.py createsuperuser

# Follow prompts to set:
# - Username
# - Email
# - Password
```

### 3. Access Admin Panel

```
http://119.93.148.180/weatherapp/admin
```

### 4. Configure Application

Edit environment variables if needed:

```bash
nano /opt/django-apps/weatherapp/.env

# After editing, restart:
systemctl restart django-weatherapp
```

---

## Ubuntu Service Management

### Using Management Script (Easy)

```bash
# Show status of all services
weatherapp-manage.sh status

# Restart all services
weatherapp-manage.sh restart

# Stop all services
weatherapp-manage.sh stop

# Start all services
weatherapp-manage.sh start

# View logs
weatherapp-manage.sh logs

# Create backup
weatherapp-manage.sh backup

# Update application
weatherapp-manage.sh update

# Open Django shell
weatherapp-manage.sh shell
```

### Using systemctl (Direct Control)

```bash
# Django/Gunicorn service
systemctl status django-weatherapp
systemctl start django-weatherapp
systemctl stop django-weatherapp
systemctl restart django-weatherapp
systemctl enable django-weatherapp  # Auto-start on boot

# Celery worker
systemctl status celery-weatherapp
systemctl restart celery-weatherapp

# Celery beat (scheduler)
systemctl status celerybeat-weatherapp
systemctl restart celerybeat-weatherapp

# Nginx
systemctl status nginx
systemctl restart nginx
systemctl reload nginx  # Reload config without restart

# Redis
systemctl status redis-server
systemctl restart redis-server

# Check if services are enabled on boot
systemctl is-enabled django-weatherapp
systemctl list-unit-files | grep weather
```

### View Logs

```bash
# Real-time Django logs
tail -f /var/log/django-apps/weatherapp/error.log

# Real-time Celery logs
tail -f /var/log/django-apps/weatherapp/celery.log

# Nginx access logs
tail -f /var/log/django-apps/weatherapp/nginx-access.log

# Nginx error logs
tail -f /var/log/django-apps/weatherapp/nginx-error.log

# System logs (journalctl)
journalctl -u django-weatherapp -f
journalctl -u celery-weatherapp -f
journalctl -u nginx -f

# View last 100 lines
journalctl -u django-weatherapp -n 100

# View logs from today
journalctl -u django-weatherapp --since today

# View logs from specific time
journalctl -u django-weatherapp --since "1 hour ago"
```

---

## Updating Application on Ubuntu

### Quick Update Process

**From Windows:**

```powershell
# Using PowerShell
.\deploy_scripts\windows_deploy.ps1
# Select Option 2 (Quick update)
```

**Or manually:**

```powershell
# Transfer updated files
scp -r weatherapp weatheralert root@119.93.148.180:/tmp/weatherapp_update/
scp deploy_scripts/quick_deploy_to_server.sh root@119.93.148.180:/tmp/

# SSH and update
ssh root@119.93.148.180
chmod +x /tmp/quick_deploy_to_server.sh
/tmp/quick_deploy_to_server.sh
```

### Manual Update on Ubuntu

```bash
# SSH to server
ssh root@119.93.148.180

# Stop services
systemctl stop django-weatherapp celery-weatherapp celerybeat-weatherapp

# Navigate to app directory
cd /opt/django-apps/weatherapp

# Backup current version
cp -r /opt/django-apps/weatherapp /opt/backups/weatherapp/backup_$(date +%Y%m%d_%H%M%S)

# Update code (if using git)
git pull origin main

# Or manually copy new files from /tmp/weatherapp_update/

# Activate virtual environment
source venv/bin/activate

# Update dependencies
pip install -r requirements.txt

# Run migrations
python manage.py migrate

# Collect static files
python manage.py collectstatic --noinput

# Deactivate virtual environment
deactivate

# Fix permissions
chown -R django-weatherapp:django-weatherapp /opt/django-apps/weatherapp

# Start services
systemctl start django-weatherapp celery-weatherapp celerybeat-weatherapp

# Restart Nginx
systemctl restart nginx
```

---

## Ubuntu-Specific Troubleshooting

### Issue: Port 80 Already in Use

```bash
# Check what's using port 80
sudo lsof -i :80
sudo netstat -tlnp | grep :80

# If Apache is installed
systemctl stop apache2
systemctl disable apache2

# Start Nginx
systemctl start nginx
```

### Issue: Python Version Mismatch

```bash
# Check Python version
python3 --version

# If Python 3.8+ not available on Ubuntu 18.04
add-apt-repository ppa:deadsnakes/ppa
apt update
apt install python3.9 python3.9-venv python3.9-dev

# Recreate virtual environment
cd /opt/django-apps/weatherapp
rm -rf venv
python3.9 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### Issue: MySQL Client Not Installing

```bash
# For Ubuntu 20.04+
apt install libmysqlclient-dev pkg-config

# For Ubuntu 22.04
apt install default-libmysqlclient-dev pkg-config

# Then reinstall Python package
source /opt/django-apps/weatherapp/venv/bin/activate
pip install mysqlclient
```

### Issue: Redis Not Starting

```bash
# Check Redis status
systemctl status redis-server

# Check Redis logs
tail -f /var/log/redis/redis-server.log

# Restart Redis
systemctl restart redis-server

# Test Redis
redis-cli ping  # Should return "PONG"
```

### Issue: Nginx Config Test Fails

```bash
# Test Nginx configuration
nginx -t

# Common fixes:
# 1. Check syntax
nano /etc/nginx/sites-available/weatherapp

# 2. Verify symbolic link
ls -l /etc/nginx/sites-enabled/weatherapp

# 3. Remove default site if conflicting
rm /etc/nginx/sites-enabled/default

# 4. Reload Nginx
systemctl reload nginx
```

### Issue: Static Files Not Loading

```bash
# Collect static files
cd /opt/django-apps/weatherapp
source venv/bin/activate
python manage.py collectstatic --noinput

# Check permissions
ls -la /opt/django-apps/weatherapp/staticfiles/

# Fix permissions
chown -R django-weatherapp:django-weatherapp /opt/django-apps/weatherapp/staticfiles/
chmod -R 755 /opt/django-apps/weatherapp/staticfiles/

# Restart Nginx
systemctl restart nginx
```

### Issue: Service Won't Start

```bash
# Check service status
systemctl status django-weatherapp

# View detailed logs
journalctl -u django-weatherapp -n 50 --no-pager

# Common issues:
# 1. Port already in use
netstat -tlnp | grep 8001
# Kill process if needed
kill -9 <PID>

# 2. Permission issues
chown -R django-weatherapp:django-weatherapp /opt/django-apps/weatherapp

# 3. Virtual environment missing
ls -la /opt/django-apps/weatherapp/venv/

# Recreate if needed
cd /opt/django-apps/weatherapp
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### Issue: Database Connection Error

```bash
# Test database connection from Ubuntu
mysql -h 153.92.15.8 -u u520834156_uWApp2024 -p u520834156_dbweatherApp

# Check .env file
cat /opt/django-apps/weatherapp/.env | grep DB

# Test from Django
cd /opt/django-apps/weatherapp
source venv/bin/activate
python manage.py dbshell

# Check if database exists
python manage.py showmigrations
```

### Issue: Out of Memory

```bash
# Check memory usage
free -h
htop

# Check swap
swapon --show

# Add swap if needed (2GB)
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# Restart services
systemctl restart django-weatherapp celery-weatherapp
```

---

## Ubuntu Security Best Practices

### 1. Setup Firewall (UFW)

```bash
# Check current status
ufw status

# Allow required ports
ufw allow 22/tcp   # SSH
ufw allow 80/tcp   # HTTP
ufw allow 443/tcp  # HTTPS

# Deny all other incoming
ufw default deny incoming
ufw default allow outgoing

# Enable firewall
ufw enable

# Check rules
ufw status numbered
```

### 2. Setup Fail2Ban (Brute Force Protection)

```bash
# Install fail2ban
apt install fail2ban -y

# Create local config
cat > /etc/fail2ban/jail.local << 'EOF'
[sshd]
enabled = true
port = 22
maxretry = 3
bantime = 3600

[nginx-limit-req]
enabled = true
port = http,https
logpath = /var/log/nginx/*error.log
maxretry = 10
EOF

# Start fail2ban
systemctl enable fail2ban
systemctl start fail2ban

# Check status
fail2ban-client status
```

### 3. Setup Automatic Updates

```bash
# Install unattended-upgrades
apt install unattended-upgrades -y

# Configure
dpkg-reconfigure -plow unattended-upgrades

# Enable automatic updates
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF
```

### 4. Harden SSH

```bash
# Edit SSH config
nano /etc/ssh/sshd_config

# Recommended settings:
# Port 22
# PermitRootLogin no  # After creating sudo user
# PasswordAuthentication no  # After setting up SSH keys
# PubkeyAuthentication yes
# X11Forwarding no

# Restart SSH
systemctl restart sshd
```

### 5. Setup SSL/HTTPS (Optional but Recommended)

```bash
# Install Certbot
apt install certbot python3-certbot-nginx -y

# Get certificate (requires domain name)
# certbot --nginx -d yourdomain.com

# For IP-only deployment, use self-signed certificate:
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/nginx-selfsigned.key \
  -out /etc/ssl/certs/nginx-selfsigned.crt

# Update Nginx config to use SSL
# See /etc/nginx/sites-available/weatherapp
```

---

## Ubuntu Performance Optimization

### 1. Optimize Gunicorn Workers

```bash
# Calculate optimal workers: (CPU cores × 2) + 1
nproc  # Check CPU cores

# Edit service file
nano /etc/systemd/system/django-weatherapp.service

# Change --workers value
# Example for 2 cores: --workers 5

# Reload and restart
systemctl daemon-reload
systemctl restart django-weatherapp
```

### 2. Optimize Nginx

```bash
# Edit nginx config
nano /etc/nginx/nginx.conf

# Optimize worker processes
worker_processes auto;  # Uses all CPU cores
worker_connections 2048;  # Increase if needed

# Enable file caching
open_file_cache max=200000 inactive=20s;
open_file_cache_valid 30s;
open_file_cache_min_uses 2;
open_file_cache_errors on;

# Test and reload
nginx -t
systemctl reload nginx
```

### 3. Optimize MySQL Connection

```bash
# Edit Django settings
nano /opt/django-apps/weatherapp/weatheralert/settings.py

# Add to DATABASES:
'OPTIONS': {
    'charset': 'utf8mb4',
    'init_command': "SET sql_mode='STRICT_TRANS_TABLES'",
    'connect_timeout': 10,
},
'CONN_MAX_AGE': 600,  # Persistent connections

# Restart
systemctl restart django-weatherapp
```

### 4. Optimize Redis

```bash
# Edit Redis config
nano /etc/redis/redis.conf

# Optimize settings:
maxmemory 256mb
maxmemory-policy allkeys-lru
save 900 1
save 300 10
save 60 10000

# Restart Redis
systemctl restart redis-server
```

---

## Monitoring on Ubuntu

### 1. System Monitoring

```bash
# Real-time system stats
htop

# Disk usage
df -h
du -sh /opt/django-apps/weatherapp/*

# Memory usage
free -h

# Network connections
netstat -tulpn
ss -tulpn

# Process monitoring
ps aux | grep gunicorn
ps aux | grep celery
```

### 2. Application Monitoring

```bash
# Check application logs
tail -f /var/log/django-apps/weatherapp/error.log

# Check monitoring log
tail -f /var/log/django-apps/weatherapp/monitor.log

# Run manual monitoring
/usr/local/bin/monitor-weatherapp.sh

# Check cron jobs
crontab -l
```

### 3. Setup Logrotate

```bash
# Create logrotate config
cat > /etc/logrotate.d/weatherapp << 'EOF'
/var/log/django-apps/weatherapp/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 django-weatherapp django-weatherapp
    sharedscripts
    postrotate
        systemctl reload django-weatherapp > /dev/null 2>&1 || true
    endscript
}
EOF

# Test logrotate
logrotate -d /etc/logrotate.d/weatherapp
```

---

## Backup and Recovery on Ubuntu

### 1. Automated Backup

```bash
# Backup script is already created at:
/usr/local/bin/django-backup.sh

# Manual backup
weatherapp-manage.sh backup

# Backups are stored at:
ls -lh /opt/backups/weatherapp/
```

### 2. Manual Backup

```bash
# Full application backup
tar -czf /opt/backups/weatherapp/manual_backup_$(date +%Y%m%d_%H%M%S).tar.gz \
  -C /opt/django-apps weatherapp

# Database backup (if using local MySQL)
mysqldump -h 153.92.15.8 -u u520834156_uWApp2024 -p \
  u520834156_dbweatherApp > /opt/backups/weatherapp/db_backup_$(date +%Y%m%d_%H%M%S).sql
```

### 3. Restore from Backup

```bash
# Stop services
systemctl stop django-weatherapp celery-weatherapp celerybeat-weatherapp

# Remove current installation
mv /opt/django-apps/weatherapp /opt/django-apps/weatherapp.old

# Extract backup
tar -xzf /opt/backups/weatherapp/backup_YYYYMMDD_HHMMSS.tar.gz \
  -C /opt/django-apps/

# Fix permissions
chown -R django-weatherapp:django-weatherapp /opt/django-apps/weatherapp

# Start services
systemctl start django-weatherapp celery-weatherapp celerybeat-weatherapp
systemctl restart nginx

# Verify
weatherapp-manage.sh status
```

---

## Ubuntu System Maintenance

### Regular Maintenance Tasks

```bash
# Weekly: Update system packages
apt update && apt list --upgradable
apt upgrade -y

# Weekly: Clean package cache
apt autoremove -y
apt autoclean

# Weekly: Check disk space
df -h
du -sh /opt/django-apps/weatherapp/*
du -sh /var/log/django-apps/*

# Monthly: Review logs
find /var/log/django-apps/ -name "*.log" -mtime +30 -ls

# Monthly: Clean old backups
find /opt/backups/weatherapp/ -name "*.tar.gz" -mtime +30 -delete

# Monthly: Check service health
systemctl status django-weatherapp celery-weatherapp nginx redis-server

# Quarterly: Test backup restoration
# (In test environment)
```

### Ubuntu System Information

```bash
# OS version
lsb_release -a
cat /etc/os-release

# Kernel version
uname -r

# System uptime
uptime

# CPU info
lscpu
cat /proc/cpuinfo

# Memory info
free -h
cat /proc/meminfo

# Disk info
lsblk
fdisk -l

# Network info
ip addr
ifconfig
netstat -rn
```

---

## Summary

### Quick Command Reference

```bash
# Deployment
./deploy_to_server.sh              # Full deployment
./quick_deploy_to_server.sh        # Quick update
bash verify_deployment.sh          # Verify deployment

# Management
weatherapp-manage.sh [command]     # All-in-one management
systemctl [action] [service]       # Service control
journalctl -u [service] -f         # View logs

# Monitoring
htop                               # System resources
tail -f /var/log/django-apps/*/log # Application logs
weatherapp-manage.sh status        # Service status

# Maintenance
apt update && apt upgrade          # System updates
weatherapp-manage.sh backup        # Create backup
systemctl restart django-weatherapp # Restart app
```

### Important Paths

```
Application:    /opt/django-apps/weatherapp/
Logs:           /var/log/django-apps/weatherapp/
Backups:        /opt/backups/weatherapp/
Nginx Config:   /etc/nginx/sites-available/weatherapp
Services:       /etc/systemd/system/django-weatherapp.service
Environment:    /opt/django-apps/weatherapp/.env
```

### Access Points

```
Application:    http://119.93.148.180/weatherapp
Admin:          http://119.93.148.180/weatherapp/admin
Health Check:   http://119.93.148.180/weatherapp/health/
```

---

## Your WeatherAlert is Ready for Ubuntu! 🚀

Deploy with confidence knowing you have:
- ✅ Complete automation scripts
- ✅ Ubuntu-optimized configuration
- ✅ Comprehensive monitoring
- ✅ Automated backups
- ✅ Security best practices
- ✅ Easy management tools

**Start deployment now:**
```powershell
.\deploy_scripts\windows_deploy.ps1
```

Good luck! 🎉

