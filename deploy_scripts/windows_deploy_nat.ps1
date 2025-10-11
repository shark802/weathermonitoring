# =============================================================================
# WeatherAlert - Windows to Ubuntu NAT Deployment Script
# Automatically deploys from Windows to Ubuntu server behind router
# 
# Server Setup:
#   - Internal IP: 192.168.3.5
#   - Gateway/Router: 192.168.3.1
#   - Public IP: 119.93.148.180 (on router)
#   - User: bccbsis-py-admin
# =============================================================================

# Configuration
$SERVER_INTERNAL_IP = "192.168.3.5"
$SERVER_PUBLIC_IP = "119.93.148.180"
$GATEWAY_IP = "192.168.3.1"
$SERVER_USER = "bccbsis-py-admin"
$PROJECT_DIR = Split-Path -Parent $PSScriptRoot

# Colors
$ColorInfo = "Cyan"
$ColorSuccess = "Green"
$ColorWarning = "Yellow"
$ColorError = "Red"

function Show-Header {
    param([string]$Title)
    Write-Host ""
    Write-Host "========================================" -ForegroundColor $ColorInfo
    Write-Host $Title -ForegroundColor $ColorInfo
    Write-Host "========================================" -ForegroundColor $ColorInfo
    Write-Host ""
}

function Show-Status {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor $ColorInfo
}

function Show-Success {
    param([string]$Message)
    Write-Host "[✓] $Message" -ForegroundColor $ColorSuccess
}

function Show-Warning {
    param([string]$Message)
    Write-Host "[⚠] $Message" -ForegroundColor $ColorWarning
}

function Show-Error {
    param([string]$Message)
    Write-Host "[✗] $Message" -ForegroundColor $ColorError
}

function Test-ServerConnection {
    Show-Status "Testing connection to Ubuntu server..."
    
    try {
        $result = Test-NetConnection -ComputerName $SERVER_INTERNAL_IP -Port 22 -WarningAction SilentlyContinue
        if ($result.TcpTestSucceeded) {
            Show-Success "Can reach server at $SERVER_INTERNAL_IP"
            return $true
        } else {
            Show-Error "Cannot reach server at $SERVER_INTERNAL_IP"
            Show-Warning "Make sure you're on the same network as the server"
            return $false
        }
    } catch {
        Show-Error "Connection test failed: $_"
        return $false
    }
}

function Deploy-ToServer {
    Show-Header "Automated NAT Deployment"
    
    Write-Host "Configuration:" -ForegroundColor $ColorInfo
    Write-Host "  Server (Internal): $SERVER_INTERNAL_IP" -ForegroundColor White
    Write-Host "  Server (Public):   $SERVER_PUBLIC_IP" -ForegroundColor White
    Write-Host "  Gateway/Router:    $GATEWAY_IP" -ForegroundColor White
    Write-Host "  Project:           $PROJECT_DIR" -ForegroundColor White
    Write-Host ""
    
    # Test connection
    if (-not (Test-ServerConnection)) {
        return
    }
    
    $confirm = Read-Host "Start deployment? (y/n)"
    if ($confirm -ne "y") {
        Write-Host "Deployment cancelled" -ForegroundColor $ColorWarning
        return
    }
    
    # Step 1: Transfer deployment script
    Show-Status "Step 1/3: Transferring deployment script..."
    try {
        scp "$PROJECT_DIR\deploy_scripts\auto_deploy_nat.sh" "${SERVER_USER}@${SERVER_INTERNAL_IP}:/tmp/"
        if ($LASTEXITCODE -eq 0) {
            Show-Success "Deployment script transferred"
        } else {
            Show-Error "Failed to transfer deployment script"
            return
        }
    } catch {
        Show-Error "Transfer failed: $_"
        return
    }
    
    # Step 2: Transfer application files
    Show-Status "Step 2/3: Transferring application files..."
    Show-Status "This may take a few minutes..."
    
    try {
        # Create temp directory on server
        ssh "${SERVER_USER}@${SERVER_INTERNAL_IP}" "mkdir -p /tmp/weatherapp_deploy"
        
        # Transfer main directories
        Show-Status "Transferring weatherapp..."
        scp -r "$PROJECT_DIR\weatherapp" "${SERVER_USER}@${SERVER_INTERNAL_IP}:/tmp/weatherapp_deploy/"
        
        Show-Status "Transferring weatheralert..."
        scp -r "$PROJECT_DIR\weatheralert" "${SERVER_USER}@${SERVER_INTERNAL_IP}:/tmp/weatherapp_deploy/"
        
        # Transfer key files
        Show-Status "Transferring configuration files..."
        scp "$PROJECT_DIR\manage.py" "${SERVER_USER}@${SERVER_INTERNAL_IP}:/tmp/weatherapp_deploy/"
        scp "$PROJECT_DIR\requirements.txt" "${SERVER_USER}@${SERVER_INTERNAL_IP}:/tmp/weatherapp_deploy/"
        
        if ($LASTEXITCODE -eq 0) {
            Show-Success "Application files transferred"
        } else {
            Show-Error "Failed to transfer some files"
            return
        }
    } catch {
        Show-Error "Transfer failed: $_"
        return
    }
    
    # Step 3: Run deployment
    Show-Status "Step 3/3: Running automated deployment on server..."
    Show-Status "This will take 10-20 minutes. Please wait..."
    Write-Host ""
    
    try {
        # Make script executable and run
        ssh "${SERVER_USER}@${SERVER_INTERNAL_IP}" "chmod +x /tmp/auto_deploy_nat.sh && sudo /tmp/auto_deploy_nat.sh"
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host ""
            Show-Success "Deployment completed successfully!"
            
            # Show access information
            Show-Header "Access Information"
            
            Write-Host "Your WeatherAlert application is now deployed!" -ForegroundColor $ColorSuccess
            Write-Host ""
            Write-Host "Access URLs:" -ForegroundColor $ColorInfo
            Write-Host "  From local network: http://$SERVER_INTERNAL_IP/weatherapp" -ForegroundColor White
            Write-Host "  From internet:      http://$SERVER_PUBLIC_IP/weatherapp" -ForegroundColor White
            Write-Host "                      (requires port forwarding)" -ForegroundColor $ColorWarning
            Write-Host ""
            Write-Host "Port Forwarding Setup:" -ForegroundColor $ColorInfo
            Write-Host "  1. Open router admin: http://$GATEWAY_IP" -ForegroundColor White
            Write-Host "  2. Find 'Port Forwarding' or 'Virtual Server'" -ForegroundColor White
            Write-Host "  3. Forward port 80 to $SERVER_INTERNAL_IP:80" -ForegroundColor White
            Write-Host "  4. Forward port 443 to $SERVER_INTERNAL_IP:443" -ForegroundColor White
            Write-Host ""
            Write-Host "For detailed instructions, run on server:" -ForegroundColor $ColorInfo
            Write-Host "  sudo /usr/local/bin/check-port-forwarding.sh" -ForegroundColor White
            Write-Host ""
            
        } else {
            Show-Error "Deployment failed"
            Show-Status "Check logs on server for details"
        }
    } catch {
        Show-Error "Deployment failed: $_"
        return
    }
}

function Update-Application {
    Show-Header "Quick Application Update"
    
    Show-Status "Testing connection..."
    if (-not (Test-ServerConnection)) {
        return
    }
    
    $confirm = Read-Host "Update application? (y/n)"
    if ($confirm -ne "y") {
        return
    }
    
    Show-Status "Transferring updated files..."
    
    try {
        # Transfer updated application code
        scp -r "$PROJECT_DIR\weatherapp" "${SERVER_USER}@${SERVER_INTERNAL_IP}:/tmp/weatherapp_update/"
        scp -r "$PROJECT_DIR\weatheralert" "${SERVER_USER}@${SERVER_INTERNAL_IP}:/tmp/weatherapp_update/"
        scp "$PROJECT_DIR\requirements.txt" "${SERVER_USER}@${SERVER_INTERNAL_IP}:/tmp/weatherapp_update/"
        
        Show-Status "Running update on server..."
        
        # Run update command
        $updateScript = @"
sudo systemctl stop django-weatherapp celery-weatherapp celerybeat-weatherapp
sudo cp -r /tmp/weatherapp_update/* /opt/django-apps/weatherapp/
cd /opt/django-apps/weatherapp
sudo -u django-weatherapp /opt/django-apps/weatherapp/venv/bin/pip install -r requirements.txt
sudo -u django-weatherapp /opt/django-apps/weatherapp/venv/bin/python manage.py migrate --noinput
sudo -u django-weatherapp /opt/django-apps/weatherapp/venv/bin/python manage.py collectstatic --noinput
sudo chown -R django-weatherapp:django-weatherapp /opt/django-apps/weatherapp
sudo systemctl start django-weatherapp celery-weatherapp celerybeat-weatherapp
"@
        
        $updateScript | ssh "${SERVER_USER}@${SERVER_INTERNAL_IP}" "bash"
        
        if ($LASTEXITCODE -eq 0) {
            Show-Success "Application updated successfully!"
        } else {
            Show-Error "Update failed"
        }
    } catch {
        Show-Error "Update failed: $_"
    }
}

function Show-ServiceStatus {
    Show-Header "Service Status"
    
    Show-Status "Connecting to server..."
    
    ssh "${SERVER_USER}@${SERVER_INTERNAL_IP}" "weatherapp-manage.sh status"
}

function Show-Logs {
    Show-Header "Application Logs"
    
    Show-Status "Fetching logs from server..."
    Write-Host ""
    
    Write-Host "--- Django Error Log ---" -ForegroundColor $ColorWarning
    ssh "${SERVER_USER}@${SERVER_INTERNAL_IP}" "sudo tail -n 30 /var/log/django-apps/weatherapp/error.log 2>/dev/null || echo 'No logs yet'"
    
    Write-Host ""
    Write-Host "--- Celery Log ---" -ForegroundColor $ColorWarning
    ssh "${SERVER_USER}@${SERVER_INTERNAL_IP}" "sudo tail -n 20 /var/log/django-apps/weatherapp/celery.log 2>/dev/null || echo 'No logs yet'"
    
    Write-Host ""
    Read-Host "Press Enter to continue"
}

function Restart-Services {
    Show-Header "Restart Services"
    
    $confirm = Read-Host "Restart all services? (y/n)"
    if ($confirm -ne "y") {
        return
    }
    
    Show-Status "Restarting services..."
    ssh "${SERVER_USER}@${SERVER_INTERNAL_IP}" "sudo weatherapp-manage.sh restart"
    
    Show-Success "Services restarted"
}

function Test-Application {
    Show-Header "Test Application"
    
    Show-Status "Testing local access..."
    
    try {
        $response = Invoke-WebRequest -Uri "http://$SERVER_INTERNAL_IP/weatherapp/" -UseBasicParsing -TimeoutSec 10 -ErrorAction SilentlyContinue
        if ($response.StatusCode -eq 200 -or $response.StatusCode -eq 302) {
            Show-Success "Application responding (HTTP $($response.StatusCode))"
        } else {
            Show-Warning "Unexpected response: $($response.StatusCode)"
        }
    } catch {
        Show-Error "Application not responding: $_"
    }
    
    Write-Host ""
    Show-Status "Testing public access (requires port forwarding)..."
    
    try {
        $response = Invoke-WebRequest -Uri "http://$SERVER_PUBLIC_IP/weatherapp/" -UseBasicParsing -TimeoutSec 10 -ErrorAction SilentlyContinue
        if ($response.StatusCode -eq 200 -or $response.StatusCode -eq 302) {
            Show-Success "Public access working! Port forwarding is configured."
        } else {
            Show-Warning "Unexpected response: $($response.StatusCode)"
        }
    } catch {
        Show-Warning "Public access not working. Port forwarding may not be configured."
        Show-Status "To configure: http://$GATEWAY_IP"
    }
    
    Write-Host ""
    Read-Host "Press Enter to continue"
}

function Show-PortForwardingInstructions {
    Show-Header "Port Forwarding Setup Instructions"
    
    Write-Host "Your server is behind a router at $GATEWAY_IP" -ForegroundColor $ColorInfo
    Write-Host ""
    Write-Host "To make it accessible from the internet:" -ForegroundColor $ColorInfo
    Write-Host ""
    Write-Host "Step 1: Access Router" -ForegroundColor $ColorSuccess
    Write-Host "  • Open browser: http://$GATEWAY_IP" -ForegroundColor White
    Write-Host "  • Login with router credentials" -ForegroundColor White
    Write-Host ""
    Write-Host "Step 2: Find Port Forwarding" -ForegroundColor $ColorSuccess
    Write-Host "  Look for one of these menu items:" -ForegroundColor White
    Write-Host "  • Port Forwarding" -ForegroundColor White
    Write-Host "  • Virtual Server" -ForegroundColor White
    Write-Host "  • NAT Forwarding" -ForegroundColor White
    Write-Host "  • Applications & Gaming" -ForegroundColor White
    Write-Host ""
    Write-Host "Step 3: Create Rules" -ForegroundColor $ColorSuccess
    Write-Host ""
    Write-Host "  Rule 1 - HTTP:" -ForegroundColor White
    Write-Host "    External Port:  80" -ForegroundColor White
    Write-Host "    Internal IP:    $SERVER_INTERNAL_IP" -ForegroundColor Yellow
    Write-Host "    Internal Port:  80" -ForegroundColor White
    Write-Host "    Protocol:       TCP" -ForegroundColor White
    Write-Host ""
    Write-Host "  Rule 2 - HTTPS:" -ForegroundColor White
    Write-Host "    External Port:  443" -ForegroundColor White
    Write-Host "    Internal IP:    $SERVER_INTERNAL_IP" -ForegroundColor Yellow
    Write-Host "    Internal Port:  443" -ForegroundColor White
    Write-Host "    Protocol:       TCP" -ForegroundColor White
    Write-Host ""
    Write-Host "Step 4: Save & Test" -ForegroundColor $ColorSuccess
    Write-Host "  • Save configuration" -ForegroundColor White
    Write-Host "  • Reboot router if needed" -ForegroundColor White
    Write-Host "  • Test: http://$SERVER_PUBLIC_IP/weatherapp" -ForegroundColor White
    Write-Host ""
    
    Read-Host "Press Enter to continue"
}

function Connect-SSH {
    Show-Header "SSH to Server"
    
    Show-Status "Connecting to $SERVER_INTERNAL_IP..."
    ssh "${SERVER_USER}@${SERVER_INTERNAL_IP}"
}

function Show-Menu {
    Clear-Host
    Show-Header "WeatherAlert - NAT Deployment Manager"
    
    Write-Host "Server Configuration:" -ForegroundColor $ColorInfo
    Write-Host "  Internal IP: $SERVER_INTERNAL_IP" -ForegroundColor White
    Write-Host "  Public IP:   $SERVER_PUBLIC_IP" -ForegroundColor White
    Write-Host "  Gateway:     $GATEWAY_IP" -ForegroundColor White
    Write-Host ""
    
    Write-Host "1. " -NoNewline -ForegroundColor White
    Write-Host "Full Deployment" -ForegroundColor $ColorSuccess -NoNewline
    Write-Host " (First time - 10-20 min)"
    
    Write-Host "2. " -NoNewline -ForegroundColor White
    Write-Host "Quick Update" -ForegroundColor $ColorSuccess -NoNewline
    Write-Host " (Update code - 2-5 min)"
    
    Write-Host "3. " -NoNewline -ForegroundColor White
    Write-Host "Check Status" -ForegroundColor $ColorInfo
    
    Write-Host "4. " -NoNewline -ForegroundColor White
    Write-Host "View Logs" -ForegroundColor $ColorInfo
    
    Write-Host "5. " -NoNewline -ForegroundColor White
    Write-Host "Restart Services" -ForegroundColor $ColorWarning
    
    Write-Host "6. " -NoNewline -ForegroundColor White
    Write-Host "Test Application" -ForegroundColor $ColorInfo
    
    Write-Host "7. " -NoNewline -ForegroundColor White
    Write-Host "Port Forwarding Instructions" -ForegroundColor $ColorWarning
    
    Write-Host "8. " -NoNewline -ForegroundColor White
    Write-Host "SSH to Server" -ForegroundColor $ColorInfo
    
    Write-Host "9. " -NoNewline -ForegroundColor White
    Write-Host "Exit" -ForegroundColor $ColorError
    
    Write-Host ""
}

# Main loop
while ($true) {
    Show-Menu
    $choice = Read-Host "Select option (1-9)"
    
    switch ($choice) {
        "1" { Deploy-ToServer }
        "2" { Update-Application }
        "3" { Show-ServiceStatus }
        "4" { Show-Logs }
        "5" { Restart-Services }
        "6" { Test-Application }
        "7" { Show-PortForwardingInstructions }
        "8" { Connect-SSH }
        "9" {
            Write-Host ""
            Write-Host "Goodbye!" -ForegroundColor $ColorSuccess
            exit
        }
        default {
            Show-Warning "Invalid choice. Please select 1-9."
            Start-Sleep -Seconds 2
        }
    }
}

