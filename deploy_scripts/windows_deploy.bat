@echo off
REM =============================================================================
REM Windows Deployment Helper Script for WeatherAlert
REM Deploys to: 119.93.148.180/weatherapp
REM =============================================================================

echo ========================================
echo WeatherAlert Deployment Helper
echo ========================================
echo.

set SERVER_IP=119.93.148.180
set SERVER_USER=root
set PROJECT_DIR=%~dp0..

echo Current directory: %PROJECT_DIR%
echo Server: %SERVER_USER%@%SERVER_IP%
echo.

:menu
echo Select deployment option:
echo 1. Full deployment (first time)
echo 2. Quick update (existing deployment)
echo 3. Transfer files only
echo 4. View logs
echo 5. Restart services
echo 6. Exit
echo.

set /p choice=Enter your choice (1-6): 

if "%choice%"=="1" goto full_deploy
if "%choice%"=="2" goto quick_deploy
if "%choice%"=="3" goto transfer_files
if "%choice%"=="4" goto view_logs
if "%choice%"=="5" goto restart_services
if "%choice%"=="6" goto end

echo Invalid choice, please try again.
goto menu

:full_deploy
echo.
echo === Full Deployment ===
echo This will:
echo   1. Transfer all files to server
echo   2. Install all dependencies
echo   3. Setup services
echo   4. Start application
echo.
set /p confirm=Continue? (y/n): 
if /i not "%confirm%"=="y" goto menu

echo.
echo Transferring files...
scp -r "%PROJECT_DIR%\weatherapp" "%PROJECT_DIR%\weatheralert" "%PROJECT_DIR%\manage.py" "%PROJECT_DIR%\requirements.txt" %SERVER_USER%@%SERVER_IP%:/tmp/weatherapp_deploy/
scp "%PROJECT_DIR%\deploy_scripts\deploy_to_server.sh" %SERVER_USER%@%SERVER_IP%:/tmp/

echo.
echo Connecting to server and deploying...
ssh %SERVER_USER%@%SERVER_IP% "chmod +x /tmp/deploy_to_server.sh && /tmp/deploy_to_server.sh"

echo.
echo Deployment complete!
echo Application available at: http://%SERVER_IP%/weatherapp
pause
goto menu

:quick_deploy
echo.
echo === Quick Update ===
echo This will update code and restart services
echo.
set /p confirm=Continue? (y/n): 
if /i not "%confirm%"=="y" goto menu

echo.
echo Transferring updated files...
scp -r "%PROJECT_DIR%\weatherapp" "%PROJECT_DIR%\weatheralert" "%PROJECT_DIR%\manage.py" "%PROJECT_DIR%\requirements.txt" %SERVER_USER%@%SERVER_IP%:/tmp/weatherapp_update/
scp "%PROJECT_DIR%\deploy_scripts\quick_deploy_to_server.sh" %SERVER_USER%@%SERVER_IP%:/tmp/

echo.
echo Running quick deployment...
ssh %SERVER_USER%@%SERVER_IP% "chmod +x /tmp/quick_deploy_to_server.sh && /tmp/quick_deploy_to_server.sh"

echo.
echo Update complete!
pause
goto menu

:transfer_files
echo.
echo === Transfer Files Only ===
echo.

echo Transferring files to server...
scp -r "%PROJECT_DIR%\weatherapp" "%PROJECT_DIR%\weatheralert" "%PROJECT_DIR%\manage.py" "%PROJECT_DIR%\requirements.txt" %SERVER_USER%@%SERVER_IP%:/tmp/weatherapp_files/
scp -r "%PROJECT_DIR%\deploy_scripts" %SERVER_USER%@%SERVER_IP%:/tmp/weatherapp_files/

echo.
echo Files transferred to /tmp/weatherapp_files/ on server
pause
goto menu

:view_logs
echo.
echo === View Logs ===
echo.
echo Connecting to server to view logs...
ssh %SERVER_USER%@%SERVER_IP% "tail -n 50 /var/log/django-apps/weatherapp/error.log"

echo.
pause
goto menu

:restart_services
echo.
echo === Restart Services ===
echo.
echo Restarting services on server...
ssh %SERVER_USER%@%SERVER_IP% "weatherapp-manage.sh restart"

echo.
echo Services restarted!
pause
goto menu

:end
echo.
echo Goodbye!
exit /b

