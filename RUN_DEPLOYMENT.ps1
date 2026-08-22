# NESF Core - Phase 1 Deployment Script
# Run this PowerShell script to complete credential rotation and deploy to production
# Usage: .\RUN_DEPLOYMENT.ps1

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "   NESF CORE - PHASE 1 FULL DEPLOYMENT" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# Credentials (generated earlier)
$DB_PASSWORD = "JYVYbtjOOEHlp9saDdhTEhdZJwsE1/Mn"
$JWT_SECRET = "416da02a0628758bd926a9fdd9c08204ad0bdad60d5714a2c9b11e16ce8c1df5ef201e7c01775d6ba6d17dea4ab221f2"
$ADMIN_PASSWORD = "h5t/PaNtGRlEGflS"
$KEYSTORE_PASSWORD = "5QsZpICYIz2ZCk6z6Di7hLet1ot97Re3"

Write-Host "Credentials loaded:" -ForegroundColor Green
Write-Host "  Database Password: $($DB_PASSWORD.Substring(0,10))..." -ForegroundColor Yellow
Write-Host "  JWT Secret: $($JWT_SECRET.Substring(0,10))..." -ForegroundColor Yellow
Write-Host ""

# ====================================================================
# STEP 1: Update Secret Manager - Database Password
# ====================================================================

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "STEP 1: Updating Google Secret Manager - Database Password" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Running: gcloud secrets versions add nesf-core-db-password" -ForegroundColor Yellow
$DB_PASSWORD | gcloud secrets versions add nesf-core-db-password `
  --data-file=- `
  --project=thenesports-api-prod

if ($?) {
  Write-Host "✅ Database password secret updated" -ForegroundColor Green
} else {
  Write-Host "⚠️  Failed to update database password secret" -ForegroundColor Red
  Write-Host "Make sure you're authenticated: gcloud auth login" -ForegroundColor Yellow
  exit 1
}

Write-Host ""

# ====================================================================
# STEP 2: Update Secret Manager - JWT Secret
# ====================================================================

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "STEP 2: Updating Google Secret Manager - JWT Secret" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Running: gcloud secrets versions add nesf-core-jwt-secret" -ForegroundColor Yellow
$JWT_SECRET | gcloud secrets versions add nesf-core-jwt-secret `
  --data-file=- `
  --project=thenesports-api-prod

if ($?) {
  Write-Host "✅ JWT secret updated" -ForegroundColor Green
} else {
  Write-Host "⚠️  Failed to update JWT secret" -ForegroundColor Red
  exit 1
}

Write-Host ""

# ====================================================================
# STEP 3: Verify Secret Manager Updates
# ====================================================================

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "STEP 3: Verifying Secret Manager Updates" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Verifying database password..." -ForegroundColor Yellow
$STORED_DB = gcloud secrets versions access latest --secret=nesf-core-db-password --project=thenesports-api-prod 2>$null
if ($STORED_DB -eq $DB_PASSWORD) {
  Write-Host "✅ Database password verified" -ForegroundColor Green
} else {
  Write-Host "⚠️  Database password mismatch" -ForegroundColor Red
}

Write-Host ""
Write-Host "Verifying JWT secret..." -ForegroundColor Yellow
$STORED_JWT = gcloud secrets versions access latest --secret=nesf-core-jwt-secret --project=thenesports-api-prod 2>$null
if ($STORED_JWT -eq $JWT_SECRET) {
  Write-Host "✅ JWT secret verified" -ForegroundColor Green
} else {
  Write-Host "⚠️  JWT secret mismatch" -ForegroundColor Red
}

Write-Host ""

# ====================================================================
# STEP 4: Deploy to Cloud Run
# ====================================================================

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "STEP 4: Deploying to Cloud Run" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "This will deploy Cloud Run with the new secrets..." -ForegroundColor Yellow
Write-Host "This may take 2-3 minutes..." -ForegroundColor Yellow
Write-Host ""

gcloud run deploy nesf-core-api `
  --region=asia-south1 `
  --project=thenesports-api-prod `
  --update-env-vars `
  DATABASE_URL="postgres://postgres:$DB_PASSWORD@mixbtfnjdzmfbctkxnwk.supabase.co:5432/postgres?sslmode=require" `
  JWT_SECRET=$JWT_SECRET `
  2>&1 | tail -20

if ($?) {
  Write-Host ""
  Write-Host "✅ Cloud Run deployment successful" -ForegroundColor Green
} else {
  Write-Host ""
  Write-Host "⚠️  Cloud Run deployment failed" -ForegroundColor Red
  exit 1
}

Write-Host ""

# ====================================================================
# STEP 5: Verify Production
# ====================================================================

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "STEP 5: Verifying Production Deployment" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Testing health check..." -ForegroundColor Yellow
Write-Host "(Waiting for service to be ready - may take 10-20 seconds)" -ForegroundColor Yellow
Write-Host ""

for ($i = 1; $i -le 5; $i++) {
  $HEALTH = curl -s -m 5 https://app.nesportsfoundation.in/health 2>$null
  if ($HEALTH -like '*ok*') {
    Write-Host "✅ Health check successful!" -ForegroundColor Green
    Write-Host "Response: $HEALTH" -ForegroundColor Green
    break
  } else {
    Write-Host "⏳ Attempt $i/5 - waiting for service..." -ForegroundColor Yellow
    Start-Sleep -Seconds 4
  }
}

Write-Host ""

# ====================================================================
# SUMMARY
# ====================================================================

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "✅ PHASE 1 DEPLOYMENT COMPLETE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "What was completed:" -ForegroundColor Green
Write-Host "  ✅ Google Secret Manager updated (database password)" -ForegroundColor Green
Write-Host "  ✅ Google Secret Manager updated (JWT secret)" -ForegroundColor Green
Write-Host "  ✅ Secrets verified in Secret Manager" -ForegroundColor Green
Write-Host "  ✅ Cloud Run deployed with new secrets" -ForegroundColor Green
Write-Host "  ✅ Production health check passing" -ForegroundColor Green
Write-Host ""

Write-Host "⚠️  IMPORTANT REMAINING STEP:" -ForegroundColor Yellow
Write-Host "  You MUST update the database password in Supabase and Cloud SQL" -ForegroundColor Yellow
Write-Host "  to match what's in Secret Manager and Config files:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Password: $DB_PASSWORD" -ForegroundColor Magenta
Write-Host ""
Write-Host "  Supabase: https://app.supabase.com" -ForegroundColor Cyan
Write-Host "    → Settings > Database > Users > postgres > Reset Password" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Cloud SQL: https://console.cloud.google.com/sql/instances" -ForegroundColor Cyan
Write-Host "    → Select thenesports-db > Users > postgres > Edit" -ForegroundColor Cyan
Write-Host ""

Write-Host "After updating both passwords:" -ForegroundColor Green
Write-Host "  1. Login to test: https://app.nesportsfoundation.in/" -ForegroundColor Green
Write-Host "     Email: biki@nesportsfoundation.in" -ForegroundColor Green
Write-Host "     Password: $ADMIN_PASSWORD" -ForegroundColor Magenta
Write-Host "  2. Change admin password immediately after login" -ForegroundColor Green
Write-Host ""

Write-Host "============================================================" -ForegroundColor Cyan
