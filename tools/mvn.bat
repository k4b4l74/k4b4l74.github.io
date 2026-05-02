@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0mvn.ps1" %*
exit /b %ERRORLEVEL%
