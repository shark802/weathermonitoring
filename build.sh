#!/usr/bin/env bash
# Build script for Heroku deployment

echo "Running Django migrations..."
python manage.py migrate --noinput

echo "Collecting static files..."
python manage.py collectstatic --noinput

echo "Build completed successfully!" 