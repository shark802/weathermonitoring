# WeatherAlert Server Deployment Guide

## Server Configuration
- **Server IP**: `119.93.148.180`
- **Application URL**: `http://119.93.148.180/weatherapp`
- **Deployment Path**: `/opt/django-apps/weatherapp`

## Prerequisites

### Server Requirements
- Ubuntu 20.04 LTS or newer
- Root or sudo access
- Minimum 2GB RAM
- Minimum 20GB disk space
- Python 3.8 or newer
- Internet connection

### Network Requirements
- Port 80 (HTTP) open
- Port 443 (HTTPS) open if using SSL
- Port 22 (SSH) for deployment

## Deployment Steps

### 1. Initial Full Deployment

For the first-time deployment or complete setup:

```bash
# On your local machine, navigate to the project directory
cd /path/to/weatherapp

# Copy deployment script to server
scp deploy_scripts/deploy_to_server.sh root@119.93.148.180:/tmp/

# SSH into the server
ssh root@119.93.148.180

# Run the deployment script
cd /tmp
chmod +x deploy_to_server.sh
./deploy_to_server.sh
```

The script will:
1. Update system packages
2. Install all dependencies (Python, Nginx, Redis, etc.)
3. Create directory structure
4. Setup Python virtual environment
5. Configure environment variables
6. Copy application files
7. Run database migrations
8. Setup systemd services
9. Configure Nginx
10. Start all services
11. Setup monitoring

### 2. Quick Update/Redeploy

For updating an existing deployment with code changes:

```bash
# On your local machine
cd /path/to/weatherapp

# Copy quick deploy script to server
scp deploy_scripts/quick_deploy_to_server.sh root@119.93.148.180:/tmp/

# Copy updated application files
scp -r weatherapp weatheralert manage.py requirements.txt root@119.93.148.180:/tmp/deploy_files/

# SSH into server and run quick deploy
ssh root@119.93.148.180
cd /tmp
chmod +x quick_deploy_to_server.sh
./quick_deploy_to_server.sh
```

### 3. Alternative: Deploy from Project Directory

If you want to deploy directly from your development machine:

```bash
# On your local machine, in the project directory
cd /path/to/weatherapp

# Make scripts executable
chmod +x deploy_scripts/deploy_to_server.sh

# Transfer entire project to server
scp -r . root@119.93.148.180:/tmp/weatherapp/

# SSH and deploy
ssh root@119.93.148.180
cd /tmp/weatherapp
./deploy_scripts/deploy_to_server.sh
```

## Post-Deployment

### Accessing the Application

Once deployed, access your application at:
```
http://119.93.148.180/weatherapp
```

### Service Management

Use the provided management script:

```bash
# Check status
weatherapp-manage.sh status

# Restart services
weatherapp-manage.sh restart

# View logs
weatherapp-manage.sh logs

# Update application
weatherapp-manage.sh update

# Create backup
weatherapp-manage.sh backup

# Open Django shell
weatherapp-manage.sh shell
```

### Manual Service Control

```bash
# Django service
systemctl status django-weatherapp
systemctl restart django-weatherapp
systemctl stop django-weatherapp
systemctl start django-weatherapp

# Celery worker
systemctl status celery-weatherapp
systemctl restart celery-weatherapp

# Celery beat (scheduler)
systemctl status celerybeat-weatherapp
systemctl restart celerybeat-weatherapp

# Nginx
systemctl status nginx
systemctl restart nginx

# Redis
systemctl status redis-server
systemctl restart redis-server
```

### View Logs

```bash
# Django application logs
tail -f /var/log/django-apps/weatherapp/error.log
tail -f /var/log/django-apps/weatherapp/access.log

# Celery logs
tail -f /var/log/django-apps/weatherapp/celery.log
tail -f /var/log/django-apps/weatherapp/celerybeat.log

# Nginx logs
tail -f /var/log/django-apps/weatherapp/nginx-error.log
tail -f /var/log/django-apps/weatherapp/nginx-access.log

# System logs
journalctl -u django-weatherapp -f
journalctl -u celery-weatherapp -f
```

## Configuration Files

### Key Configuration Locations

- **Application**: `/opt/django-apps/weatherapp/`
- **Environment Config**: `/opt/django-apps/weatherapp/.env`
- **Logs**: `/var/log/django-apps/weatherapp/`
- **Backups**: `/opt/backups/weatherapp/`
- **Nginx Config**: `/etc/nginx/sites-available/weatherapp`
- **Systemd Services**: `/etc/systemd/system/django-weatherapp.service`

### Environment Variables

Edit `.env` file to configure:

```bash
nano /opt/django-apps/weatherapp/.env
```

After editing, restart services:
```bash
systemctl restart django-weatherapp
```

## Troubleshooting

### Application Not Accessible

1. Check if services are running:
```bash
weatherapp-manage.sh status
```

2. Check Nginx configuration:
```bash
nginx -t
systemctl status nginx
```

3. Check application logs:
```bash
tail -f /var/log/django-apps/weatherapp/error.log
```

### Database Connection Issues

1. Verify database credentials in `.env` file
2. Test database connection:
```bash
cd /opt/django-apps/weatherapp
source venv/bin/activate
python manage.py dbshell
```

### Static Files Not Loading

1. Collect static files:
```bash
cd /opt/django-apps/weatherapp
source venv/bin/activate
python manage.py collectstatic --noinput
```

2. Check Nginx static file configuration
3. Verify file permissions:
```bash
ls -la /opt/django-apps/weatherapp/staticfiles/
```

### Service Won't Start

1. Check service logs:
```bash
journalctl -u django-weatherapp -n 50
```

2. Check for port conflicts:
```bash
netstat -tlnp | grep 8001
```

3. Verify user permissions:
```bash
chown -R django-weatherapp:django-weatherapp /opt/django-apps/weatherapp
```

### High Memory/CPU Usage

1. Check running processes:
```bash
htop
```

2. Adjust Gunicorn workers in systemd service file:
```bash
nano /etc/systemd/system/django-weatherapp.service
# Change --workers parameter
systemctl daemon-reload
systemctl restart django-weatherapp
```

## Monitoring

### Automated Monitoring

A monitoring script runs every 5 minutes via cron:
```bash
# View monitoring log
tail -f /var/log/django-apps/weatherapp/monitor.log
```

### Manual Health Check

```bash
# Check application health
curl http://119.93.148.180/weatherapp/health/

# Check service status
systemctl is-active django-weatherapp
systemctl is-active celery-weatherapp
systemctl is-active celerybeat-weatherapp
```

## Backup and Recovery

### Create Backup

```bash
weatherapp-manage.sh backup
```

Or manually:
```bash
cd /opt/backups/weatherapp
tar -czf backup_$(date +%Y%m%d_%H%M%S).tar.gz /opt/django-apps/weatherapp
```

### Restore from Backup

```bash
# Stop services
systemctl stop django-weatherapp celery-weatherapp celerybeat-weatherapp

# Extract backup
cd /opt/django-apps
rm -rf weatherapp
tar -xzf /opt/backups/weatherapp/backup_YYYYMMDD_HHMMSS.tar.gz

# Fix permissions
chown -R django-weatherapp:django-weatherapp /opt/django-apps/weatherapp

# Start services
systemctl start django-weatherapp celery-weatherapp celerybeat-weatherapp
```

## Security Considerations

### Firewall Configuration

```bash
# Allow HTTP/HTTPS
ufw allow 80/tcp
ufw allow 443/tcp

# Allow SSH
ufw allow 22/tcp

# Enable firewall
ufw enable
```

### SSL/HTTPS Setup (Optional)

For production, consider setting up SSL:

```bash
# Install certbot
apt install certbot python3-certbot-nginx

# Obtain certificate (requires domain name)
certbot --nginx -d yourdomain.com

# Auto-renewal is configured via cron
```

### Security Headers

Security headers are already configured in Nginx. To customize:
```bash
nano /etc/nginx/sites-available/weatherapp
```

## Performance Optimization

### Database Optimization

```bash
# Run database optimization
cd /opt/django-apps/weatherapp
source venv/bin/activate
python manage.py optimize_db  # If you have this command
```

### Static File Caching

Static files are configured with 1-year cache. To modify:
```bash
nano /etc/nginx/sites-available/weatherapp
# Look for "expires 1y" and adjust
```

### Redis Optimization

Redis is configured for optimal performance. To adjust:
```bash
nano /etc/redis/redis.conf
systemctl restart redis-server
```

## Maintenance

### Regular Maintenance Tasks

1. **Weekly**: Check logs for errors
2. **Weekly**: Review disk space usage
3. **Monthly**: Update system packages
4. **Monthly**: Review and rotate logs
5. **Quarterly**: Test backup restoration

### Update System Packages

```bash
apt update && apt upgrade -y
systemctl restart django-weatherapp
```

### Clear Old Logs

```bash
# Clear logs older than 30 days
find /var/log/django-apps/weatherapp -name "*.log" -mtime +30 -delete
```

## Support

### Getting Help

1. Check application logs
2. Check system logs (journalctl)
3. Verify all services are running
4. Check firewall rules
5. Verify network connectivity

### Useful Commands Reference

```bash
# Service management
weatherapp-manage.sh [status|start|stop|restart|logs|update|backup]

# View logs
journalctl -u django-weatherapp -f
tail -f /var/log/django-apps/weatherapp/error.log

# Django management
cd /opt/django-apps/weatherapp && source venv/bin/activate
python manage.py [command]

# Database operations
python manage.py migrate
python manage.py createsuperuser
python manage.py dbshell

# Check system resources
htop
df -h
free -h
```

## Additional Resources

- Django Documentation: https://docs.djangoproject.com/
- Nginx Documentation: https://nginx.org/en/docs/
- Gunicorn Documentation: https://docs.gunicorn.org/
- Celery Documentation: https://docs.celeryproject.org/

---

**Deployment completed successfully!**

Your WeatherAlert application is now accessible at:
**http://119.93.148.180/weatherapp**

