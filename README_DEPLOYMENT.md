# Weather Application Deployment Guide

This repository contains a comprehensive deployment solution for the weather monitoring application on Ubuntu server with support for multiple Python applications via subfolder routing.

## 🚀 Quick Start

### Prerequisites
- Ubuntu Server 20.04+ with root/sudo access
- Static IP address (192.168.3.5 in this example)
- Basic knowledge of Linux commands

### One-Command Deployment
```bash
# Clone or copy the project to your Ubuntu server
git clone <your-repository-url>
cd weathermonitoring

# Make scripts executable
chmod +x deploy_scripts/*.sh

# Run quick deployment
./deploy_scripts/quick_deploy.sh
```

## 📁 Project Structure

```
weathermonitoring/
├── deploy_scripts/           # Deployment automation scripts
│   ├── setup_environment.sh  # System setup and dependencies
│   ├── deploy_app.sh         # Application deployment
│   ├── add_new_app.sh        # Add additional Python apps
│   ├── monitor_apps.sh       # Monitoring and health checks
│   ├── quick_deploy.sh       # Complete deployment in one command
│   └── make_executable.bat   # Windows helper script
├── deployment_guide.md       # Detailed step-by-step guide
├── README_DEPLOYMENT.md      # This file
└── [your application code]
```

## 🛠️ Manual Deployment Steps

If you prefer manual deployment, follow these steps:

### Step 1: System Setup
```bash
./deploy_scripts/setup_environment.sh
```

### Step 2: Deploy Application
```bash
./deploy_scripts/deploy_app.sh
```

### Step 3: Verify Deployment
```bash
./deploy_scripts/monitor_apps.sh
```

## 🌐 Access Points

After deployment, your applications will be accessible at:

- **Weather App**: `http://192.168.3.5/weatherapp/`
- **Health Check**: `http://192.168.3.5/health`
- **Admin Panel**: `http://192.168.3.5/weatherapp/admin/`

## 🔧 Adding More Applications

To add additional Python applications to the same server:

```bash
./deploy_scripts/add_new_app.sh <app_name> <port> <app_path>
```

Example:
```bash
./deploy_scripts/add_new_app.sh myapp 8002 /path/to/myapp
```

This will make the app accessible at `http://192.168.3.5/myapp/`

## 📊 Monitoring

### Check Application Status
```bash
./deploy_scripts/monitor_apps.sh
```

### View Logs
```bash
# All applications
./deploy_scripts/monitor_apps.sh logs weatherapp

# Specific application
sudo tail -f /var/log/weatherapp/gunicorn.log
```

### Service Management
```bash
# Check status
sudo supervisorctl status

# Restart application
sudo supervisorctl restart weatherapp

# Restart all services
sudo supervisorctl restart all
```

## 🔒 Security Configuration

### Environment Variables
Update `/var/www/apps/weatherapp/.env` with your actual values:

```env
SECRET_KEY=your-super-secret-key-here
DEBUG=False
ALLOWED_HOSTS=192.168.3.5,localhost,127.0.0.1
DATABASE_URL=mysql://user:password@localhost:3306/database
EMAIL_HOST_USER=your-email@gmail.com
EMAIL_HOST_PASSWORD=your-app-password
OPENWEATHERMAP_API_KEY=your-api-key
```

### Firewall Configuration
```bash
sudo ufw enable
sudo ufw allow ssh
sudo ufw allow 80
sudo ufw allow 443
```

## 🗄️ Database Management

### Create Superuser
```bash
sudo -u www-data /var/www/apps/weatherapp/venv/bin/python /var/www/apps/weatherapp/manage.py createsuperuser
```

### Run Migrations
```bash
sudo -u www-data /var/www/apps/weatherapp/venv/bin/python /var/www/apps/weatherapp/manage.py migrate
```

### Backup Database
```bash
mysqldump -u u520834156_uWApp2024 -p u520834156_dbweatherApp > backup_$(date +%Y%m%d_%H%M%S).sql
```

## 🔄 Updates and Maintenance

### Update Application
```bash
cd /var/www/apps/weatherapp
git pull origin main
sudo -u www-data /var/www/apps/weatherapp/venv/bin/pip install -r requirements.txt
sudo -u www-data /var/www/apps/weatherapp/venv/bin/python manage.py migrate
sudo -u www-data /var/www/apps/weatherapp/venv/bin/python manage.py collectstatic --noinput
sudo supervisorctl restart weatherapp
```

### System Updates
```bash
sudo apt update && sudo apt upgrade -y
sudo supervisorctl restart all
```

## 🐛 Troubleshooting

### Common Issues

1. **Application not accessible**
   ```bash
   # Check nginx status
   sudo systemctl status nginx
   sudo nginx -t
   
   # Check application status
   sudo supervisorctl status
   ```

2. **Database connection issues**
   ```bash
   # Check MySQL status
   sudo systemctl status mysql
   
   # Test connection
   mysql -u u520834156_uWApp2024 -p u520834156_dbweatherApp
   ```

3. **Static files not loading**
   ```bash
   # Collect static files
   sudo -u www-data /var/www/apps/weatherapp/venv/bin/python manage.py collectstatic --noinput
   
   # Check nginx static file configuration
   sudo nginx -t
   ```

4. **Permission issues**
   ```bash
   # Fix permissions
   sudo chown -R www-data:www-data /var/www/apps/weatherapp
   sudo chmod -R 755 /var/www/apps/weatherapp
   ```

### Log Files
- **Application logs**: `/var/log/weatherapp/`
- **Nginx logs**: `/var/log/nginx/`
- **System logs**: `/var/log/syslog`

## 📋 Architecture Overview

```
Internet → Nginx (Port 80) → Gunicorn (Port 8001) → Django App
                              ↓
                         Celery Worker → Redis → MySQL
```

### Components
- **Nginx**: Reverse proxy and static file serving
- **Gunicorn**: WSGI server for Django application
- **Celery**: Task queue for background jobs
- **Redis**: Message broker for Celery
- **MySQL**: Database for application data
- **Supervisor**: Process management

## 🔧 Configuration Files

### Nginx Configuration
- Location: `/etc/nginx/sites-available/weatherapp`
- Handles subfolder routing and static files

### Supervisor Configuration
- Location: `/etc/supervisor/conf.d/weatherapp.conf`
- Manages Gunicorn and Celery processes

### Application Configuration
- Location: `/var/www/apps/weatherapp/.env`
- Environment variables and secrets

## 📞 Support

If you encounter issues:

1. Check the logs: `./deploy_scripts/monitor_apps.sh`
2. Verify all services are running: `sudo supervisorctl status`
3. Test endpoints: `curl http://192.168.3.5/health`
4. Check nginx configuration: `sudo nginx -t`

## 🎯 Next Steps

After successful deployment:

1. **Configure SSL**: Set up Let's Encrypt certificates
2. **Set up monitoring**: Configure log rotation and alerts
3. **Backup strategy**: Implement automated database backups
4. **Security hardening**: Regular security updates and audits
5. **Performance tuning**: Optimize based on usage patterns

## 📝 Notes

- The application is configured to run on subfolder `/weatherapp/`
- Multiple applications can be added using the same pattern
- All scripts include error handling and colored output
- The deployment is production-ready with security considerations
- Regular monitoring and maintenance are recommended

---

**Happy Deploying! 🚀**
