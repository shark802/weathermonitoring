# Environment Variables Setup Guide

This guide explains how to set up environment variables for the WeatherAlert application.

## Security Notice

⚠️ **NEVER commit credentials to version control!**

The `.env` file is gitignored and should contain your actual credentials. Use `.env.example` as a template.

## Required Environment Variables

Create a `.env` file in the project root with the following variables:

```bash
# Django Settings
# Generate a new secret key: python -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())"
SECRET_KEY=your-secret-key-change-this-in-production
DEBUG=False
ALLOWED_HOSTS=your-server-ip,localhost,127.0.0.1

# Database (MySQL)
DB_NAME=your-database-name
DB_USER=your-database-user
DB_PASSWORD=your-database-password
DB_HOST=your-database-host
DB_PORT=3306

# Email Configuration
EMAIL_HOST=smtp.gmail.com
EMAIL_PORT=587
EMAIL_USE_TLS=True
EMAIL_HOST_USER=your-email@gmail.com
EMAIL_HOST_PASSWORD=your-app-password

# SMS API Configuration
SMS_API_URL=https://sms.pagenet.info/api/v1/sms/send
SMS_API_KEY=your-sms-api-key
SMS_DEVICE_ID=your-sms-device-id

# PhilSys QR Verification Keys (Optional)
# PSA_PUBLIC_KEY=your-psa-public-key
# PSA_ED25519_PUBLIC_KEY=your-psa-ed25519-public-key

# Subpath hosting (if applicable)
FORCE_SCRIPT_NAME=/weatherapp
STATIC_URL=/weatherapp/static/
MEDIA_URL=/weatherapp/media/
SESSION_COOKIE_PATH=/weatherapp
CSRF_COOKIE_PATH=/weatherapp

# Celery (Redis)
REDIS_URL=redis://localhost:6379/0
CELERY_BROKER_URL=redis://localhost:6379/0
CELERY_RESULT_BACKEND=redis://localhost:6379/0
```

## Setting Variables Before Deployment

You can set environment variables before running the deployment script:

```bash
export DB_NAME="your-database-name"
export DB_USER="your-database-user"
export DB_PASSWORD="your-database-password"
export DB_HOST="your-database-host"
export EMAIL_HOST_USER="your-email@gmail.com"
export EMAIL_HOST_PASSWORD="your-app-password"
export SMS_API_KEY="your-sms-api-key"
export SMS_DEVICE_ID="your-sms-device-id"
export SECRET_KEY="your-generated-secret-key"

# Then run deployment
./deploy_weatherapp.sh
```

## Generating a Secret Key

Generate a secure Django secret key:

```bash
python -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())"
```

## Production Best Practices

1. **Use a secrets manager** (AWS Secrets Manager, HashiCorp Vault, etc.)
2. **Rotate credentials regularly**
3. **Use different credentials for each environment** (dev, staging, production)
4. **Never log credentials** or include them in error messages
5. **Restrict file permissions**: `chmod 600 .env`
6. **Use environment variables** instead of `.env` file in containerized deployments

## Verification

After setting up your `.env` file, verify it's working:

```bash
# Check that .env is gitignored
git check-ignore .env

# Test Django can read the variables
python manage.py check
```

