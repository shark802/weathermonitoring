# WeatherAlert - Deployment Instructions

## Quick Start Guide

Your WeatherAlert application will be deployed to:
- **Server IP**: `119.93.148.180`
- **URL**: `http://119.93.148.180/weatherapp`

## Prerequisites

### On Your Windows Machine

1. **Install SSH Client** (if not already installed):
   - Windows 10/11 includes OpenSSH by default
   - To verify: Open PowerShell and run `ssh -V`

2. **Install Git Bash** (alternative method):
   - Download from: https://git-scm.com/download/win
   - Provides Unix-like commands on Windows

### On the Server (119.93.148.180)

- Ubuntu 20.04 LTS or newer
- Root or sudo access
- Minimum 2GB RAM, 20GB disk space
- Ports 80, 443 open

## Deployment Methods

### Method 1: Using PowerShell (Recommended for Windows)

1. Open PowerShell as Administrator in your project directory:
   ```powershell
   cd "C:\Users\JaOsn\Desktop\BCC PythonApps\weatherapp"
   ```

2. Run the PowerShell deployment script:
   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   .\deploy_scripts\windows_deploy.ps1
   ```

3. Follow the interactive menu:
   - Choose option **1** for first-time deployment
   - Choose option **2** for updates

### Method 2: Using Git Bash

1. Open Git Bash in your project directory

2. Make scripts executable:
   ```bash
   chmod +x deploy_scripts/*.sh
   ```

3. Run deployment:
   ```bash
   # For first-time deployment
   ./deploy_scripts/deploy_to_server.sh
   
   # For updates
   ./deploy_scripts/quick_deploy_to_server.sh
   ```

### Method 3: Manual SSH Deployment

1. **Transfer files to server**:
   ```powershell
   # From PowerShell in project directory
   scp -r weatherapp weatheralert manage.py requirements.txt root@119.93.148.180:/tmp/weatherapp/
   scp deploy_scripts/deploy_to_server.sh root@119.93.148.180:/tmp/
   ```

2. **SSH to server and deploy**:
   ```powershell
   ssh root@119.93.148.180
   ```

3. **On the server, run**:
   ```bash
   cd /tmp
   chmod +x deploy_to_server.sh
   ./deploy_to_server.sh
   ```

## Step-by-Step First Deployment

### Step 1: Prepare Your Windows Machine

```powershell
# Open PowerShell
cd "C:\Users\JaOsn\Desktop\BCC PythonApps\weatherapp"

# Test SSH connection
ssh root@119.93.148.180
# (Type 'exit' after confirming connection works)
```

### Step 2: Run Deployment

**Option A - Using PowerShell Script (Easiest)**:
```powershell
.\deploy_scripts\windows_deploy.ps1
# Select option 1 (Full deployment)
```

**Option B - Manual Deployment**:
```powershell
# 1. Transfer deployment script
scp deploy_scripts\deploy_to_server.sh root@119.93.148.180:/tmp/

# 2. SSH to server
ssh root@119.93.148.180

# 3. On server, run:
chmod +x /tmp/deploy_to_server.sh
/tmp/deploy_to_server.sh
```

### Step 3: Wait for Deployment

The script will:
- ✓ Update system packages (2-5 minutes)
- ✓ Install dependencies (3-5 minutes)
- ✓ Setup Python environment (2-3 minutes)
- ✓ Configure services (1-2 minutes)
- ✓ Setup Nginx (1 minute)
- ✓ Start application (1 minute)

**Total time: 10-20 minutes**

### Step 4: Verify Deployment

1. Open browser and go to: `http://119.93.148.180/weatherapp`

2. You should see your WeatherAlert application!

## Post-Deployment Management

### Check Application Status

```powershell
# Using PowerShell script
.\deploy_scripts\windows_deploy.ps1
# Select option 6 (Check service status)
```

Or via SSH:
```bash
ssh root@119.93.148.180
weatherapp-manage.sh status
```

### View Logs

```powershell
# Using PowerShell script
.\deploy_scripts\windows_deploy.ps1
# Select option 4 (View logs)
```

Or via SSH:
```bash
ssh root@119.93.148.180
weatherapp-manage.sh logs
```

### Restart Services

```powershell
# Using PowerShell script
.\deploy_scripts\windows_deploy.ps1
# Select option 5 (Restart services)
```

Or via SSH:
```bash
ssh root@119.93.148.180
weatherapp-manage.sh restart
```

## Updating Your Application

When you make code changes and want to deploy updates:

### Quick Update (Recommended)

```powershell
# Using PowerShell
.\deploy_scripts\windows_deploy.ps1
# Select option 2 (Quick update)
```

This will:
1. Transfer updated code
2. Install new dependencies
3. Run migrations
4. Collect static files
5. Restart services

### Manual Update

```powershell
# Transfer updated files
scp -r weatherapp weatheralert root@119.93.148.180:/tmp/weatherapp_update/

# SSH and update
ssh root@119.93.148.180
cd /tmp
./quick_deploy_to_server.sh
```

## Useful Management Commands

### On Windows (via PowerShell)

```powershell
# Check if app is accessible
Invoke-WebRequest http://119.93.148.180/weatherapp

# View logs remotely
ssh root@119.93.148.180 "tail -f /var/log/django-apps/weatherapp/error.log"

# Restart remotely
ssh root@119.93.148.180 "systemctl restart django-weatherapp"
```

### On Server (via SSH)

```bash
# Quick status check
weatherapp-manage.sh status

# View live logs
weatherapp-manage.sh logs

# Restart application
weatherapp-manage.sh restart

# Create backup
weatherapp-manage.sh backup

# Django shell
weatherapp-manage.sh shell

# Individual service management
systemctl status django-weatherapp
systemctl restart django-weatherapp
systemctl restart celery-weatherapp
systemctl restart nginx

# View detailed logs
tail -f /var/log/django-apps/weatherapp/error.log
tail -f /var/log/django-apps/weatherapp/access.log
journalctl -u django-weatherapp -f
```

## Troubleshooting

### Application Not Loading

1. **Check services**:
   ```bash
   ssh root@119.93.148.180
   weatherapp-manage.sh status
   ```

2. **Check logs**:
   ```bash
   tail -f /var/log/django-apps/weatherapp/error.log
   ```

3. **Restart services**:
   ```bash
   weatherapp-manage.sh restart
   ```

### Database Connection Error

1. Verify database credentials in settings
2. Check if database server is accessible:
   ```bash
   mysql -h 153.92.15.8 -u u520834156_uWApp2024 -p u520834156_dbweatherApp
   ```

### Static Files Not Loading

```bash
ssh root@119.93.148.180
cd /opt/django-apps/weatherapp
source venv/bin/activate
python manage.py collectstatic --noinput
systemctl restart nginx
```

### Port 80 Already in Use

```bash
# Check what's using port 80
netstat -tlnp | grep :80

# If another service is using it, stop it
systemctl stop apache2  # if Apache is running
systemctl start nginx
```

### Permission Denied Errors

```bash
# Fix ownership
chown -R django-weatherapp:django-weatherapp /opt/django-apps/weatherapp

# Fix log permissions
chown -R django-weatherapp:django-weatherapp /var/log/django-apps/weatherapp
```

## Configuration Files

### Important Locations

```
Application Directory: /opt/django-apps/weatherapp/
Environment Config:    /opt/django-apps/weatherapp/.env
Logs:                  /var/log/django-apps/weatherapp/
Backups:               /opt/backups/weatherapp/
Nginx Config:          /etc/nginx/sites-available/weatherapp
Systemd Services:      /etc/systemd/system/django-weatherapp.service
```

### Editing Configuration

```bash
# SSH to server
ssh root@119.93.148.180

# Edit environment variables
nano /opt/django-apps/weatherapp/.env

# After editing, restart services
systemctl restart django-weatherapp
```

## Security Recommendations

### 1. Change Default Passwords

After deployment, create a new admin user:
```bash
ssh root@119.93.148.180
cd /opt/django-apps/weatherapp
source venv/bin/activate
python manage.py createsuperuser
```

### 2. Setup Firewall

```bash
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 22/tcp
ufw enable
```

### 3. Regular Backups

Setup automated backups:
```bash
# Backups are created automatically via cron
# Manual backup:
weatherapp-manage.sh backup
```

### 4. Monitor Logs

```bash
# Check for errors regularly
tail -f /var/log/django-apps/weatherapp/error.log
```

## Performance Optimization

### Adjust Worker Processes

Edit the systemd service:
```bash
nano /etc/systemd/system/django-weatherapp.service
# Change --workers 3 to desired number (CPU cores * 2 + 1)
systemctl daemon-reload
systemctl restart django-weatherapp
```

### Enable Compression

Already configured in Nginx, but verify:
```bash
nano /etc/nginx/sites-available/weatherapp
# Look for gzip settings
```

## Backup and Recovery

### Create Backup

```bash
# Automated via management script
weatherapp-manage.sh backup

# Manual backup
tar -czf backup.tar.gz /opt/django-apps/weatherapp
```

### Restore Backup

```bash
# Stop services
systemctl stop django-weatherapp celery-weatherapp celerybeat-weatherapp

# Extract backup
cd /opt/django-apps
tar -xzf /opt/backups/weatherapp/backup_YYYYMMDD_HHMMSS.tar.gz

# Fix permissions
chown -R django-weatherapp:django-weatherapp /opt/django-apps/weatherapp

# Start services
systemctl start django-weatherapp celery-weatherapp celerybeat-weatherapp
```

## Need Help?

### Quick Diagnostics

```bash
# Run on server
ssh root@119.93.148.180 << 'EOF'
echo "=== Services Status ==="
systemctl is-active django-weatherapp celery-weatherapp nginx redis-server

echo -e "\n=== Disk Space ==="
df -h /

echo -e "\n=== Memory Usage ==="
free -h

echo -e "\n=== Recent Errors ==="
tail -n 20 /var/log/django-apps/weatherapp/error.log

echo -e "\n=== App Response ==="
curl -I http://localhost/weatherapp/
EOF
```

### Getting More Information

Check the detailed deployment guide:
```bash
cat deploy_scripts/README_SERVER_DEPLOYMENT.md
```

---

## Summary

**First Deployment**:
```powershell
.\deploy_scripts\windows_deploy.ps1  # Select option 1
```

**Update Application**:
```powershell
.\deploy_scripts\windows_deploy.ps1  # Select option 2
```

**Access Application**:
```
http://119.93.148.180/weatherapp
```

**Manage Services**:
```bash
ssh root@119.93.148.180
weatherapp-manage.sh [status|restart|logs|backup]
```

That's it! Your WeatherAlert application is now professionally deployed! 🎉

