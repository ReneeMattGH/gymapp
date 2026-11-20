@echo off
setlocal
echo ========================================================
echo  Starting CeeBase REST Server for Forma Gym App...
echo ========================================================
echo.

cd /d "D:\Mac\project\NexusDB"

python tools\studio\server.py ceebase.cbdb --port 8080 --host 0.0.0.0
