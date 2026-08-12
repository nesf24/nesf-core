@echo off
setlocal enabledelayedexpansion

echo ==========================================
echo NESF Core: Developer Environment Setup
echo ==========================================
echo.

REM Step 1: Dependencies
echo [*] Installing API dependencies...
cd api
call npm install
if errorlevel 1 goto :error
cd ..

echo [*] Installing Flutter dependencies...
cd app
call flutter pub get
if errorlevel 1 goto :error
cd ..

REM Step 2: Database
echo [*] Starting Postgres via Docker Compose...
call docker-compose up -d
if errorlevel 1 goto :error
timeout /t 3 /nobreak

REM Step 3: Database setup
echo [*] Migrating database schema...
cd api
set DATABASE_URL=postgres://nesf_core:dev-password-local@localhost:5432/nesf_core_dev
call npm run migrate
if errorlevel 1 goto :error

echo [*] Seeding database with initial data...
call npm run seed
if errorlevel 1 goto :error

REM Step 4: Summary
echo.
echo [OK] Setup complete!
echo.
echo Next steps:
echo.
echo 1. Start the API (in one terminal^):
echo    cd api
echo    npm start
echo.
echo 2. Start the Flutter app (in another terminal^):
echo    cd app
echo    flutter run --dart-define=API_BASE=http://10.0.2.2:4000  # Android emulator
echo    flutter run --dart-define=API_BASE=http://localhost:4000 # Windows/Web
echo.
echo 3. Run tests:
echo    cd api
echo    npm run test:e2e  # End-to-end tests
echo    npm run test:media # Media privacy tests
echo.
echo Admin credentials (from seed^):
echo   Email: biki@nesportsfoundation.in
echo   Password: ChangeMe@123
echo.
goto :end

:error
echo.
echo [ERROR] Setup failed. Check the error message above.
echo.
exit /b 1

:end
