# WeatherAlert - Quick Deployment Guide 🚀

## Your Application Will Be Available At:
```
http://119.93.148.180/weatherapp
```

## Super Quick Deploy (Windows)

### Option 1: PowerShell Script (Easiest) ⭐

1. Open PowerShell in this directory:
```powershell
cd "C:\Users\JaOsn\Desktop\BCC PythonApps\weatherapp"
```

2. Run the deployment script:
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\deploy_scripts\windows_deploy.ps1
```

3. Select **Option 1** for first deployment or **Option 2** for updates

4. Done! 🎉

### Option 2: Manual Deployment

1. **Transfer files to server**:
```powershell
scp -r weatherapp weatheralert manage.py requirements.txt root@119.93.148.180:/tmp/weatherapp/
scp deploy_scripts/deploy_to_server.sh root@119.93.148.180:/tmp/
```

2. **SSH and deploy**:
```powershell
ssh root@119.93.148.180
cd /tmp
chmod +x deploy_to_server.sh
./deploy_to_server.sh
```

3. Wait 10-20 minutes for deployment to complete

4. Access at: `http://119.93.148.180/weatherapp`

## After Deployment

### Check Status
```bash
ssh root@119.93.148.180
weatherapp-manage.sh status
```

### View Logs
```bash
weatherapp-manage.sh logs
```

### Restart Services
```bash
weatherapp-manage.sh restart
```

## Quick Update (After First Deployment)

```powershell
.\deploy_scripts\windows_deploy.ps1
# Select option 2
```

Or manually:
```powershell
scp -r weatherapp weatheralert root@119.93.148.180:/tmp/weatherapp_update/
ssh root@119.93.148.180 "/tmp/quick_deploy_to_server.sh"
```

## Files Created

### Deployment Scripts
- ✅ `deploy_scripts/deploy_to_server.sh` - Full deployment
- ✅ `deploy_scripts/quick_deploy_to_server.sh` - Quick updates
- ✅ `deploy_scripts/windows_deploy.ps1` - Windows helper (PowerShell)
- ✅ `deploy_scripts/windows_deploy.bat` - Windows helper (CMD)
- ✅ `deploy_scripts/verify_deployment.sh` - Verification

### Documentation
- ✅ `DEPLOYMENT_INSTRUCTIONS.md` - Detailed guide
- ✅ `deploy_scripts/README_SERVER_DEPLOYMENT.md` - Server operations
- ✅ `deploy_scripts/DEPLOYMENT_SUMMARY.md` - Complete reference

### Configuration
- ✅ `weatheralert/settings.py` - Updated with new IP
- ✅ `weatheralert/settings_production.py` - Production settings
- ✅ `requirements_production.txt` - Production dependencies

## Configuration Summary

| Setting | Value |
|---------|-------|
| Server IP | 119.93.148.180 |
| Application URL | /weatherapp |
| Server Path | /opt/django-apps/weatherapp |
| Database | MySQL (existing) |
| Python Version | 3.8+ |
| Django Version | 4.1.13 |

## Services

After deployment, these services will run:
- **django-weatherapp** - Main application (Gunicorn)
- **celery-weatherapp** - Background tasks
- **celerybeat-weatherapp** - Scheduled tasks
- **nginx** - Web server
- **redis-server** - Message broker

## Management Commands

All commands run on the server via SSH:

```bash
# General management
weatherapp-manage.sh [status|start|stop|restart|logs|update|backup]

# Service control
systemctl [start|stop|restart|status] django-weatherapp
systemctl [start|stop|restart|status] celery-weatherapp
systemctl [start|stop|restart|status] nginx

# View logs
tail -f /var/log/django-apps/weatherapp/error.log
journalctl -u django-weatherapp -f

# Django commands
cd /opt/django-apps/weatherapp
source venv/bin/activate
python manage.py [command]
```

## Troubleshooting

### Application not loading?
```bash
ssh root@119.93.148.180
weatherapp-manage.sh status    # Check services
weatherapp-manage.sh logs      # View errors
weatherapp-manage.sh restart   # Restart all
```

### Static files missing?
```bash
ssh root@119.93.148.180
cd /opt/django-apps/weatherapp
source venv/bin/activate
python manage.py collectstatic --noinput
systemctl restart nginx
```

### Need to rollback?
```bash
ssh root@119.93.148.180
cd /opt/backups/weatherapp
# Find latest backup
ls -lt
# Restore it (see full documentation)
```

## What The Deployment Does

1. ✅ Updates system packages
2. ✅ Installs Python, Nginx, Redis
3. ✅ Creates directory structure
4. ✅ Sets up Python virtual environment
5. ✅ Installs application dependencies
6. ✅ Configures environment variables
7. ✅ Runs database migrations
8. ✅ Collects static files
9. ✅ Creates systemd services
10. ✅ Configures Nginx reverse proxy
11. ✅ Starts all services
12. ✅ Sets up monitoring
13. ✅ Creates management tools

## Important Notes

- ⚠️ **First deployment takes 10-20 minutes**
- ⚠️ **Updates take 2-5 minutes**
- ⚠️ **Make sure you have SSH access to the server**
- ⚠️ **Backup important data before deploying**
- ℹ️ **Monitoring runs automatically every 5 minutes**
- ℹ️ **Logs are rotated automatically**

## Need More Help?

1. **Quick Start**: See `DEPLOYMENT_INSTRUCTIONS.md`
2. **Server Operations**: See `deploy_scripts/README_SERVER_DEPLOYMENT.md`
3. **Complete Reference**: See `deploy_scripts/DEPLOYMENT_SUMMARY.md`

## Support

If deployment fails:
1. Check the error messages
2. View logs: `tail -f /var/log/django-apps/weatherapp/error.log`
3. Check service status: `weatherapp-manage.sh status`
4. Review troubleshooting section in documentation

---

## Ready to Deploy?

**Windows PowerShell (Recommended):**
```powershell
.\deploy_scripts\windows_deploy.ps1
```

**Manual SSH:**
```bash
ssh root@119.93.148.180
```

**Your app will be at:**
```
http://119.93.148.180/weatherapp
```

Good luck! 🚀✨

