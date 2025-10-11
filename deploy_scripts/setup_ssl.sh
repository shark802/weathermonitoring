#!/bin/bash

# =============================================================================
# SSL Certificate Setup Script for Django Applications
# Supports Let's Encrypt SSL certificates for multiple domains
# =============================================================================

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SERVER_IP="192.168.3.5"
NGINX_CONF_DIR="/etc/nginx/sites-available"
NGINX_ENABLED_DIR="/etc/nginx/sites-enabled"
CERTBOT_DIR="/etc/letsencrypt"
WEBROOT_DIR="/var/www/html"

# App configurations
declare -A APPS
APPS=(
    ["weatherapp"]="bccweatherapp"
    ["irmss"]="irrms" 
    ["fireguard"]="fireguard"
)

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Function to install Certbot
install_certbot() {
    print_status "Installing Certbot and dependencies..."
    
    # Update package list
    apt update
    
    # Install Certbot and Nginx plugin
    apt install -y certbot python3-certbot-nginx
    
    # Install additional tools
    apt install -y openssl
    
    print_success "Certbot installed successfully"
}

# Function to create webroot directory
create_webroot() {
    print_status "Creating webroot directory for ACME challenges..."
    
    mkdir -p $WEBROOT_DIR
    chown -R www-data:www-data $WEBROOT_DIR
    chmod -R 755 $WEBROOT_DIR
    
    # Create a simple index page
    cat > $WEBROOT_DIR/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Django Applications Server</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .container { max-width: 800px; margin: 0 auto; }
        .app-link { display: inline-block; margin: 10px; padding: 15px 25px; 
                    background: #007bff; color: white; text-decoration: none; 
                    border-radius: 5px; }
        .app-link:hover { background: #0056b3; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Django Applications Server</h1>
        <p>Welcome to the Django applications server. Available applications:</p>
        <a href="/bccweatherapp/" class="app-link">WeatherAlert</a>
        <a href="/irrms/" class="app-link">IRMSS</a>
        <a href="/fireguard/" class="app-link">FireGuard</a>
    </div>
</body>
</html>
EOF

    print_success "Webroot directory created"
}

# Function to create temporary HTTP configuration
create_temp_http_config() {
    print_status "Creating temporary HTTP configuration for certificate validation..."
    
    # Create a temporary nginx configuration for ACME challenges
    cat > /etc/nginx/sites-available/temp-ssl << EOF
# Temporary configuration for SSL certificate validation
server {
    listen 80;
    server_name _;
    
    # ACME challenge location
    location /.well-known/acme-challenge/ {
        root $WEBROOT_DIR;
        try_files \$uri =404;
    }
    
    # Redirect all other requests to HTTPS (will be enabled after SSL setup)
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}
EOF

    # Enable temporary configuration
    ln -sf /etc/nginx/sites-available/temp-ssl $NGINX_ENABLED_DIR/temp-ssl
    
    # Test and reload nginx
    nginx -t
    systemctl reload nginx
    
    print_success "Temporary HTTP configuration created"
}

# Function to obtain SSL certificate for a domain
obtain_certificate() {
    local domain=$1
    local app_name=$2
    
    print_status "Obtaining SSL certificate for $domain (app: $app_name)..."
    
    # Stop the application temporarily
    systemctl stop django-$app_name 2>/dev/null || true
    
    # Obtain certificate using webroot method
    certbot certonly \
        --webroot \
        --webroot-path=$WEBROOT_DIR \
        --email admin@$domain \
        --agree-tos \
        --no-eff-email \
        --domains $domain \
        --non-interactive \
        --expand
    
    if [ $? -eq 0 ]; then
        print_success "SSL certificate obtained for $domain"
        configure_ssl_for_app $domain $app_name
    else
        print_error "Failed to obtain SSL certificate for $domain"
        return 1
    fi
    
    # Start the application
    systemctl start django-$app_name
}

# Function to configure SSL for an application
configure_ssl_for_app() {
    local domain=$1
    local app_name=$2
    local app_url="${APPS[$app_name]}"
    
    print_status "Configuring SSL for $app_name..."
    
    # Create SSL-enabled nginx configuration
    cat > $NGINX_CONF_DIR/$app_name-ssl << EOF
# SSL configuration for $app_name
server {
    listen 80;
    server_name $domain;
    
    # Redirect HTTP to HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $domain;
    
    # SSL certificate configuration
    ssl_certificate $CERTBOT_DIR/live/$domain/fullchain.pem;
    ssl_certificate_key $CERTBOT_DIR/live/$domain/privkey.pem;
    
    # SSL security settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_session_tickets off;
    
    # HSTS
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;
    
    # ACME challenge location
    location /.well-known/acme-challenge/ {
        root $WEBROOT_DIR;
        try_files \$uri =404;
    }
    
    # Static files
    location /static/ {
        alias /opt/django-apps/$app_name/staticfiles/;
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header X-Served-By "$app_name";
    }
    
    # Media files
    location /media/ {
        alias /opt/django-apps/$app_name/media/;
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header X-Served-By "$app_name";
    }
    
    # Main application
    location /$app_url/ {
        proxy_pass http://127.0.0.1:800${app_name: -1}/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffer settings
        proxy_buffering on;
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    # Health check
    location /$app_url/health/ {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
        add_header X-Served-By "$app_name";
    }
}
EOF

    # Enable SSL configuration
    ln -sf $NGINX_CONF_DIR/$app_name-ssl $NGINX_ENABLED_DIR/$app_name-ssl
    
    # Remove HTTP-only configuration if it exists
    rm -f $NGINX_ENABLED_DIR/$app_name
    
    print_success "SSL configuration created for $app_name"
}

# Function to setup automatic certificate renewal
setup_auto_renewal() {
    print_status "Setting up automatic certificate renewal..."
    
    # Test certificate renewal
    certbot renew --dry-run
    
    if [ $? -eq 0 ]; then
        print_success "Certificate renewal test successful"
    else
        print_warning "Certificate renewal test failed"
    fi
    
    # Create renewal script
    cat > /usr/local/bin/ssl-renew.sh << 'EOF'
#!/bin/bash

# SSL Certificate Renewal Script
LOG_FILE="/var/log/ssl-renewal.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> $LOG_FILE
}

# Attempt to renew certificates
if certbot renew --quiet; then
    log_message "SSL certificates renewed successfully"
    
    # Reload nginx to use new certificates
    systemctl reload nginx
    
    # Restart Django applications to pick up new certificates
    systemctl restart django-weatherapp 2>/dev/null || true
    systemctl restart django-irmss 2>/dev/null || true
    systemctl restart django-fireguard 2>/dev/null || true
    
    log_message "Services restarted after certificate renewal"
else
    log_message "SSL certificate renewal failed"
fi
EOF

    chmod +x /usr/local/bin/ssl-renew.sh
    
    # Create cron job for automatic renewal
    cat > /etc/cron.d/ssl-renewal << EOF
# SSL Certificate Renewal
0 2 * * * root /usr/local/bin/ssl-renew.sh
EOF

    print_success "Automatic certificate renewal configured"
}

# Function to create SSL monitoring script
create_ssl_monitoring() {
    print_status "Creating SSL monitoring script..."
    
    cat > /usr/local/bin/monitor-ssl.sh << 'EOF'
#!/bin/bash

# SSL Certificate Monitoring Script
LOG_FILE="/var/log/ssl-monitor.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> $LOG_FILE
}

check_certificate() {
    local domain=$1
    local cert_file="/etc/letsencrypt/live/$domain/fullchain.pem"
    
    if [ ! -f "$cert_file" ]; then
        log_message "❌ Certificate file not found for $domain"
        return 1
    fi
    
    # Get certificate expiration date
    local expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" | cut -d= -f2)
    local expiry_timestamp=$(date -d "$expiry_date" +%s)
    local current_timestamp=$(date +%s)
    local days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))
    
    if [ $days_until_expiry -lt 30 ]; then
        log_message "⚠️ Certificate for $domain expires in $days_until_expiry days"
        
        # Attempt renewal
        if certbot renew --cert-name $domain --quiet; then
            log_message "✅ Certificate renewed for $domain"
            systemctl reload nginx
        else
            log_message "❌ Failed to renew certificate for $domain"
        fi
    else
        log_message "✅ Certificate for $domain is valid for $days_until_expiry days"
    fi
}

# Check all certificates
for cert_dir in /etc/letsencrypt/live/*/; do
    if [ -d "$cert_dir" ]; then
        domain=$(basename "$cert_dir")
        check_certificate "$domain"
    fi
done
EOF

    chmod +x /usr/local/bin/monitor-ssl.sh
    
    # Create cron job for SSL monitoring
    cat > /etc/cron.d/ssl-monitor << EOF
# SSL Certificate Monitoring
0 6 * * * root /usr/local/bin/monitor-ssl.sh
EOF

    print_success "SSL monitoring script created"
}

# Function to create SSL management script
create_ssl_manager() {
    print_status "Creating SSL management script..."
    
    cat > /usr/local/bin/ssl-manager.sh << 'EOF'
#!/bin/bash

# SSL Certificate Management Script

show_help() {
    echo "SSL Certificate Manager"
    echo "Usage: $0 <command> [domain]"
    echo ""
    echo "Commands:"
    echo "  status [domain]     - Show certificate status"
    echo "  renew [domain]      - Renew certificate for domain"
    echo "  list               - List all certificates"
    echo "  test               - Test certificate renewal"
    echo "  revoke <domain>     - Revoke certificate for domain"
    echo "  delete <domain>     - Delete certificate for domain"
}

show_status() {
    local domain=$1
    
    if [ -z "$domain" ]; then
        echo "Available certificates:"
        for cert_dir in /etc/letsencrypt/live/*/; do
            if [ -d "$cert_dir" ]; then
                domain=$(basename "$cert_dir")
                show_status "$domain"
            fi
        done
        return
    fi
    
    local cert_file="/etc/letsencrypt/live/$domain/fullchain.pem"
    
    if [ ! -f "$cert_file" ]; then
        echo "❌ Certificate not found for $domain"
        return 1
    fi
    
    echo "=== Certificate Status for $domain ==="
    
    # Get certificate information
    local subject=$(openssl x509 -subject -noout -in "$cert_file" | cut -d= -f2-)
    local issuer=$(openssl x509 -issuer -noout -in "$cert_file" | cut -d= -f2-)
    local expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" | cut -d= -f2)
    local expiry_timestamp=$(date -d "$expiry_date" +%s)
    local current_timestamp=$(date +%s)
    local days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))
    
    echo "Subject: $subject"
    echo "Issuer: $issuer"
    echo "Expires: $expiry_date"
    echo "Days until expiry: $days_until_expiry"
    
    if [ $days_until_expiry -lt 30 ]; then
        echo "Status: ⚠️ Expires soon"
    else
        echo "Status: ✅ Valid"
    fi
    echo ""
}

renew_certificate() {
    local domain=$1
    
    if [ -z "$domain" ]; then
        echo "Please specify a domain name"
        return 1
    fi
    
    echo "Renewing certificate for $domain..."
    
    if certbot renew --cert-name "$domain" --quiet; then
        echo "✅ Certificate renewed for $domain"
        systemctl reload nginx
    else
        echo "❌ Failed to renew certificate for $domain"
        return 1
    fi
}

list_certificates() {
    echo "=== SSL Certificates ==="
    for cert_dir in /etc/letsencrypt/live/*/; do
        if [ -d "$cert_dir" ]; then
            domain=$(basename "$cert_dir")
            echo "Domain: $domain"
            show_status "$domain"
        fi
    done
}

test_renewal() {
    echo "Testing certificate renewal..."
    if certbot renew --dry-run; then
        echo "✅ Certificate renewal test successful"
    else
        echo "❌ Certificate renewal test failed"
        return 1
    fi
}

revoke_certificate() {
    local domain=$1
    
    if [ -z "$domain" ]; then
        echo "Please specify a domain name"
        return 1
    fi
    
    echo "Revoking certificate for $domain..."
    read -p "Are you sure you want to revoke the certificate for $domain? (yes/no): " confirm
    
    if [ "$confirm" = "yes" ]; then
        certbot revoke --cert-path "/etc/letsencrypt/live/$domain/fullchain.pem"
        echo "Certificate revoked for $domain"
    else
        echo "Certificate revocation cancelled"
    fi
}

delete_certificate() {
    local domain=$1
    
    if [ -z "$domain" ]; then
        echo "Please specify a domain name"
        return 1
    fi
    
    echo "Deleting certificate for $domain..."
    read -p "Are you sure you want to delete the certificate for $domain? (yes/no): " confirm
    
    if [ "$confirm" = "yes" ]; then
        certbot delete --cert-name "$domain"
        echo "Certificate deleted for $domain"
    else
        echo "Certificate deletion cancelled"
    fi
}

# Main script logic
if [ $# -lt 1 ]; then
    show_help
    exit 1
fi

command=$1
domain=$2

case $command in
    "status")
        show_status $domain
        ;;
    "renew")
        renew_certificate $domain
        ;;
    "list")
        list_certificates
        ;;
    "test")
        test_renewal
        ;;
    "revoke")
        revoke_certificate $domain
        ;;
    "delete")
        delete_certificate $domain
        ;;
    *)
        echo "Unknown command: $command"
        show_help
        ;;
esac
EOF

    chmod +x /usr/local/bin/ssl-manager.sh
    
    print_success "SSL management script created"
}

# Function to setup SSL for local development
setup_local_ssl() {
    print_status "Setting up self-signed certificates for local development..."
    
    # Create directory for self-signed certificates
    mkdir -p /etc/ssl/local
    
    # Generate self-signed certificate
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/local/local.key \
        -out /etc/ssl/local/local.crt \
        -subj "/C=PH/ST=Philippines/L=Local/O=Development/OU=IT/CN=$SERVER_IP"
    
    # Create local SSL configuration
    cat > $NGINX_CONF_DIR/local-ssl << EOF
# Local SSL configuration for development
server {
    listen 443 ssl http2;
    server_name $SERVER_IP localhost;
    
    # Self-signed certificate
    ssl_certificate /etc/ssl/local/local.crt;
    ssl_certificate_key /etc/ssl/local/local.key;
    
    # SSL settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512;
    ssl_prefer_server_ciphers off;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    
    # Include the same location blocks as the main configuration
    # This would be customized based on your specific needs
}
EOF

    print_success "Local SSL setup completed"
    print_warning "Self-signed certificates will show security warnings in browsers"
}

# Main function
main() {
    print_status "Starting SSL setup for Django applications..."
    
    check_root
    install_certbot
    create_webroot
    create_temp_http_config
    setup_auto_renewal
    create_ssl_monitoring
    create_ssl_manager
    setup_local_ssl
    
    print_success "SSL setup completed successfully!"
    print_status ""
    print_status "To obtain SSL certificates for your domains:"
    print_status "1. Ensure your domains point to $SERVER_IP"
    print_status "2. Run: certbot certonly --webroot -w $WEBROOT_DIR -d yourdomain.com"
    print_status "3. Configure your applications to use HTTPS"
    print_status ""
    print_status "Use the following commands to manage SSL certificates:"
    print_status "  /usr/local/bin/ssl-manager.sh status"
    print_status "  /usr/local/bin/ssl-manager.sh list"
    print_status "  /usr/local/bin/ssl-manager.sh renew"
    print_status ""
    print_warning "For local development, self-signed certificates are available"
    print_warning "For production, you need valid domain names pointing to $SERVER_IP"
}

# Run main function
main "$@"
