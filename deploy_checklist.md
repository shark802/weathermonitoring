# Heroku Deployment Checklist

## Issues Fixed:
1. ✅ Added dj-database-url to requirements.txt
2. ✅ Updated settings.py for production environment
3. ✅ Added environment variable support
4. ✅ Fixed static files configuration
5. ✅ Added security settings for production
6. ✅ Created runtime.txt for Python version
7. ✅ Created build.sh script

## Next Steps:
1. Set environment variables in Heroku:
   ```bash
   heroku config:set SECRET_KEY="your-secret-key-here"
   heroku config:set DEBUG="False"
   heroku config:set DATABASE_URL="your-database-url"
   ```

2. Add database addon to Heroku:
   ```bash
   heroku addons:create heroku-postgresql:mini
   ```

3. Run migrations:
   ```bash
   heroku run python manage.py migrate
   ```

4. Collect static files:
   ```bash
   heroku run python manage.py collectstatic --noinput
   ```

5. Scale the web dyno:
   ```bash
   heroku ps:scale web=1
   ```

## Common Issues:
- H14 error: No web processes running - Fixed by scaling web dyno
- Build failures: Check requirements.txt and runtime.txt
- Database connection: Ensure DATABASE_URL is set
- Static files: Ensure whitenoise is configured properly 