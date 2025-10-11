# Django Multi-Application Deployment Scripts for Ubuntu Server

This comprehensive deployment solution provides automated setup and management for multiple Django applications on Ubuntu Server (IP: 192.168.3.5). The system supports isolated deployment of **WeatherAlert**, **IRMSS**, and **FireGuard** applications with proper routing and no conflicts.

## 🚀 Quick Start

### 1. Initial Server Setup
```bash
# Make scripts executable
chmod +x deploy_scripts/*.sh

# Run the main deployment script
sudo ./deploy_scripts/ubuntu_multi_app_deploy.sh
```

### 2. Database Setup
```bash
# Setup MySQL databases for all applications
sudo ./deploy_scripts/setup_databases.sh
```

### 3. Deploy WeatherAlert Application
```bash
# Deploy WeatherAlert to production
sudo ./deploy_scripts/deploy_weatherapp.sh
```

### 4. Access Applications
- **WeatherAlert**: http://192.168.3.5/bccweatherapp
- **IRMSS**: http://192.168.3.5/irrms  
- **FireGuard**: http://192.168.3.5/fireguard
- **Monitoring Dashboard**: http://192.168.3.5/monitoring.html

## 📁 Script Overview

### Core Deployment Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `ubuntu_multi_app_deploy.sh` | Main server setup with multi-app support | `sudo ./ubuntu_multi_app_deploy.sh` |
| `deploy_weatherapp.sh` | Deploy WeatherAlert application | `sudo ./deploy_weatherapp.sh` |
| `setup_databases.sh` | Setup MySQL databases for all apps | `sudo ./setup_databases.sh` |
| `nginx_multi_app.conf` | Nginx configuration for multiple apps | Applied automatically |

### Configuration & Management Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `setup_ssl.sh` | SSL certificate automation | `sudo ./setup_ssl.sh` |
| `setup_monitoring.sh` | Monitoring and backup setup | `sudo ./setup_monitoring.sh` |
| `create_env_templates.sh` | Environment configuration templates | `sudo ./create_env_templates.sh` |
| `create_app_manager.sh` | Application management scripts | `sudo ./create_app_manager.sh` |

## 🏗️ Architecture Overview

### Application Isolation
Each Django application runs in complete isolation:

- **Separate Virtual Environments**: `/opt/django-apps/{app}/venv/`
- **Isolated Databases**: `{app}_db` with dedicated users
- **Unique Ports**: 8001 (weatherapp), 8002 (irmss), 8003 (fireguard)
- **Independent Services**: `django-{app}`, `celery-{app}`, `celerybeat-{app}`
- **Separate Logs**: `/var/log/django-apps/{app}/`

### URL Routing
- `192.168.3.5/bccweatherapp/` → WeatherAlert (Port 8001)
- `192.168.3.5/irrms/` → IRMSS (Port 8002)
- `192.168.3.5/fireguard/` → FireGuard (Port 8003)

### Database Structure
```
weatherapp_db    → WeatherAlert application
irmss_db         → IRMSS application  
fireguard_db     → FireGuard application
```

## 🛠️ Management Commands

### Application Management
```bash
# Show status of all applications
django-manager.sh status

# Start/stop/restart specific application
django-manager.sh start weatherapp
django-manager.sh stop irmss
django-manager.sh restart fireguard

# Show logs for application
django-manager.sh logs weatherapp

# Health check
django-manager.sh health weatherapp

# Deploy application with environment
django-manager.sh deploy weatherapp production
```

### Quick Commands
```bash
# Start all applications
start-all-apps.sh

# Stop all applications  
stop-all-apps.sh

# Restart all applications
restart-all-apps.sh

# Check status of all applications
check-all-apps.sh

# Health check all applications
health-check-all.sh
```

### Service Aliases
```bash
# Django management aliases
django-status    # Show all app status
django-start     # Start all apps
django-stop      # Stop all apps
django-restart   # Restart all apps
django-logs      # Show logs
django-health    # Health check
django-monitor   # Open monitoring dashboard

# App-specific aliases
weather-status   # WeatherAlert status
weather-start    # Start WeatherAlert
weather-stop     # Stop WeatherAlert
weather-restart  # Restart WeatherAlert
weather-logs     # WeatherAlert logs

irmss-status     # IRMSS status
irmss-start      # Start IRMSS
irmss-stop       # Stop IRMSS
irmss-restart    # Restart IRMSS
irmss-logs       # IRMSS logs

fireguard-status # FireGuard status
fireguard-start  # Start FireGuard
fireguard-stop   # Stop FireGuard
fireguard-restart # Restart FireGuard
fireguard-logs   # FireGuard logs
```

## 🔧 Configuration Management

### Environment Templates
Environment templates are created in `/opt/django-apps/env-templates/`:

```
env-templates/
├── production/
│   ├── weatherapp.env
│   ├── irmss.env
│   └── fireguard.env
├── development/
│   ├── weatherapp.env
│   ├── irmss.env
│   └── fireguard.env
└── staging/
    ├── weatherapp.env
    ├── irmss.env
    └── fireguard.env
```

### Deploy Environment Configuration
```bash
# Deploy production environment for WeatherAlert
deploy-app.sh weatherapp production

# Deploy development environment for IRMSS
deploy-app.sh irmss development

# Deploy staging environment for FireGuard
deploy-app.sh fireguard staging
```

### Environment Management
```bash
# List all available templates
env-manager.sh list

# Show environment configuration
env-manager.sh show weatherapp production

# Deploy environment configuration
env-manager.sh deploy weatherapp production

# Backup current environment
env-manager.sh backup weatherapp

# Validate environment configuration
env-manager.sh validate weatherapp production
```

## 📊 Monitoring & Backup

### Monitoring Features
- **System Resource Monitoring**: CPU, Memory, Disk, Load Average
- **Application Health Monitoring**: Service status, HTTP health checks
- **Database Monitoring**: Connection status, performance metrics
- **Log Analysis**: Error detection and alerting
- **Web Dashboard**: http://192.168.3.5/monitoring.html

### Backup Features
- **Automated Daily Backups**: Application files, databases, logs
- **Retention Management**: Configurable retention periods
- **Incremental Backups**: Efficient storage usage
- **Restore Capabilities**: Easy application restoration

### Monitoring Commands
```bash
# System monitoring
system-monitor.sh

# Application monitoring
app-monitor.sh

# Database monitoring
monitor-databases.sh

# SSL certificate monitoring
monitor-ssl.sh
```

### Backup Commands
```bash
# Create backup for all applications
backup-all.sh

# Restore application from backup
restore-app.sh weatherapp weatherapp_20240101_120000.tar.gz

# Database backup
backup-databases.sh

# Database restore
restore-database.sh weatherapp weatherapp_20240101_120000.sql.gz
```

## 🔐 Security Features

### SSL/TLS Support
- **Let's Encrypt Integration**: Automatic certificate management
- **Self-Signed Certificates**: For local development
- **Certificate Monitoring**: Expiration alerts and auto-renewal
- **Security Headers**: XSS protection, content type sniffing prevention

### Security Commands
```bash
# SSL certificate management
ssl-manager.sh status
ssl-manager.sh renew
ssl-manager.sh list
ssl-manager.sh test

# Setup SSL certificates
setup_ssl.sh
```

### Database Security
- **Isolated Databases**: Each app has its own database
- **Secure Credentials**: Encrypted password storage
- **Access Control**: App-specific database users
- **Backup Encryption**: Secure backup storage

## 🗄️ Database Management

### Database Commands
```bash
# Database status
db-manager.sh status

# Database backup
db-manager.sh backup

# Database optimization
db-manager.sh optimize

# Database repair
db-manager.sh repair

# Database information
db-manager.sh info
```

### Database Configuration
Each application has its own database configuration:
- **weatherapp**: `weatherapp_db` with user `weatherapp_user`
- **irmss**: `irmss_db` with user `irmss_user`  
- **fireguard**: `fireguard_db` with user `fireguard_user`

## 📝 Logging & Troubleshooting

### Log Locations
```
/var/log/django-apps/
├── weatherapp/
│   ├── django.log
│   ├── access.log
│   ├── error.log
│   ├── celery.log
│   └── celerybeat.log
├── irmss/
│   └── (same structure)
├── fireguard/
│   └── (same structure)
└── system-monitor.log
```

### Troubleshooting Commands
```bash
# View application logs
django-manager.sh logs weatherapp

# Check service status
systemctl status django-weatherapp
systemctl status celery-weatherapp
systemctl status celerybeat-weatherapp

# Check nginx status
systemctl status nginx
nginx -t

# Check database connections
db-manager.sh status weatherapp

# Check SSL certificates
ssl-manager.sh status
```

## 🚀 Deployment Workflow

### 1. Initial Server Setup
```bash
# Run main deployment script
sudo ./ubuntu_multi_app_deploy.sh

# Setup databases
sudo ./setup_databases.sh

# Setup monitoring
sudo ./setup_monitoring.sh

# Create environment templates
sudo ./create_env_templates.sh

# Create app management scripts
sudo ./create_app_manager.sh
```

### 2. Deploy WeatherAlert
```bash
# Deploy WeatherAlert application
sudo ./deploy_weatherapp.sh

# Deploy environment configuration
sudo deploy-app.sh weatherapp production

# Start the application
sudo django-manager.sh start weatherapp
```

### 3. Deploy Additional Applications
```bash
# For IRMSS
sudo django-manager.sh deploy irmss production
sudo django-manager.sh start irmss

# For FireGuard  
sudo django-manager.sh deploy fireguard production
sudo django-manager.sh start fireguard
```

### 4. SSL Setup (Optional)
```bash
# Setup SSL certificates
sudo ./setup_ssl.sh

# Obtain certificate for domain
sudo certbot certonly --webroot -w /var/www/html -d yourdomain.com
```

## 📋 Maintenance Tasks

### Daily Maintenance
```bash
# Check application status
django-manager.sh status

# Health check all applications
django-manager.sh health

# Check system resources
system-monitor.sh

# Review logs for errors
django-manager.sh logs weatherapp
```

### Weekly Maintenance
```bash
# Database optimization
db-manager.sh optimize

# Log cleanup (automatic)
# Backup verification
backup-all.sh

# SSL certificate check
ssl-manager.sh status
```

### Monthly Maintenance
```bash
# Update application code
django-manager.sh update weatherapp

# Database maintenance
db-manager.sh repair

# Security updates
apt update && apt upgrade
```

## 🆘 Emergency Procedures

### Application Recovery
```bash
# Stop all applications
django-manager.sh stop

# Restore from backup
restore-app.sh weatherapp weatherapp_backup.tar.gz

# Start applications
django-manager.sh start
```

### Database Recovery
```bash
# Restore database
restore-database.sh weatherapp weatherapp_db_backup.sql

# Verify database
db-manager.sh status weatherapp
```

### Service Recovery
```bash
# Restart all services
systemctl restart nginx
systemctl restart mysql
systemctl restart redis-server

# Restart applications
django-manager.sh restart
```

## 📞 Support & Documentation

### Key Files
- **Main Configuration**: `/etc/django-apps/`
- **Application Code**: `/opt/django-apps/`
- **Logs**: `/var/log/django-apps/`
- **Backups**: `/opt/backups/`
- **SSL Certificates**: `/etc/letsencrypt/`

### Useful Commands
```bash
# Show all available commands
django-manager.sh help

# Show environment templates
env-manager.sh list

# Show database status
db-manager.sh status

# Show SSL status
ssl-manager.sh status

# Show monitoring dashboard
django-manager.sh monitor
```

### Application URLs
- **WeatherAlert**: http://192.168.3.5/bccweatherapp
- **IRMSS**: http://192.168.3.5/irrms
- **FireGuard**: http://192.168.3.5/fireguard
- **Monitoring**: http://192.168.3.5/monitoring.html

This comprehensive deployment solution provides enterprise-grade management for multiple Django applications with complete isolation, monitoring, backup, and security features.
