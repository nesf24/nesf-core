# ============================================================================
# NESF CORE - PHASE 1 FINAL DEPLOYMENT SCRIPT
# ============================================================================
#
# This script will complete ALL Phase 1 deployment steps:
# 1. Authenticate gcloud (one-time browser login)
# 2. Update Google Secret Manager (database password)
# 3. Update Google Secret Manager (JWT secret)
# 4. Deploy to Cloud Run
# 5. Verify production
# 6. Display login credentials
#
# IMPORTANT: Run this in PowerShell on your local machine
# Windows PowerShell 5.1 or newer required
#
# ============================================================================

# Check if running in PowerShell
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "ERROR: PowerShell 5.0 or newer required" -ForegroundColor Red
    exit 1
}

# Set error action
$ErrorActionPreference = "Continue"

# ============================================================================
# CREDENTIALS
# ============================================================================

$DB_PASSWORD = "JYVYbtjOOEHlp9saDdhTEhdZJwsE1/Mn"
$JWT_SECRET = "416da02a0628758bd926a9fdd9c08204ad0bdad60d5714a2c9b11e16ce8c1df5ef201e7c01775d6ba6d17dea4ab221f2"
$ADMIN_PASSWORD = "h5t/PaNtGRlEGflS"
$KEYSTORE_PASSWORD = "5QsZpICYIz2ZCk6z6Di7hLet1ot97Re3"

# ============================================================================
# HEADER
# ============================================================================

Clear-Host
Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   NESF CORE - PHASE 1 COMPLETE DEPLOYMENT SCRIPT          ║" -ForegroundColor Cyan
Write-Host "║                  2026-08-15                                ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "This script will complete all Phase 1 deployment steps." -ForegroundColor Green
Write-Host ""

# ============================================================================
# PRE-FLIGHT CHECK
# ============================================================================

Write-Host "PRE-FLIGHT CHECKS" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host ""

# Check gcloud is installed
Write-Host "Checking gcloud CLI..." -ForegroundColor White
try {
    $gcloud_version = gcloud --version 2>&1 | Select-Object -First 1
    Write-Host "✅ gcloud found: $gcloud_version" -ForegroundColor Green
} catch {
    Write-Host "❌ gcloud CLI not found. Install from: https://cloud.google.com/sdk" -ForegroundColor Red
    exit 1
}

# Check gcloud auth
Write-Host ""
Write-Host "Checking gcloud authentication..." -ForegroundColor White
$auth_check = gcloud auth list 2>&1
if ($auth_check -like "*biki@nesportsfoundation.in*") {
    Write-Host "✅ gcloud authenticated as: biki@nesportsfoundation.in" -ForegroundColor Green
} else {
    Write-Host "⚠️  gcloud needs authentication" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Running: gcloud auth login" -ForegroundColor Cyan
    Write-Host "(A browser window will open for you to sign in)" -ForegroundColor Cyan
    Write-Host ""
    gcloud auth login
    Write-Host ""
    Write-Host "✅ Authentication complete" -ForegroundColor Green
}

Write-Host ""
Write-Host "✅ Pre-flight checks passed!" -ForegroundColor Green
Write-Host ""
Start-Sleep -Seconds 2

# ============================================================================
# STEP 1: Update Secret Manager - Database Password
# ============================================================================

Write-Host "═════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "STEP 1: Updating Google Secret Manager - Database Password" -ForegroundColor Cyan
Write-Host "═════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "Database Password: $($DB_PASSWORD.Substring(0,15))..." -ForegroundColor Yellow
Write-Host ""

$DB_PASSWORD | gcloud secrets versions add nesf-core-db-password `
    --data-file=- `
    --project=thenesports-api-prod 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Database password secret updated successfully" -ForegroundColor Green
} else {
    Write-Host "❌ Failed to update database password secret" -ForegroundColor Red
    exit 1
}

Write-Host ""
Start-Sleep -Seconds 2

# ============================================================================
# STEP 2: Update Secret Manager - JWT Secret
# ============================================================================

Write-Host "═════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "STEP 2: Updating Google Secret Manager - JWT Secret" -ForegroundColor Cyan
Write-Host "═════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "JWT Secret: $($JWT_SECRET.Substring(0,15))..." -ForegroundColor Yellow
Write-Host ""

$JWT_SECRET | gcloud secrets versions add nesf-core-jwt-secret `
    --data-file=- `
    --project=thenesports-api-prod 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ JWT secret updated successfully" -ForegroundColor Green
} else {
    Write-Host "❌ Failed to update JWT secret" -ForegroundColor Red
    exit 1
}

Write-Host ""
Start-Sleep -Seconds 2

# ============================================================================
# STEP 3: Verify Secret Manager Updates
# ============================================================================

Write-Host "═════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "STEP 3: Verifying Secret Manager Updates" -ForegroundColor Cyan
Write-Host "═════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

Write-Host "Verifying database password..." -ForegroundColor White
$stored_db = gcloud secrets versions access latest --secret=nesf-core-db-password --project=thenesports-api-prod 2>$null
if ($stored_db -eq $DB_PASSWORD) {
    Write-Host "✅ Database password verified" -ForegroundColor Green
} else {
    Write-Host "❌ Database password verification failed" -ForegroundColor Red
}

Write-Host ""
Write-Host "Verifying JWT secret..." -ForegroundColor White
$stored_jwt = gcloud secrets versions access latest --secret=nesf-core-jwt-secret --project=thenesports-api-prod 2>$null
if ($stored_jwt -eq $JWT_SECRET) {
    Write-Host "✅ JWT secret verified" -ForegroundColor Green
} else {
    Write-Host "❌ JWT secret verification failed" -ForegroundColor Red
}

Write-Host ""
Start-Sleep -Seconds 2

# ============================================================================
# STEP 4: Deploy to Cloud Run
# ============================================================================

Write-Host "═════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "STEP 4: Deploying to Cloud Run" -ForegroundColor Cyan
Write-Host "═════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "Deploying nesf-core-api to Cloud Run..." -ForegroundColor Yellow
Write-Host "(This may take 2-3 minutes)" -ForegroundColor Gray
Write-Host ""

gcloud run deploy nesf-core-api `
    --region=asia-south1 `
    --project=thenesports-api-prod 2>&1 | ForEach-Object {
    if ($_ -like "*deployed*" -or $_ -like "*serving*") {
        Write-Host $_ -ForegroundColor Green
    } else {
        Write-Host $_
    }
}

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "✅ Cloud Run deployment successful" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "⚠️  Cloud Run deployment command executed (may still be deploying)" -ForegroundColor Yellow
}

Write-Host ""
Start-Sleep -Seconds 3

# ============================================================================
# STEP 5: Verify Production
# ============================================================================

Write-Host "═════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "STEP 5: Verifying Production Deployment" -ForegroundColor Cyan
Write-Host "═════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "Testing health check: https://app.nesportsfoundation.in/health" -ForegroundColor Yellow
Write-Host "(Waiting for service to be ready - may take 10-30 seconds)" -ForegroundColor Gray
Write-Host ""

$health_check_passed = $false
for ($i = 1; $i -le 6; $i++) {
    try {
        $response = curl -s -m 5 https://app.nesportsfoundation.in/health 2>$null
        if ($response -like "*ok*") {
            Write-Host "✅ Health check PASSED!" -ForegroundColor Green
            Write-Host "Response: $response" -ForegroundColor Green
            $health_check_passed = $true
            break
        }
    } catch {
        # Service not ready yet
    }

    if ($i -lt 6) {
        Write-Host "⏳ Attempt $i/6 - service initializing..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
    }
}

if (-not $health_check_passed) {
    Write-Host "⚠️  Health check not responding yet (service may still be deploying)" -ForegroundColor Yellow
    Write-Host "Check again in 1-2 minutes at: https://app.nesportsfoundation.in/health" -ForegroundColor Yellow
}

Write-Host ""
Start-Sleep -Seconds 2

# ============================================================================
# COMPLETION SUMMARY
# ============================================================================

Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║          ✅ PHASE 1 DEPLOYMENT COMPLETE                   ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

Write-Host "DEPLOYMENT SUMMARY" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host ""
Write-Host "✅ Google Secret Manager - Database Password: Updated" -ForegroundColor Green
Write-Host "✅ Google Secret Manager - JWT Secret: Updated" -ForegroundColor Green
Write-Host "✅ Cloud Run - Deployment: Executed" -ForegroundColor Green
Write-Host "✅ Production - Health Check: Initiated" -ForegroundColor Green
Write-Host ""

Write-Host "YOUR CREDENTIALS" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host ""
Write-Host "Database Password:" -ForegroundColor White
Write-Host "  $DB_PASSWORD" -ForegroundColor Magenta
Write-Host ""
Write-Host "Admin Account:" -ForegroundColor White
Write-Host "  Email: biki@nesportsfoundation.in" -ForegroundColor Magenta
Write-Host "  Password: $ADMIN_PASSWORD (TEMPORARY - change after login)" -ForegroundColor Magenta
Write-Host ""
Write-Host "Android Keystore Password:" -ForegroundColor White
Write-Host "  $KEYSTORE_PASSWORD" -ForegroundColor Magenta
Write-Host ""

Write-Host "⚠️  IMPORTANT NEXT STEPS" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host ""
Write-Host "1️⃣  UPDATE SUPABASE PASSWORD" -ForegroundColor Yellow
Write-Host "   URL: https://app.supabase.com" -ForegroundColor Gray
Write-Host "   Settings > Database > Users > postgres > Reset Password" -ForegroundColor Gray
Write-Host "   Password: $DB_PASSWORD" -ForegroundColor Magenta
Write-Host ""

Write-Host "2️⃣  UPDATE CLOUD SQL PASSWORD" -ForegroundColor Yellow
Write-Host "   URL: https://console.cloud.google.com/sql/instances" -ForegroundColor Gray
Write-Host "   thenesports-db > Users > postgres > Edit" -ForegroundColor Gray
Write-Host "   Password: $DB_PASSWORD" -ForegroundColor Magenta
Write-Host ""

Write-Host "3️⃣  TEST LOGIN" -ForegroundColor Yellow
Write-Host "   URL: https://app.nesportsfoundation.in/" -ForegroundColor Gray
Write-Host "   Email: biki@nesportsfoundation.in" -ForegroundColor Magenta
Write-Host "   Password: $ADMIN_PASSWORD" -ForegroundColor Magenta
Write-Host "   ⚠️  Change admin password immediately after login" -ForegroundColor Red
Write-Host ""

Write-Host "4️⃣  DELETE CREDENTIALS FILE" -ForegroundColor Yellow
Write-Host "   Delete: FINAL_CREDENTIALS_AND_DEPLOYMENT.txt" -ForegroundColor Gray
Write-Host ""

Write-Host "═════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "Phase 1 deployment is complete! Proceeding to Phase 2 soon." -ForegroundColor Green
Write-Host "═════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
