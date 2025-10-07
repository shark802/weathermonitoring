@echo off
echo Making deployment scripts executable...

REM Note: This is for Windows. On Linux/Ubuntu, use: chmod +x deploy_scripts/*.sh

echo.
echo The following scripts are ready for deployment:
echo   - setup_environment.sh
echo   - deploy_app.sh
echo   - add_new_app.sh
echo   - monitor_apps.sh
echo   - quick_deploy.sh
echo.
echo To use these scripts on Ubuntu server:
echo   1. Copy the entire project to your Ubuntu server
echo   2. Run: chmod +x deploy_scripts/*.sh
echo   3. Run: ./deploy_scripts/quick_deploy.sh
echo.
pause
