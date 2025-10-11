# =============================================================================
# PowerShell Deployment Script for WeatherAlert
# Deploys to: 119.93.148.180/weatherapp
# =============================================================================

# Configuration
$SERVER_IP = "119.93.148.180"
$SERVER_USER = "root"
$PROJECT_DIR = Split-Path -Parent $PSScriptRoot

Write-Host "========================================" -ForegroundColor Blue
Write-Host "WeatherAlert Deployment Helper" -ForegroundColor Blue
Write-Host "========================================" -ForegroundColor Blue
Write-Host ""
Write-Host "Server: $SERVER_USER@$SERVER_IP" -ForegroundColor Cyan
Write-Host "Project: $PROJECT_DIR" -ForegroundColor Cyan
Write-Host ""

function Show-Menu {
    Write-Host "Select deployment option:" -ForegroundColor Yellow
    Write-Host "1. Full deployment (first time)"
    Write-Host "2. Quick update (existing deployment)"
    Write-Host "3. Transfer files only"
    Write-Host "4. View logs"
    Write-Host "5. Restart services"
    Write-Host "6. Check service status"
    Write-Host "7. SSH to server"
    Write-Host "8. Exit"
    Write-Host ""
}

function Full-Deployment {
    Write-Host ""
    Write-Host "=== Full Deployment ===" -ForegroundColor Green
    Write-Host "This will:"
    Write-Host "  1. Transfer all files to server"
    Write-Host "  2. Install all dependencies"
    Write-Host "  3. Setup services"
    Write-Host "  4. Start application"
    Write-Host ""
    
    $confirm = Read-Host "Continue? (y/n)"
    if ($confirm -ne "y") { return }
    
    Write-Host ""
    Write-Host "Creating temporary directory on server..." -ForegroundColor Cyan
    ssh "$SERVER_USER@$SERVER_IP" "mkdir -p /tmp/weatherapp_deploy"
    
    Write-Host "Transferring files..." -ForegroundColor Cyan
    scp -r "$PROJECT_DIR\weatherapp" "$SERVER_USER@${SERVER_IP}:/tmp/weatherapp_deploy/"
    scp -r "$PROJECT_DIR\weatheralert" "$SERVER_USER@${SERVER_IP}:/tmp/weatherapp_deploy/"
    scp "$PROJECT_DIR\manage.py" "$SERVER_USER@${SERVER_IP}:/tmp/weatherapp_deploy/"
    scp "$PROJECT_DIR\requirements.txt" "$SERVER_USER@${SERVER_IP}:/tmp/weatherapp_deploy/"
    scp "$PROJECT_DIR\deploy_scripts\deploy_to_server.sh" "$SERVER_USER@${SERVER_IP}:/tmp/"
    
    Write-Host ""
    Write-Host "Connecting to server and deploying..." -ForegroundColor Cyan
    ssh "$SERVER_USER@$SERVER_IP" "cd /tmp/weatherapp_deploy && chmod +x /tmp/deploy_to_server.sh && /tmp/deploy_to_server.sh"
    
    Write-Host ""
    Write-Host "Deployment complete!" -ForegroundColor Green
    Write-Host "Application available at: http://$SERVER_IP/weatherapp" -ForegroundColor Green
    Write-Host ""
    
    Read-Host "Press Enter to continue"
}

function Quick-Update {
    Write-Host ""
    Write-Host "=== Quick Update ===" -ForegroundColor Green
    Write-Host "This will update code and restart services" -ForegroundColor Yellow
    Write-Host ""
    
    $confirm = Read-Host "Continue? (y/n)"
    if ($confirm -ne "y") { return }
    
    Write-Host ""
    Write-Host "Transferring updated files..." -ForegroundColor Cyan
    ssh "$SERVER_USER@$SERVER_IP" "mkdir -p /tmp/weatherapp_update"
    
    scp -r "$PROJECT_DIR\weatherapp" "$SERVER_USER@${SERVER_IP}:/tmp/weatherapp_update/"
    scp -r "$PROJECT_DIR\weatheralert" "$SERVER_USER@${SERVER_IP}:/tmp/weatherapp_update/"
    scp "$PROJECT_DIR\manage.py" "$SERVER_USER@${SERVER_IP}:/tmp/weatherapp_update/"
    scp "$PROJECT_DIR\requirements.txt" "$SERVER_USER@${SERVER_IP}:/tmp/weatherapp_update/"
    scp "$PROJECT_DIR\deploy_scripts\quick_deploy_to_server.sh" "$SERVER_USER@${SERVER_IP}:/tmp/"
    
    Write-Host ""
    Write-Host "Running quick deployment..." -ForegroundColor Cyan
    ssh "$SERVER_USER@$SERVER_IP" "chmod +x /tmp/quick_deploy_to_server.sh && /tmp/quick_deploy_to_server.sh"
    
    Write-Host ""
    Write-Host "Update complete!" -ForegroundColor Green
    Write-Host ""
    
    Read-Host "Press Enter to continue"
}

function Transfer-Files {
    Write-Host ""
    Write-Host "=== Transfer Files Only ===" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "Creating temporary directory on server..." -ForegroundColor Cyan
    ssh "$SERVER_USER@$SERVER_IP" "mkdir -p /tmp/weatherapp_files"
    
    Write-Host "Transferring files..." -ForegroundColor Cyan
    scp -r "$PROJECT_DIR\weatherapp" "$SERVER_USER@${SERVER_IP}:/tmp/weatherapp_files/"
    scp -r "$PROJECT_DIR\weatheralert" "$SERVER_USER@${SERVER_IP}:/tmp/weatherapp_files/"
    scp -r "$PROJECT_DIR\deploy_scripts" "$SERVER_USER@${SERVER_IP}:/tmp/weatherapp_files/"
    scp "$PROJECT_DIR\manage.py" "$SERVER_USER@${SERVER_IP}:/tmp/weatherapp_files/"
    scp "$PROJECT_DIR\requirements.txt" "$SERVER_USER@${SERVER_IP}:/tmp/weatherapp_files/"
    
    Write-Host ""
    Write-Host "Files transferred to /tmp/weatherapp_files/ on server" -ForegroundColor Green
    Write-Host ""
    
    Read-Host "Press Enter to continue"
}

function View-Logs {
    Write-Host ""
    Write-Host "=== View Logs ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "Fetching logs from server..." -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "--- Django Error Log ---" -ForegroundColor Yellow
    ssh "$SERVER_USER@$SERVER_IP" "tail -n 30 /var/log/django-apps/weatherapp/error.log 2>/dev/null || echo 'Log file not found'"
    
    Write-Host ""
    Write-Host "--- Celery Log ---" -ForegroundColor Yellow
    ssh "$SERVER_USER@$SERVER_IP" "tail -n 20 /var/log/django-apps/weatherapp/celery.log 2>/dev/null || echo 'Log file not found'"
    
    Write-Host ""
    Read-Host "Press Enter to continue"
}

function Restart-Services {
    Write-Host ""
    Write-Host "=== Restart Services ===" -ForegroundColor Green
    Write-Host ""
    
    $confirm = Read-Host "Restart all services? (y/n)"
    if ($confirm -ne "y") { return }
    
    Write-Host "Restarting services on server..." -ForegroundColor Cyan
    ssh "$SERVER_USER@$SERVER_IP" "systemctl restart django-weatherapp celery-weatherapp celerybeat-weatherapp nginx"
    
    Write-Host ""
    Write-Host "Services restarted!" -ForegroundColor Green
    Write-Host ""
    
    Read-Host "Press Enter to continue"
}

function Check-Status {
    Write-Host ""
    Write-Host "=== Service Status ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "Checking services on server..." -ForegroundColor Cyan
    Write-Host ""
    
    ssh "$SERVER_USER@$SERVER_IP" "systemctl is-active django-weatherapp && echo 'Django: Running' || echo 'Django: Stopped'"
    ssh "$SERVER_USER@$SERVER_IP" "systemctl is-active celery-weatherapp && echo 'Celery: Running' || echo 'Celery: Stopped'"
    ssh "$SERVER_USER@$SERVER_IP" "systemctl is-active celerybeat-weatherapp && echo 'Celery Beat: Running' || echo 'Celery Beat: Stopped'"
    ssh "$SERVER_USER@$SERVER_IP" "systemctl is-active nginx && echo 'Nginx: Running' || echo 'Nginx: Stopped'"
    ssh "$SERVER_USER@$SERVER_IP" "systemctl is-active redis-server && echo 'Redis: Running' || echo 'Redis: Stopped'"
    
    Write-Host ""
    Write-Host "Testing application..." -ForegroundColor Cyan
    $response = Invoke-WebRequest -Uri "http://$SERVER_IP/weatherapp/" -UseBasicParsing -TimeoutSec 10 -ErrorAction SilentlyContinue
    if ($response.StatusCode -eq 200 -or $response.StatusCode -eq 302) {
        Write-Host "Application: Responding (HTTP $($response.StatusCode))" -ForegroundColor Green
    } else {
        Write-Host "Application: Not responding" -ForegroundColor Red
    }
    
    Write-Host ""
    Read-Host "Press Enter to continue"
}

function SSH-Connect {
    Write-Host ""
    Write-Host "Connecting to server..." -ForegroundColor Cyan
    ssh "$SERVER_USER@$SERVER_IP"
}

# Main loop
while ($true) {
    Clear-Host
    Write-Host "========================================" -ForegroundColor Blue
    Write-Host "WeatherAlert Deployment Helper" -ForegroundColor Blue
    Write-Host "========================================" -ForegroundColor Blue
    Write-Host ""
    Write-Host "Server: $SERVER_USER@$SERVER_IP" -ForegroundColor Cyan
    Write-Host "URL: http://$SERVER_IP/weatherapp" -ForegroundColor Cyan
    Write-Host ""
    
    Show-Menu
    
    $choice = Read-Host "Enter your choice (1-8)"
    
    switch ($choice) {
        "1" { Full-Deployment }
        "2" { Quick-Update }
        "3" { Transfer-Files }
        "4" { View-Logs }
        "5" { Restart-Services }
        "6" { Check-Status }
        "7" { SSH-Connect }
        "8" { 
            Write-Host ""
            Write-Host "Goodbye!" -ForegroundColor Green
            exit 
        }
        default { 
            Write-Host "Invalid choice, please try again." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
}

