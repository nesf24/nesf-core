@echo off
REM ============================================================================
REM NESF Core - Phase 1 Deployment
REM ============================================================================
REM
REM This batch file will deploy Phase 1 completely.
REM It includes authentication and all deployment steps.
REM
REM USAGE: Double-click this file or run: RUN_ME_FIRST.bat
REM
REM ============================================================================

setlocal enabledelayedexpansion

echo.
echo ============================================================
echo    NESF CORE - PHASE 1 COMPLETE DEPLOYMENT
echo ============================================================
echo.

REM Check if PowerShell is available
powershell -NoProfile -Command "Write-Host 'PowerShell OK'" >nul 2>&1
if errorlevel 1 (
    echo ERROR: PowerShell not found
    pause
    exit /b 1
)

REM Run the PowerShell deployment script
echo Running deployment script...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference='Continue'; ^
    cd 'D:\new app\nesf-core'; ^
    if (-not (Test-Path '.\FINAL_DEPLOYMENT_SCRIPT.ps1')) { ^
        Write-Host 'ERROR: FINAL_DEPLOYMENT_SCRIPT.ps1 not found' -ForegroundColor Red; ^
        exit 1 ^
    }; ^
    & '.\FINAL_DEPLOYMENT_SCRIPT.ps1'"

if errorlevel 1 (
    echo.
    echo ERROR: Deployment failed
    echo.
    echo Troubleshooting:
    echo 1. Make sure you have gcloud CLI installed
    echo 2. Run: gcloud auth login
    echo 3. Then run this file again
    echo.
    pause
    exit /b 1
)

echo.
echo ============================================================
echo DEPLOYMENT COMPLETE
echo ============================================================
echo.
echo Next steps:
echo 1. Update Supabase password: https://app.supabase.com
echo 2. Update Cloud SQL password: https://console.cloud.google.com/sql/instances
echo 3. Test login: https://app.nesportsfoundation.in/
echo.
pause
