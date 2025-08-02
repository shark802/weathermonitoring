# Heroku Deployment Troubleshooting Guide

## Current Error Analysis
Based on your logs, you're experiencing:
- **H14 Error**: "No web processes running" - This is the main issue
- **Build failures**: Some builds are failing during deployment

## Root Causes & Solutions

### 1. H14 Error - No Web Processes Running
**Cause**: The web dyno is not scaled up or not running properly.

**Solution**:
```bash
# Scale up the web dyno
heroku ps:scale web=1

# Check dyno status
heroku ps
```

### 2. Build Failures
**Cause**: Missing dependencies or configuration issues.

**Solutions Applied**:
- ✅ Added `dj-database-url==2.1.0` to requirements.txt
- ✅ Created `runtime.txt` with Python 3.11.18
- ✅ Updated settings.py for production environment
- ✅ Fixed static files configuration with whitenoise

### 3. Database Connection Issues
**Cause**: No database configured for production.

**Solution**:
```bash
# Add PostgreSQL database
heroku addons:create heroku-postgresql:mini

# Check database URL
heroku config:get DATABASE_URL
```

## Quick Fix Commands

Run these commands in order:

```bash
# 1. Set environment variables
heroku config:set SECRET_KEY="django-insecure-d0a@+xqkrda!+gb$6huxlb6&fngp+j^gs^#hbb5z*^*iny5g2c"
heroku config:set DEBUG="False"

# 2. Add database (if not already added)
heroku addons:create heroku-postgresql:mini

# 3. Deploy the updated code
git add .
git commit -m "Fix Heroku deployment configuration"
git push heroku main

# 4. Run migrations
heroku run python manage.py migrate

# 5. Collect static files
heroku run python manage.py collectstatic --noinput

# 6. Scale the web dyno (FIXES H14 ERROR)
heroku ps:scale web=1

# 7. Check the app
heroku open
```

## Verification Steps

After running the commands above:

1. **Check dyno status**:
   ```bash
   heroku ps
   ```

2. **Check logs**:
   ```bash
   heroku logs --tail
   ```

3. **Test the app**:
   ```bash
   heroku open
   ```

## Expected Results

After fixing:
- ✅ No more H14 errors
- ✅ App should be accessible at https://bccweather-629d88a334c9.herokuapp.com
- ✅ Static files should load properly
- ✅ Database should be connected

## If Issues Persist

1. **Check build logs**:
   ```bash
   heroku builds:info
   ```

2. **Restart the dyno**:
   ```bash
   heroku restart
   ```

3. **Check configuration**:
   ```bash
   heroku config
   ``` 