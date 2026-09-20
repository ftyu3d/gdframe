@echo off
setlocal
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pack_release.ps1"
if errorlevel 1 (
	echo Pack failed.
	exit /b 1
)
