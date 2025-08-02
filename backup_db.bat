@echo off
REM Set your database name and backup location
set DB_NAME=weatheralert
set BACKUP_PATH=your_backup.sql
set MYSQL_PATH=C:\xampp\mysql\bin

"%MYSQL_PATH%\mysqldump.exe" -u root -p %DB_NAME% > %BACKUP_PATH%
echo Backup completed and saved to %BACKUP_PATH%
pause