# Weather Application Deployment Guide
## Ubuntu Server with Nginx Reverse Proxy

This guide will help you deploy the weather monitoring application on Ubuntu server (IP: 192.168.3.5) with Nginx reverse proxy to support multiple Python applications accessible via subfolders.

## Prerequisites
- Ubuntu Server 20.04+ with root/sudo access
- Domain or static IP (192.168.3.5)
- Basic knowledge of Linux commands

---

## Step 1: System Preparation and Dependencies

### 1.1 Update System
```bash
sudo apt update && sudo apt upgrade -y
```

### 1.2 Install System Dependencies
```bash
# Essential packages
sudo apt install -y python3 python3-pip python3-venv python3-dev
sudo apt install -y nginx supervisor redis-server
sudo apt install -y mysql-server mysql-client
sudo apt install -y git curl wget unzip
sudo apt install -y build-essential libssl-dev libffi-dev
sudo apt install -y libmysqlclient-dev pkg-config

# For TensorFlow CPU support
sudo apt install -y libhdf5-dev libhdf5-serial-dev
```

### 1.3 Configure MySQL
```bash
sudo mysql_secure_installation
# Follow prompts to set root password and secure installation

# Create database and user
sudo mysql -u root -p
```

```sql
CREATE DATABASE u520834156_dbweatherApp CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'u520834156_uWApp2024'@'localhost' IDENTIFIED BY 'bIxG2Z$In#8';
GRANT ALL PRIVILEGES ON u520834156_dbweatherApp.* TO 'u520834156_uWApp2024'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

---

## Step 2: Application Setup

### 2.1 Create Application Directory Structure
```bash
# Create main applications directory
sudo mkdir -p /var/www/apps
sudo chown -R www-data:www-data /var/www/apps

# Create weather app directory
sudo mkdir -p /var/www/apps/weatherapp
cd /var/www/apps/weatherapp
```

### 2.2 Clone and Setup Application
```bash
# Clone your repository (replace with your actual repo URL)
git clone <your-repository-url> .

# Or if you have the code locally, copy it
# sudo cp -r /path/to/your/weathermonitoring/* /var/www/apps/weatherapp/

# Set proper permissions
sudo chown -R www-data:www-data /var/www/apps/weatherapp
sudo chmod -R 755 /var/www/apps/weatherapp
```

### 2.3 Create Python Virtual Environment
```bash
cd /var/www/apps/weatherapp
sudo python3 -m venv venv
sudo chown -R www-data:www-data venv
sudo chmod -R 755 venv

# Activate virtual environment
source venv/bin/activate

# Upgrade pip
pip install --upgrade pip
```

### 2.4 Install Python Dependencies
```bash
# Install requirements
pip install -r requirements.txt

# Install additional production dependencies
pip install gunicorn psycopg2-binary
```

---

## Step 3: Environment Configuration

### 3.1 Create Environment File
```bash
sudo nano /var/www/apps/weatherapp/.env
```

Add the following content (replace with your actual values):
```env
# Django Settings
SECRET_KEY=your-super-secret-key-here
DEBUG=False
ALLOWED_HOSTS=192.168.3.5,localhost,127.0.0.1

# Database Configuration
DATABASE_URL=mysql://u520834156_uWApp2024:bIxG2Z$In#8@localhost:3306/u520834156_dbweatherApp

# Email Configuration
EMAIL_HOST=smtp.gmail.com
EMAIL_PORT=587
EMAIL_USE_TLS=True
EMAIL_HOST_USER=your-email@gmail.com
EMAIL_HOST_PASSWORD=your-app-password

# Redis Configuration
REDIS_URL=redis://localhost:6379/0

# Weather API Configuration
OPENWEATHERMAP_API_KEY=your-openweathermap-api-key
LATITUDE=10.5283
LONGITUDE=122.8338

# SMS Configuration
SMS_API_URL=https://sms.pagenet.info/api/v1/sms/send
SMS_API_KEY=your-sms-api-key
SMS_DEVICE_ID=your-device-id

# PhilSys QR Verification (if needed)
PSA_PUBLIC_KEY=your-psa-public-key
PSA_ED25519_PUBLIC_KEY=your-psa-ed25519-public-key
```

### 3.2 Update Django Settings for Subfolder Deployment
```bash
sudo nano /var/www/apps/weatherapp/weatheralert/settings.py
```

Add these lines after the existing settings:
```python
# Subfolder deployment settings
FORCE_SCRIPT_NAME = '/weatherapp'
USE_X_FORWARDED_HOST = True
SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')

# Static files configuration for subfolder
STATIC_URL = '/weatherapp/static/'
STATIC_ROOT = '/var/www/apps/weatherapp/staticfiles'

# Media files configuration for subfolder
MEDIA_URL = '/weatherapp/media/'
MEDIA_ROOT = '/var/www/apps/weatherapp/media'
```

### 3.3 Update URL Configuration
```bash
sudo nano /var/www/apps/weatherapp/weatheralert/urls.py
```

Update the main urls.py:
```python
from django.contrib import admin
from django.urls import path, include
from django.conf import settings
from django.conf.urls.static import static

urlpatterns = [
    path('admin/', admin.site.urls),
    path('', include('weatherapp.urls')),
]

# Serve static and media files in development
if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
    urlpatterns += static(settings.STATIC_URL, document_root=settings.STATIC_ROOT)
```

---

## Step 4: Database Setup

### 4.1 Run Django Migrations
```bash
cd /var/www/apps/weatherapp
source venv/bin/activate

# Set Django settings module
export DJANGO_SETTINGS_MODULE=weatheralert.settings

# Run migrations
python manage.py makemigrations
python manage.py migrate

# Create superuser
python manage.py createsuperuser

# Collect static files
python manage.py collectstatic --noinput
```

---

## Step 5: Nginx Configuration

### 5.1 Create Nginx Configuration for Weather App
```bash
sudo nano /etc/nginx/sites-available/weatherapp
```

Add the following configuration:
```nginx
# Upstream for weather app
upstream weatherapp {
    server 127.0.0.1:8001;
}

# Main server block
server {
    listen 80;
    server_name 192.168.3.5;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;

    # Weather app location
    location /weatherapp/ {
        proxy_pass http://weatherapp/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Handle static files
        location /weatherapp/static/ {
            alias /var/www/apps/weatherapp/staticfiles/;
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
        
        # Handle media files
        location /weatherapp/media/ {
            alias /var/www/apps/weatherapp/media/;
            expires 1y;
            add_header Cache-Control "public";
        }
    }

    # Default location for other apps
    location / {
        return 200 'Welcome to Multi-App Server';
        add_header Content-Type text/plain;
    }

    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
```

### 5.2 Enable the Site
```bash
# Enable the site
sudo ln -s /etc/nginx/sites-available/weatherapp /etc/nginx/sites-enabled/

# Test nginx configuration
sudo nginx -t

# Reload nginx
sudo systemctl reload nginx
sudo systemctl enable nginx
```

---

## Step 6: Gunicorn Configuration

### 6.1 Create Gunicorn Configuration
```bash
sudo nano /var/www/apps/weatherapp/gunicorn.conf.py
```

Add the following configuration:
```python
# Gunicorn configuration file
import multiprocessing

bind = "127.0.0.1:8001"
workers = multiprocessing.cpu_count() * 2 + 1
worker_class = "sync"
worker_connections = 1000
max_requests = 1000
max_requests_jitter = 100
timeout = 30
keepalive = 2

# Logging
accesslog = "/var/log/weatherapp/access.log"
errorlog = "/var/log/weatherapp/error.log"
loglevel = "info"

# Process naming
proc_name = "weatherapp"

# Server mechanics
daemon = False
pidfile = "/var/run/weatherapp.pid"
user = "www-data"
group = "www-data"
tmp_upload_dir = None

# SSL (if needed)
# keyfile = "/path/to/keyfile"
# certfile = "/path/to/certfile"
```

### 6.2 Create Log Directory
```bash
sudo mkdir -p /var/log/weatherapp
sudo chown -R www-data:www-data /var/log/weatherapp
```

---

## Step 7: Supervisor Configuration

### 7.1 Create Supervisor Configuration for Weather App
```bash
sudo nano /etc/supervisor/conf.d/weatherapp.conf
```

Add the following configuration:
```ini
[program:weatherapp]
command=/var/www/apps/weatherapp/venv/bin/gunicorn --config /var/www/apps/weatherapp/gunicorn.conf.py weatheralert.wsgi:application
directory=/var/www/apps/weatherapp
user=www-data
group=www-data
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/weatherapp/gunicorn.log
environment=DJANGO_SETTINGS_MODULE="weatheralert.settings"

[program:weatherapp-celery-worker]
command=/var/www/apps/weatherapp/venv/bin/celery -A weatheralert worker --loglevel=info
directory=/var/www/apps/weatherapp
user=www-data
group=www-data
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/weatherapp/celery-worker.log
environment=DJANGO_SETTINGS_MODULE="weatheralert.settings"

[program:weatherapp-celery-beat]
command=/var/www/apps/weatherapp/venv/bin/celery -A weatheralert beat --loglevel=info
directory=/var/www/apps/weatherapp
user=www-data
group=www-data
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/weatherapp/celery-beat.log
environment=DJANGO_SETTINGS_MODULE="weatheralert.settings"
```

### 7.2 Update Supervisor and Start Services
```bash
# Update supervisor configuration
sudo supervisorctl reread
sudo supervisorctl update

# Start weather app services
sudo supervisorctl start weatherapp
sudo supervisorctl start weatherapp-celery-worker
sudo supervisorctl start weatherapp-celery-beat

# Check status
sudo supervisorctl status
```

---

## Step 8: Redis Configuration

### 8.1 Configure Redis
```bash
sudo nano /etc/redis/redis.conf
```

Update the following settings:
```conf
# Bind to localhost only for security
bind 127.0.0.1

# Set a password (optional but recommended)
# requirepass your-redis-password

# Configure persistence
save 900 1
save 300 10
save 60 10000
```

### 8.2 Start Redis
```bash
sudo systemctl start redis-server
sudo systemctl enable redis-server
```

---

## Step 9: Firewall Configuration

### 9.1 Configure UFW Firewall
```bash
# Enable UFW
sudo ufw enable

# Allow SSH
sudo ufw allow ssh

# Allow HTTP and HTTPS
sudo ufw allow 80
sudo ufw allow 443

# Allow MySQL (if needed from external)
sudo ufw allow 3306

# Check status
sudo ufw status
```

---

## Step 10: Testing and Verification

### 10.1 Test Application
```bash
# Check if services are running
sudo supervisorctl status
sudo systemctl status nginx
sudo systemctl status redis-server

# Test application locally
curl http://192.168.3.5/weatherapp/
curl http://192.168.3.5/health
```

### 10.2 Check Logs
```bash
# Check application logs
sudo tail -f /var/log/weatherapp/gunicorn.log
sudo tail -f /var/log/weatherapp/celery-worker.log
sudo tail -f /var/log/weatherapp/celery-beat.log

# Check nginx logs
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

---

## Step 11: Adding Additional Python Applications

### 11.1 Directory Structure for Multiple Apps
```
/var/www/apps/
├── weatherapp/          # Weather application
├── app2/               # Second application
├── app3/               # Third application
└── shared/             # Shared resources
```

### 11.2 Nginx Configuration for Multiple Apps
```bash
sudo nano /etc/nginx/sites-available/multi-apps
```

```nginx
# Upstream definitions
upstream weatherapp {
    server 127.0.0.1:8001;
}

upstream app2 {
    server 127.0.0.1:8002;
}

upstream app3 {
    server 127.0.0.1:8003;
}

server {
    listen 80;
    server_name 192.168.3.5;

    # Weather app
    location /weatherapp/ {
        proxy_pass http://weatherapp/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Second app
    location /app2/ {
        proxy_pass http://app2/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Third app
    location /app3/ {
        proxy_pass http://app3/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Default location
    location / {
        return 200 'Multi-App Server - Available apps: /weatherapp/, /app2/, /app3/';
        add_header Content-Type text/plain;
    }
}
```

---

## Step 12: Monitoring and Maintenance

### 12.1 Create Monitoring Script
```bash
sudo nano /usr/local/bin/check-apps.sh
```

```bash
#!/bin/bash
# Application health check script

echo "=== Application Status Check ==="
echo "Date: $(date)"
echo

# Check supervisor status
echo "Supervisor Status:"
sudo supervisorctl status
echo

# Check nginx status
echo "Nginx Status:"
sudo systemctl is-active nginx
echo

# Check redis status
echo "Redis Status:"
sudo systemctl is-active redis-server
echo

# Check application endpoints
echo "Application Endpoints:"
curl -s -o /dev/null -w "Weather App: %{http_code}\n" http://192.168.3.5/weatherapp/
curl -s -o /dev/null -w "Health Check: %{http_code}\n" http://192.168.3.5/health
echo

# Check disk space
echo "Disk Usage:"
df -h /var/www/apps/
echo

# Check memory usage
echo "Memory Usage:"
free -h
echo
```

```bash
sudo chmod +x /usr/local/bin/check-apps.sh
```

### 12.2 Create Log Rotation Configuration
```bash
sudo nano /etc/logrotate.d/weatherapp
```

```
/var/log/weatherapp/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 www-data www-data
    postrotate
        sudo supervisorctl restart weatherapp
    endscript
}
```

---

## Step 13: Security Hardening

### 13.1 Create Security Script
```bash
sudo nano /usr/local/bin/secure-server.sh
```

```bash
#!/bin/bash
# Security hardening script

echo "=== Security Hardening ==="

# Update system
sudo apt update && sudo apt upgrade -y

# Install fail2ban
sudo apt install -y fail2ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# Configure fail2ban for nginx
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sudo systemctl restart fail2ban

# Set up automatic security updates
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades

# Configure firewall
sudo ufw --force enable
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80
sudo ufw allow 443

echo "Security hardening completed!"
```

```bash
sudo chmod +x /usr/local/bin/secure-server.sh
```

---

## Troubleshooting

### Common Issues and Solutions

1. **Application not accessible via subfolder**
   - Check nginx configuration
   - Verify proxy_pass URL has trailing slash
   - Check Django FORCE_SCRIPT_NAME setting

2. **Static files not loading**
   - Run `python manage.py collectstatic`
   - Check nginx static file location configuration
   - Verify file permissions

3. **Database connection issues**
   - Check MySQL service status
   - Verify database credentials
   - Check firewall settings

4. **Celery tasks not running**
   - Check Redis service status
   - Verify Celery worker is running
   - Check task configuration in settings

5. **Permission issues**
   - Check file ownership (www-data:www-data)
   - Verify directory permissions (755)
   - Check log file permissions

### Useful Commands

```bash
# Restart all services
sudo supervisorctl restart all
sudo systemctl restart nginx

# Check service status
sudo supervisorctl status
sudo systemctl status nginx redis-server mysql

# View logs
sudo tail -f /var/log/weatherapp/gunicorn.log
sudo tail -f /var/log/nginx/error.log

# Test configuration
sudo nginx -t
sudo supervisorctl reread
```

---

## Conclusion

Your weather application should now be accessible at `http://192.168.3.5/weatherapp/` with the ability to add more Python applications on different subfolders. The setup includes:

- ✅ Nginx reverse proxy for subfolder routing
- ✅ Gunicorn WSGI server
- ✅ Celery task queue with Redis
- ✅ MySQL database
- ✅ Supervisor for process management
- ✅ Security hardening
- ✅ Monitoring and logging
- ✅ Support for multiple applications

Remember to:
- Keep your system updated
- Monitor logs regularly
- Backup your database
- Use strong passwords and environment variables
- Test your application thoroughly

For additional applications, follow the same pattern but use different ports (8002, 8003, etc.) and update the nginx configuration accordingly.
