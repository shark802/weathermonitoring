#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# One-Run Live Deployment Script for WeatherApp
# Deploys Django app at http://119.93.148.180/weatherapp
# =============================================================================

# Configuration (auto-detected where possible)
APP_NAME="weatherapp"
APP_USER="$(whoami)"
# Use current working directory as app root (run the script from the project root)
APP_ROOT="$(pwd)"
# Default virtualenv inside project directory to meet requirement: weatherapp/myenv
VENV_PATH="${APP_ROOT}/myenv"
SERVICE_NAME="${APP_NAME}"
NGINX_SITE="${APP_NAME}"
PUBLIC_IP="119.93.148.180"
LOCAL_IP="192.168.3.5"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Warn if running as root; continue but ensure paths use HOME and PWD
if [[ $EUID -eq 0 ]]; then
    warning "Running as root. It's recommended to run as the application user. Proceeding with caution."
fi

# Check if we're in the right directory
if [[ ! -f "manage.py" ]]; then
    error "Please run this script from the weatherapp directory (where manage.py is located)"
fi

log "Starting WeatherApp deployment..."

# =============================================================================
# 1. System Dependencies
# =============================================================================
log "Installing system dependencies..."
sudo apt-get update -y
sudo apt-get install -y python3 python3-pip python3-venv nginx ufw gunicorn

# =============================================================================
# 2. Python Environment Setup
# =============================================================================
log "Detecting Python virtual environment..."

# Prefer an already-activated virtualenv
if [[ -n "${VIRTUAL_ENV:-}" ]]; then
    VENV_PATH="${VIRTUAL_ENV}"
    log "Using currently activated virtualenv: ${VENV_PATH}"
# Then prefer project-local myenv
elif [[ -d "${APP_ROOT}/myenv" && -x "${APP_ROOT}/myenv/bin/python" ]]; then
    VENV_PATH="${APP_ROOT}/myenv"
    log "Detected existing project venv at: ${VENV_PATH}"
# Optional fallback: user's home myenv
elif [[ -d "${HOME}/myenv" && -x "${HOME}/myenv/bin/python" ]]; then
    VENV_PATH="${HOME}/myenv"
    log "Detected existing home venv at: ${VENV_PATH}"
else
    VENV_PATH="${APP_ROOT}/myenv"
    log "No existing venv detected. Creating new venv at: ${VENV_PATH}"
    python3 -m venv "$VENV_PATH"
fi

source "$VENV_PATH/bin/activate"

# Prepare a writable pip cache within the project to avoid permission issues
PIP_CACHE_DIR="${APP_ROOT}/.cache/pip"
mkdir -p "${PIP_CACHE_DIR}"
export PIP_CACHE_DIR
export PIP_DISABLE_PIP_VERSION_CHECK=1

# Bootstrap and robustly upgrade packaging tooling inside the venv
# Ensure pip toolchain is consistent (work around resolvelib vendor conflicts)
"${VENV_PATH}/bin/python" -m ensurepip --upgrade || true
# Remove external resolvelib if present (pip vendors its own)
"${VENV_PATH}/bin/python" -m pip uninstall -y resolvelib || true
# Pin to a stable pip known to work on Python 3.10 and avoid vendor mismatch
"${VENV_PATH}/bin/python" -m pip install --no-cache-dir "pip==24.2" "setuptools>=65" "wheel>=0.38"

# Install requirements
if [[ -f "requirements.txt" ]]; then
    log "Installing Python dependencies..."
    "${VENV_PATH}/bin/python" -m pip install --no-cache-dir -r requirements.txt
else
    warning "requirements.txt not found, installing basic Django dependencies..."
    "${VENV_PATH}/bin/python" -m pip install --no-cache-dir django gunicorn whitenoise dj-database-url python-dotenv
fi

# =============================================================================
# 3. Environment Configuration
# =============================================================================
log "Setting up environment variables..."
cat > "${APP_ROOT}/.env" << 'EOF'
# Django Settings
SECRET_KEY=your-secret-key-change-this-in-production
DEBUG=False
ALLOWED_HOSTS=119.93.148.180,192.168.3.5,localhost,127.0.0.1

# Database (MySQL)
DB_NAME=u520834156_dbweatherApp
DB_USER=u520834156_uWApp2024
DB_PASSWORD=bIxG2Z$In#8
DB_HOST=153.92.15.8
DB_PORT=3306

# Email
EMAIL_HOST=smtp.gmail.com
EMAIL_PORT=587
EMAIL_USE_TLS=True
EMAIL_HOST_USER=rainalertcaps@gmail.com
EMAIL_HOST_PASSWORD=clmz izuz zphx tnrw

# SMS
SMS_API_URL=https://sms.pagenet.info/api/v1/sms/send
SMS_API_KEY=6PLX3NFL2A2FLQ81RI7X6C4PJP68ANLJNYQ7XAR6
SMS_DEVICE_ID=97e8c4360d11fa51

# Subpath hosting
FORCE_SCRIPT_NAME=/weatherapp
STATIC_URL=/weatherapp/static/
MEDIA_URL=/weatherapp/media/
SESSION_COOKIE_PATH=/weatherapp
CSRF_COOKIE_PATH=/weatherapp

# Celery
CELERY_BROKER_URL=redis://localhost:6379/0
CELERY_RESULT_BACKEND=redis://localhost:6379/0
EOF

# =============================================================================
# 4. Django Configuration
# =============================================================================
log "Configuring Django application..."

# Ensure log directory for production logging exists before Django initializes
LOG_BASE_DIR="/var/log/django-apps"
LOG_APP_DIR="${LOG_BASE_DIR}/${APP_NAME}"
log "Provisioning log directory at ${LOG_APP_DIR}..."
sudo mkdir -p "${LOG_APP_DIR}"
sudo chown -R "${APP_USER}:${APP_USER}" "${LOG_APP_DIR}"
sudo chmod -R 755 "${LOG_APP_DIR}"

# Set environment variables for this session
export DJANGO_SETTINGS_MODULE=weatheralert.settings_production
export FORCE_SCRIPT_NAME=/weatherapp
export STATIC_URL=/weatherapp/static/
export MEDIA_URL=/weatherapp/media/

# Collect static files
log "Collecting static files..."
python manage.py collectstatic --noinput --clear

# Create media directory
mkdir -p "${APP_ROOT}/media"

# =============================================================================
# 5. Find Free Port
# =============================================================================
log "Finding available port..."
for port in 8010 8011 8012 8013 8014; do
    if ! ss -ltnp | grep -q ":$port "; then
        APP_PORT=$port
        break
    fi
done

if [[ -z "${APP_PORT:-}" ]]; then
    error "No free ports available in range 8010-8014"
fi

log "Using port: $APP_PORT"

# =============================================================================
# 6. Systemd Service
# =============================================================================
log "Creating systemd service..."
sudo tee "/etc/systemd/system/${SERVICE_NAME}.service" > /dev/null << EOF
[Unit]
Description=WeatherApp Django Application
After=network.target

[Service]
Type=exec
User=${APP_USER}
Group=${APP_USER}
WorkingDirectory=${APP_ROOT}
Environment=PATH=${VENV_PATH}/bin
Environment=DJANGO_SETTINGS_MODULE=weatheralert.settings_production
Environment=FORCE_SCRIPT_NAME=/weatherapp
Environment=STATIC_URL=/weatherapp/static/
Environment=MEDIA_URL=/weatherapp/media/
Environment=SESSION_COOKIE_PATH=/weatherapp
Environment=CSRF_COOKIE_PATH=/weatherapp
ExecStart=${VENV_PATH}/bin/gunicorn --bind 127.0.0.1:${APP_PORT} --workers 3 --timeout 300 weatheralert.wsgi:application
ExecReload=/bin/kill -s HUP \$MAINPID
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# =============================================================================
# 7. Nginx Configuration
# =============================================================================
log "Configuring Nginx reverse proxy..."
sudo tee "/etc/nginx/sites-available/${NGINX_SITE}" > /dev/null << EOF
server {
    listen 80;
    server_name ${PUBLIC_IP} ${LOCAL_IP};

    client_max_body_size 20m;

    # Redirect bare /weatherapp to trailing slash
    location = /weatherapp {
        return 301 /weatherapp/;
    }

    # Serve static files
    location /weatherapp/static/ {
        alias ${APP_ROOT}/staticfiles/;
        access_log off;
        expires 30d;
        add_header Cache-Control "public, max-age=2592000, immutable";
    }

    # Serve media files
    location /weatherapp/media/ {
        alias ${APP_ROOT}/media/;
        access_log off;
        expires 7d;
        add_header Cache-Control "public, max-age=604800";
    }

    # Legacy static/media support
    location /static/ {
        alias ${APP_ROOT}/staticfiles/;
        access_log off;
        expires 30d;
        add_header Cache-Control "public, max-age=2592000, immutable";
    }

    location /media/ {
        alias ${APP_ROOT}/media/;
        access_log off;
        expires 7d;
        add_header Cache-Control "public, max-age=604800";
    }

    # Reverse proxy for Django app
    location /weatherapp/ {
        rewrite ^/weatherapp(/.*)$ \$1 break;
        
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Script-Name /weatherapp;
        proxy_set_header X-Forwarded-Prefix /weatherapp;
        
        proxy_read_timeout 300;
        proxy_connect_timeout 60;
        proxy_redirect off;
        
        proxy_pass http://127.0.0.1:${APP_PORT};
    }

    # Health check
    location = / {
        return 200 "WeatherApp Server OK\\n";
        add_header Content-Type text/plain;
    }
}
EOF

# Enable Nginx site
sudo ln -sf "/etc/nginx/sites-available/${NGINX_SITE}" "/etc/nginx/sites-enabled/${NGINX_SITE}"

# Remove default Nginx site if it exists
sudo rm -f /etc/nginx/sites-enabled/default

# =============================================================================
# 8. Firewall Configuration
# =============================================================================
log "Configuring firewall..."
sudo ufw --force enable
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow from 192.168.3.0/24

# =============================================================================
# 9. Start Services
# =============================================================================
log "Starting services..."

# Reload systemd and start app
sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}"
sudo systemctl start "${SERVICE_NAME}"

# Test Nginx config and reload
sudo nginx -t
sudo systemctl reload nginx

# =============================================================================
# 10. Verification
# =============================================================================
log "Verifying deployment..."

# Wait a moment for services to start
sleep 5

# Check if service is running
if systemctl is-active --quiet "${SERVICE_NAME}"; then
    success "WeatherApp service is running"
else
    error "WeatherApp service failed to start"
fi

# Check if Nginx is running
if systemctl is-active --quiet nginx; then
    success "Nginx is running"
else
    error "Nginx failed to start"
fi

# Test local connectivity
if curl -s -f "http://127.0.0.1:${APP_PORT}/" > /dev/null; then
    success "App responds on localhost:${APP_PORT}"
else
    warning "App may not be responding on localhost:${APP_PORT}"
fi

# =============================================================================
# 11. Final Status
# =============================================================================
echo ""
echo "🎉 Deployment completed successfully!"
echo ""
echo "📋 Service Information:"
echo "   • App URL: http://${PUBLIC_IP}/weatherapp/"
echo "   • Local URL: http://${LOCAL_IP}/weatherapp/"
echo "   • Service: ${SERVICE_NAME}"
echo "   • Port: ${APP_PORT}"
echo "   • User: ${APP_USER}"
echo ""
echo "🔧 Management Commands:"
echo "   • View logs: sudo journalctl -u ${SERVICE_NAME} -f"
echo "   • Restart app: sudo systemctl restart ${SERVICE_NAME}"
echo "   • Stop app: sudo systemctl stop ${SERVICE_NAME}"
echo "   • Nginx status: sudo systemctl status nginx"
echo ""
echo "🌐 Test your deployment:"
echo "   curl -I http://${PUBLIC_IP}/weatherapp/"
echo ""

# Quick test
log "Testing public access..."
if curl -s -f "http://${PUBLIC_IP}/weatherapp/" > /dev/null; then
    success "Public access working! Visit: http://${PUBLIC_IP}/weatherapp/"
else
    warning "Public access test failed. Check firewall and DNS settings."
fi

success "Deployment script completed!"
