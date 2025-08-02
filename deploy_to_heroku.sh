#!/usr/bin/env bash
# Deployment script for Heroku

echo "🚀 Starting Heroku deployment..."

# Check if we're in the right directory
if [ ! -f "manage.py" ]; then
    echo "❌ Error: manage.py not found. Please run this script from the Django project root."
    exit 1
fi

# Set environment variables
echo "📝 Setting environment variables..."
heroku config:set SECRET_KEY="django-insecure-d0a@+xqkrda!+gb$6huxlb6&fngp+j^gs^#hbb5z*^*iny5g2c"
heroku config:set DEBUG="False"

# Add PostgreSQL database if not already added
echo "🗄️  Setting up database..."
heroku addons:create heroku-postgresql:mini

# Deploy the application
echo "📦 Deploying to Heroku..."
git add .
git commit -m "Fix Heroku deployment configuration"
git push heroku main

# Run migrations
echo "🔄 Running database migrations..."
heroku run python manage.py migrate

# Collect static files
echo "📁 Collecting static files..."
heroku run python manage.py collectstatic --noinput

# Scale the web dyno (this fixes the H14 error)
echo "⚡ Scaling web dyno..."
heroku ps:scale web=1

echo "✅ Deployment completed!"
echo "🌐 Your app should now be available at: https://bccweather-629d88a334c9.herokuapp.com"

# Check the logs
echo "📋 Checking application logs..."
heroku logs --tail 