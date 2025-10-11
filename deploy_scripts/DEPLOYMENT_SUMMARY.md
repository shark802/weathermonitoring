# WeatherAlert - Deployment Summary

## Quick Reference

### Application Details
- **Server IP**: `119.93.148.180`
- **Access URL**: `http://119.93.148.180/weatherapp`
- **Deployment Path**: `/opt/django-apps/weatherapp`
- **Python Version**: 3.8+
- **Django Version**: 4.1.13

## Files Created/Modified

### 1. Django Settings
- ✅ `weatheralert/settings.py` - Updated with new IP and subpath support
- ✅ `weatheralert/settings_production.py` - Production-optimized settings
- ✅ Added `FORCE_SCRIPT_NAME` for subpath deployment

### 2. Deployment Scripts

#### Main Deployment Scripts
- ✅ `deploy_scripts/deploy_to_server.sh` - Full deployment script (Linux/Server)
- ✅ `deploy_scripts/quick_deploy_to_server.sh` - Quick update script (Linux/Server)

#### Windows Helper Scripts
- ✅ `deploy_scripts/windows_deploy.bat` - Windows batch script
- ✅ `deploy_scripts/windows_deploy.ps1` - PowerShell deployment script (Recommended)

#### Verification & Utilities
- ✅ `deploy_scripts/verify_deployment.sh` - Post-deployment verification
- ✅ `deploy_scripts/README_SERVER_DEPLOYMENT.md` - Detailed deployment guide

### 3. Documentation
- ✅ `DEPLOYMENT_INSTRUCTIONS.md` - Quick start guide
- ✅ `requirements_production.txt` - Production dependencies

## Deployment Flow

### First-Time Deployment

```
Windows Machine                    Server (119.93.148.180)
     |                                     |
     |---1. Transfer Files---------------->|
     |                                     |
     |---2. Run deploy_to_server.sh------->|
     |                                     |
     |                              3. Install Dependencies
     |                                     |
     |                              4. Setup Services
     |                                     |
     |                              5. Configure Nginx
     |                                     |
     |<--6. Application Running------------|
     |                                     |
```

### Update Deployment

```
Windows Machine                    Server (119.93.148.180)
     |                                     |
     |---1. Transfer Updated Code--------->|
     |                                     |
     |---2. Run quick_deploy_to_server.sh->|
     |                                     |
     |                              3. Update Dependencies
     |                                     |
     |                              4. Run Migrations
     |                                     |
     |                              5. Collect Static Files
     |                                     |
     |                              6. Restart Services
     |                                     |
     |<--7. Updated Application Running----|
     |                                     |
```

## Services Architecture

```
┌─────────────────────────────────────────────────────┐
│                 Internet Users                       │
└───────────────────┬─────────────────────────────────┘
                    │
                    │ HTTP (Port 80)
                    ▼
┌─────────────────────────────────────────────────────┐
│                    Nginx                             │
│            (Reverse Proxy)                           │
│    - Static files serving                            │
│    - Request routing                                 │
│    - Security headers                                │
└───────────────────┬─────────────────────────────────┘
                    │
                    │ Proxy to localhost:8001
                    ▼
┌─────────────────────────────────────────────────────┐
│              Gunicorn (WSGI Server)                  │
│         - 3 Worker processes                         │
│         - Handles Django requests                    │
└───────────────────┬─────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────┐
│            Django Application                        │
│         (WeatherAlert)                               │
│    - Business logic                                  │
│    - View rendering                                  │
│    - API endpoints                                   │
└─────┬────────────────────────────────┬──────────────┘
      │                                │
      │                                │
      ▼                                ▼
┌──────────────┐              ┌──────────────────────┐
│   MySQL DB   │              │   Celery Workers     │
│  (External)  │              │  - Background tasks  │
│              │              │  - Celery Beat       │
└──────────────┘              └──────┬───────────────┘
                                     │
                                     ▼
                              ┌──────────────┐
                              │    Redis     │
                              │  (Message    │
                              │   Broker)    │
                              └──────────────┘
```

## Service Details

### 1. Nginx (Web Server)
- **Port**: 80
- **Config**: `/etc/nginx/sites-available/weatherapp`
- **Purpose**: Reverse proxy, static file serving
- **Command**: `systemctl status nginx`

### 2. Django/Gunicorn (Application Server)
- **Port**: 8001 (localhost only)
- **Service**: `django-weatherapp`
- **Workers**: 3
- **Command**: `systemctl status django-weatherapp`

### 3. Celery Worker (Task Queue)
- **Service**: `celery-weatherapp`
- **Purpose**: Background task processing
- **Command**: `systemctl status celery-weatherapp`

### 4. Celery Beat (Scheduler)
- **Service**: `celerybeat-weatherapp`
- **Purpose**: Periodic task scheduling
- **Command**: `systemctl status celerybeat-weatherapp`

### 5. Redis (Message Broker)
- **Port**: 6379
- **Purpose**: Celery message broker and cache
- **Command**: `systemctl status redis-server`

## Directory Structure on Server

```
/opt/django-apps/weatherapp/
├── weatheralert/              # Django project settings
│   ├── settings.py
│   ├── settings_production.py
│   ├── urls.py
│   └── wsgi.py
├── weatherapp/                # Main application
│   ├── models.py
│   ├── views.py
│   ├── urls.py
│   ├── templates/
│   └── static/
├── venv/                      # Python virtual environment
├── staticfiles/               # Collected static files
├── media/                     # User-uploaded files
├── manage.py
├── requirements.txt
└── .env                       # Environment variables

/var/log/django-apps/weatherapp/
├── access.log                 # Gunicorn access log
├── error.log                  # Gunicorn error log
├── celery.log                 # Celery worker log
├── celerybeat.log             # Celery beat log
├── nginx-access.log           # Nginx access log
├── nginx-error.log            # Nginx error log
└── monitor.log                # Monitoring script log

/etc/systemd/system/
├── django-weatherapp.service
├── celery-weatherapp.service
└── celerybeat-weatherapp.service
```

## Environment Variables

Key environment variables in `/opt/django-apps/weatherapp/.env`:

```bash
DEBUG=False
SECRET_KEY=<auto-generated>
ALLOWED_HOSTS=119.93.148.180,localhost,127.0.0.1
FORCE_SCRIPT_NAME=/weatherapp

DATABASE_URL=mysql://user:pass@host:port/dbname
REDIS_URL=redis://localhost:6379/0

EMAIL_HOST=smtp.gmail.com
EMAIL_PORT=587
EMAIL_HOST_USER=rainalertcaps@gmail.com
EMAIL_HOST_PASSWORD=<password>

SMS_API_URL=<sms-api-url>
SMS_API_KEY=<sms-api-key>

STATIC_URL=/weatherapp/static/
MEDIA_URL=/weatherapp/media/
SESSION_COOKIE_PATH=/weatherapp
```

## Management Commands

### Using Management Script (Recommended)

```bash
# Show status
weatherapp-manage.sh status

# Restart all services
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

### Direct Service Management

```bash
# Start services
systemctl start django-weatherapp
systemctl start celery-weatherapp
systemctl start celerybeat-weatherapp

# Stop services
systemctl stop django-weatherapp
systemctl stop celery-weatherapp
systemctl stop celerybeat-weatherapp

# Restart services
systemctl restart django-weatherapp
systemctl restart nginx

# View service status
systemctl status django-weatherapp
```

### View Logs

```bash
# Follow Django logs
tail -f /var/log/django-apps/weatherapp/error.log

# Follow Celery logs
tail -f /var/log/django-apps/weatherapp/celery.log

# View systemd logs
journalctl -u django-weatherapp -f
journalctl -u celery-weatherapp -f
```

## Monitoring

### Automated Monitoring
- **Script**: `/usr/local/bin/monitor-weatherapp.sh`
- **Schedule**: Every 5 minutes (cron)
- **Log**: `/var/log/django-apps/weatherapp/monitor.log`

### Manual Health Check

```bash
# Check application response
curl http://119.93.148.180/weatherapp/

# Check health endpoint
curl http://119.93.148.180/weatherapp/health/

# Check all services
systemctl is-active django-weatherapp celery-weatherapp nginx redis-server
```

## Common Operations

### Deploy Updates

```powershell
# From Windows PowerShell
.\deploy_scripts\windows_deploy.ps1
# Select option 2 (Quick update)
```

### Rollback Deployment

```bash
# SSH to server
ssh root@119.93.148.180

# Stop services
systemctl stop django-weatherapp celery-weatherapp celerybeat-weatherapp

# Restore from backup
cd /opt/django-apps
mv weatherapp weatherapp.broken
tar -xzf /opt/backups/weatherapp/backup_YYYYMMDD_HHMMSS.tar.gz

# Fix permissions
chown -R django-weatherapp:django-weatherapp weatherapp

# Start services
systemctl start django-weatherapp celery-weatherapp celerybeat-weatherapp
```

### Clear Cache

```bash
# Clear Redis cache
redis-cli FLUSHDB

# Or via Django
cd /opt/django-apps/weatherapp
source venv/bin/activate
python manage.py shell
>>> from django.core.cache import cache
>>> cache.clear()
```

### Database Operations

```bash
cd /opt/django-apps/weatherapp
source venv/bin/activate

# Run migrations
python manage.py migrate

# Create superuser
python manage.py createsuperuser

# Database shell
python manage.py dbshell
```

## Security Considerations

### Firewall Rules
```bash
# Allow HTTP
ufw allow 80/tcp

# Allow HTTPS (for future SSL)
ufw allow 443/tcp

# Allow SSH
ufw allow 22/tcp

# Enable firewall
ufw enable
```

### SSL/HTTPS (Future)
To enable HTTPS:
1. Get a domain name
2. Point DNS to 119.93.148.180
3. Install certbot: `apt install certbot python3-certbot-nginx`
4. Run: `certbot --nginx -d yourdomain.com`

### Security Checklist
- ✅ DEBUG mode disabled in production
- ✅ Strong SECRET_KEY generated
- ✅ ALLOWED_HOSTS configured
- ✅ Security headers enabled in Nginx
- ✅ Services run as non-root user
- ⚠️ SSL/HTTPS not yet configured (recommended)
- ⚠️ Change default admin password after first login

## Performance Tuning

### Gunicorn Workers
Adjust workers in `/etc/systemd/system/django-weatherapp.service`:
```
--workers <number>
```
Recommended: (CPU cores × 2) + 1

### Database Connection Pooling
Already configured in Django settings with persistent connections.

### Redis Memory Limit
Configured at 256MB in `/etc/redis/redis.conf`

### Static File Caching
Nginx serves static files with 1-year cache headers.

## Troubleshooting Guide

### Issue: Application Not Loading

```bash
# 1. Check services
weatherapp-manage.sh status

# 2. Check logs
tail -n 50 /var/log/django-apps/weatherapp/error.log

# 3. Restart services
weatherapp-manage.sh restart

# 4. Verify deployment
bash /opt/django-apps/weatherapp/deploy_scripts/verify_deployment.sh
```

### Issue: Static Files Not Loading

```bash
cd /opt/django-apps/weatherapp
source venv/bin/activate
python manage.py collectstatic --noinput
systemctl restart nginx
```

### Issue: Database Connection Error

```bash
# Test database connection
mysql -h 153.92.15.8 -u u520834156_uWApp2024 -p u520834156_dbweatherApp

# Check settings
nano /opt/django-apps/weatherapp/.env
```

### Issue: High Memory Usage

```bash
# Check memory
free -h
htop

# Restart services to free memory
systemctl restart django-weatherapp celery-weatherapp
```

## Next Steps After Deployment

1. ✅ Access application: `http://119.93.148.180/weatherapp`
2. ⬜ Change default admin credentials
3. ⬜ Setup regular backups (already automated)
4. ⬜ Monitor application logs daily
5. ⬜ Consider domain name + SSL for production
6. ⬜ Setup email notifications for errors
7. ⬜ Configure firewall rules
8. ⬜ Setup monitoring/alerting

## Support & Documentation

- **Deployment Guide**: `deploy_scripts/README_SERVER_DEPLOYMENT.md`
- **Quick Start**: `DEPLOYMENT_INSTRUCTIONS.md`
- **Django Docs**: https://docs.djangoproject.com/
- **Nginx Docs**: https://nginx.org/en/docs/

## Summary

✅ **All scripts created and configured**
✅ **Server IP set to: 119.93.148.180**
✅ **Application path set to: /weatherapp**
✅ **Windows deployment helpers included**
✅ **Automated monitoring configured**
✅ **Management scripts included**
✅ **Production settings optimized**

**Ready to deploy! Use the PowerShell script or follow manual instructions.**

---

*Last Updated: October 11, 2025*

