# Deployment Scripts Overview

This directory contains comprehensive deployment scripts for the weather application on Ubuntu server.

## 🚀 **Quick Start - Recommended Approach**

### **For Complete Fresh Deployment:**
```bash
# Make scripts executable
chmod +x deploy_scripts/*.sh

# Run the final comprehensive deployment
./deploy_scripts/final_deploy.sh
```

### **For Fixing Existing Deployment:**
```bash
# Make scripts executable
chmod +x deploy_scripts/*.sh

# Run the fix script
./deploy_scripts/fix_deployment.sh
```

## 📋 **Script Descriptions**

### **1. `final_deploy.sh` - ⭐ RECOMMENDED**
- **Purpose**: Complete fresh deployment with full cleanup
- **Use when**: Starting fresh or completely overriding existing deployment
- **Features**:
  - Complete cleanup of existing services
  - Fresh virtual environment setup
  - Proper path configuration for `/home/bccbsis-py-admin/weatherapp`
  - Comprehensive error handling
  - Full validation and testing

### **2. `fix_deployment.sh`**
- **Purpose**: Fix existing deployment without full cleanup
- **Use when**: You have an existing deployment that needs path corrections
- **Features**:
  - Stops existing services
  - Updates configurations with correct paths
  - Preserves existing virtual environment
  - Quick fix approach

### **3. `complete_deploy.sh`**
- **Purpose**: Comprehensive deployment with error handling
- **Use when**: You want detailed error checking and validation
- **Features**:
  - Step-by-step deployment with validation
  - Comprehensive error handling
  - Django configuration checks
  - Service validation

### **4. `deploy_app.sh`**
- **Purpose**: Basic application deployment
- **Use when**: You have a clean environment and just need app deployment
- **Features**:
  - Standard deployment process
  - Basic error handling
  - Configuration file generation

### **5. `setup_environment.sh`**
- **Purpose**: System environment setup
- **Use when**: Setting up a new Ubuntu server
- **Features**:
  - Installs all required packages
  - Configures system services
  - Sets up directories and permissions

### **6. `test_deployment.sh`**
- **Purpose**: Test and validate deployment
- **Use when**: After deployment to verify everything works
- **Features**:
  - Comprehensive testing suite
  - Service status checks
  - Endpoint testing
  - Detailed test results

### **7. `validate_deployment.sh`**
- **Purpose**: Detailed validation of deployment
- **Use when**: Troubleshooting deployment issues
- **Features**:
  - Detailed validation checks
  - Service verification
  - Configuration validation
  - Log file checks

### **8. `add_new_app.sh`**
- **Purpose**: Add additional Python applications
- **Use when**: Adding more apps to the multi-app server
- **Features**:
  - Adds new apps on different ports
  - Updates nginx configuration
  - Creates supervisor configurations

### **9. `monitor_apps.sh`**
- **Purpose**: Monitor all applications
- **Use when**: Checking system health and status
- **Features**:
  - Service status monitoring
  - Resource usage checks
  - Log viewing
  - Health endpoint testing

## 🔧 **Script Execution Order**

### **For Fresh Server Setup:**
1. `setup_environment.sh` - Set up system
2. `final_deploy.sh` - Deploy application
3. `test_deployment.sh` - Verify deployment

### **For Fixing Existing Deployment:**
1. `fix_deployment.sh` - Fix existing deployment
2. `test_deployment.sh` - Verify fixes

### **For Adding More Applications:**
1. `add_new_app.sh <app_name> <port> <path>` - Add new app
2. `monitor_apps.sh` - Check all apps

## ⚠️ **Important Notes**

### **Path Configuration:**
- All scripts are configured for `/home/bccbsis-py-admin/weatherapp`
- This matches your current server setup
- Scripts will automatically use the correct paths

### **Service Management:**
- Uses Supervisor for process management
- Nginx for reverse proxy
- Redis for Celery message broker
- MySQL for database

### **Error Handling:**
- All scripts include comprehensive error handling
- Failed steps will stop execution with clear error messages
- Logs are available for troubleshooting

### **Permissions:**
- Scripts handle proper file permissions
- www-data user for web services
- Proper directory permissions

## 🚨 **Troubleshooting**

### **Common Issues:**

1. **502 Bad Gateway**
   - Run: `sudo supervisorctl status`
   - Check: `sudo tail -f /var/log/weatherapp/gunicorn.log`

2. **Permission Denied**
   - Run: `sudo chown -R www-data:www-data /home/bccbsis-py-admin/weatherapp`

3. **Nginx Configuration Error**
   - Run: `sudo nginx -t`
   - Check: `/etc/nginx/sites-available/weatherapp`

4. **Database Connection Issues**
   - Check: MySQL service status
   - Verify: Database credentials in `.env`

### **Useful Commands:**
```bash
# Check all services
sudo supervisorctl status

# View application logs
sudo tail -f /var/log/weatherapp/gunicorn.log

# Test nginx configuration
sudo nginx -t

# Restart all services
sudo supervisorctl restart all

# Check port usage
sudo netstat -tlnp | grep :8001
```

## 📊 **Expected Results**

After successful deployment:
- **Weather App**: `http://192.168.3.5/weatherapp/`
- **Health Check**: `http://192.168.3.5/health`
- **Admin Panel**: `http://192.168.3.5/weatherapp/admin/`

All services should be running and accessible via the configured URLs.

## 🔄 **Maintenance**

### **Regular Tasks:**
- Monitor logs: `./deploy_scripts/monitor_apps.sh`
- Check service status: `sudo supervisorctl status`
- Update application: Pull changes and restart services
- Backup database: Regular MySQL backups

### **Updates:**
- Update code: `git pull` in app directory
- Restart services: `sudo supervisorctl restart weatherapp`
- Test deployment: `./deploy_scripts/test_deployment.sh`

---

**Choose the appropriate script based on your needs. For most cases, `final_deploy.sh` is the recommended starting point.**
