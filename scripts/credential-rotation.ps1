# NESF Core - Phase 1: Credential Rotation Script (PowerShell)
# This script guides you through rotating exposed credentials
# IMPORTANT: Some steps require manual actions (Supabase console, Google Cloud)

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "          NESF CORE: PHASE 1 CREDENTIAL ROTATION" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "⚠️  CRITICAL: This script will help rotate exposed credentials" -ForegroundColor Yellow
Write-Host "Time required: ~60 minutes"
Write-Host ""
$Continue = Read-Host "Continue? (yes/no)"
if ($Continue -ne "yes") {
    Write-Host "Aborted."
    exit 1
}

$StartTime = Get-Date

# ======================================================================
# STEP 1: Generate New Passwords & Secrets
# ======================================================================

Write-Host ""
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "STEP 1: Generate New Passwords & Secrets" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""

# Generate new JWT secret
Write-Host "Generating new JWT secret..."
$NewJWT = node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"
Write-Host "✅ New JWT Secret generated:" -ForegroundColor Green
Write-Host "   $NewJWT"
Write-Host ""

# Generate new database password (using .NET)
Write-Host "Generating new database password..."
$RandomBytes = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(24)
$NewDBPassword = [Convert]::ToBase64String($RandomBytes).Substring(0, 30)
Write-Host "✅ New Database Password generated:" -ForegroundColor Green
Write-Host "   $NewDBPassword"
Write-Host ""

# Generate new keystore password
Write-Host "Generating new keystore password..."
$RandomBytes = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(24)
$NewKeystorePassword = [Convert]::ToBase64String($RandomBytes).Substring(0, 30)
Write-Host "✅ New Keystore Password generated:" -ForegroundColor Green
Write-Host "   $NewKeystorePassword"
Write-Host ""

# Save to temporary file
$CredsFile = "$env:TEMP\nesf-core-credentials-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
$CredsContent = @"
NESF Core - New Credentials
Generated: $(Get-Date)

JWT_SECRET=$NewJWT

DATABASE_PASSWORD=$NewDBPassword

KEYSTORE_PASSWORD=$NewKeystorePassword

Keep this file safe! Delete after credentials are deployed.
"@
Set-Content -Path $CredsFile -Value $CredsContent
Write-Host "💾 Credentials saved to: $CredsFile" -ForegroundColor Yellow
Write-Host ""

# ======================================================================
# STEP 2: Manual Actions in Supabase Console
# ======================================================================

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "STEP 2: Rotate Supabase Password (MANUAL)" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "⚠️  You must do this manually in Supabase console:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Open: https://app.supabase.com"
Write-Host "2. Select NESF Core project"
Write-Host "3. Go to: Settings > Database > Users"
Write-Host "4. Click on 'postgres' user"
Write-Host "5. Click 'Reset Password'"
Write-Host "6. Copy the new password"
Write-Host ""
Write-Host "New password to use: $NewDBPassword" -ForegroundColor Magenta
Write-Host ""
Read-Host "When complete, press Enter to continue"

# ======================================================================
# STEP 3: Update Local .env Files
# ======================================================================

Write-Host ""
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "STEP 3: Update Local .env Files" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""

# Update .env.supabase
Write-Host "Updating api\.env.supabase..."
$EnvSupabaseContent = @"
# NESF Core: Supabase Configuration
# ⚠️ WARNING: This file contains sensitive production credentials
# MUST be added to .gitignore and never committed to version control

PORT=4000
NODE_ENV=production

# Supabase PostgreSQL Database Connection
DATABASE_URL=postgres://postgres:$NewDBPassword@mixbtfnjdzmfbctkxnwk.supabase.co:5432/postgres?sslmode=require

# JWT Secret
JWT_SECRET=$NewJWT

# Token Configuration
ACCESS_TOKEN_TTL=2h
REFRESH_TOKEN_DAYS=30

# CORS Origins
CORS_ORIGINS=https://app.nesportsfoundation.in,http://localhost:3000,http://localhost:4000

# File Storage
STORAGE_DRIVER=local
UPLOAD_DIR=uploads
PUBLIC_BASE_URL=https://app.nesportsfoundation.in

# Seed Data (change after first login)
SEED_ADMIN_EMAIL=biki@nesportsfoundation.in
SEED_ADMIN_PASSWORD=ChangeMe@123

# SSL Configuration
DB_SSL=true
"@
Set-Content -Path "D:\new app\nesf-core\api\.env.supabase" -Value $EnvSupabaseContent
Write-Host "✅ Updated api\.env.supabase" -ForegroundColor Green
Write-Host ""

# Create .env.local for local development
Write-Host "Creating api\.env.local for development..."
$EnvLocalContent = @"
PORT=4000
NODE_ENV=development

# Local development PostgreSQL (using docker-compose)
DATABASE_URL=postgres://postgres:localpwd@localhost:5432/nesf_core_dev

# JWT Secret (development)
JWT_SECRET=$NewJWT

# Token Configuration
ACCESS_TOKEN_TTL=2h
REFRESH_TOKEN_DAYS=30

# CORS Origins
CORS_ORIGINS=http://localhost:3000,http://localhost:4000,https://app.nesportsfoundation.in

# File Storage
STORAGE_DRIVER=local
UPLOAD_DIR=uploads
PUBLIC_BASE_URL=http://localhost:4000

# Seed Data (change after first login)
SEED_ADMIN_EMAIL=biki@nesportsfoundation.in
SEED_ADMIN_PASSWORD=LocalDev@123

# SSL Configuration
DB_SSL=false
"@
Set-Content -Path "D:\new app\nesf-core\api\.env.local" -Value $EnvLocalContent
Write-Host "✅ Created api\.env.local" -ForegroundColor Green
Write-Host ""

# ======================================================================
# STEP 4: Manual Actions in Google Cloud
# ======================================================================

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "STEP 4: Rotate Cloud SQL Password (MANUAL/CLI)" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Option A: Using gcloud CLI (requires authentication)" -ForegroundColor Yellow
Write-Host "  gcloud sql users set-password postgres ``"
Write-Host "    --instance=thenesports-db ``"
Write-Host "    --password='$NewDBPassword' ``"
Write-Host "    --project=thenesports-api-prod"
Write-Host ""
Write-Host "Option B: Manual via Cloud Console" -ForegroundColor Yellow
Write-Host "  1. Open: https://console.cloud.google.com/sql"
Write-Host "  2. Select: thenesports-db"
Write-Host "  3. Users tab > postgres user > Change password"
Write-Host "  4. Use: $NewDBPassword"
Write-Host ""
Read-Host "When complete, press Enter to continue"

# ======================================================================
# STEP 5: Update Google Secret Manager
# ======================================================================

Write-Host ""
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "STEP 5: Update Google Secret Manager" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""

# Check if gcloud is available
if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) {
    Write-Host "⚠️  gcloud CLI not found. Install from: https://cloud.google.com/sdk" -ForegroundColor Yellow
    Read-Host "After installing, press Enter to continue"
}

Write-Host "Updating Secret Manager secrets..."
Write-Host ""

# Update database password
Write-Host "  Updating: nesf-core-db-password"
$NewDBPassword | gcloud secrets versions add nesf-core-db-password `
  --data-file=- `
  --project=thenesports-api-prod 2>$null
if ($?) {
    Write-Host "  ✅ Updated" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  Failed (may need permissions)" -ForegroundColor Yellow
}

# Update JWT secret
Write-Host "  Updating: nesf-core-jwt-secret"
$NewJWT | gcloud secrets versions add nesf-core-jwt-secret `
  --data-file=- `
  --project=thenesports-api-prod 2>$null
if ($?) {
    Write-Host "  ✅ Updated" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  Failed (may need permissions)" -ForegroundColor Yellow
}

Write-Host ""

# ======================================================================
# STEP 6: Create Android Keystore key.properties
# ======================================================================

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "STEP 6: Create Android Keystore Configuration" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Creating app\android\key.properties..."
$KeyPropertiesContent = @"
# Android Keystore Configuration
# Generated: $(Get-Date)
# Keep this file SECRET - never commit to git

storeFile=../nesf-core-key.jks
storePassword=$NewKeystorePassword
keyAlias=nesf-core-key
keyPassword=$NewKeystorePassword
"@
Set-Content -Path "D:\new app\nesf-core\app\android\key.properties" -Value $KeyPropertiesContent
Write-Host "✅ Created app\android\key.properties" -ForegroundColor Green
Write-Host "   Keystore password: $NewKeystorePassword" -ForegroundColor Magenta
Write-Host ""

# ======================================================================
# STEP 7: Test Local Setup
# ======================================================================

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "STEP 7: Test Local Setup" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Checking Node.js..."
if (Get-Command node -ErrorAction SilentlyContinue) {
    Write-Host "✅ Node.js is available" -ForegroundColor Green
} else {
    Write-Host "⚠️  Node.js not found. Install from: https://nodejs.org" -ForegroundColor Yellow
}

Write-Host ""

# ======================================================================
# SUMMARY
# ======================================================================

$EndTime = Get-Date
$Elapsed = ($EndTime - $StartTime).TotalMinutes

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "✅ PHASE 1 CREDENTIAL ROTATION COMPLETE" -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Elapsed time: $([Math]::Round($Elapsed, 1)) minutes"
Write-Host ""
Write-Host "What was done:" -ForegroundColor Green
Write-Host "  ✅ Generated new JWT secret"
Write-Host "  ✅ Generated new database password"
Write-Host "  ✅ Updated api\.env.supabase"
Write-Host "  ✅ Created api\.env.local (development)"
Write-Host "  ✅ Created app\android\key.properties"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Verify the files were created:"
Write-Host "     - api\.env.supabase (check DATABASE_URL)"
Write-Host "     - api\.env.local (check JWT_SECRET)"
Write-Host "     - app\android\key.properties (check storePassword)"
Write-Host ""
Write-Host "  2. Test local setup (from D:\new app\nesf-core):"
Write-Host "     cd api"
Write-Host "     npm install"
Write-Host "     npm run migrate"
Write-Host ""
Write-Host "  3. Deploy to production:"
Write-Host "     gcloud run deploy nesf-core-api --region=asia-south1 --project=thenesports-api-prod"
Write-Host ""
Write-Host "  4. Test production:"
Write-Host "     curl https://app.nesportsfoundation.in/health"
Write-Host ""
Write-Host "Credentials saved to: $CredsFile" -ForegroundColor Yellow
Write-Host "Delete this file after deployment is complete"
Write-Host ""
Write-Host "======================================================================" -ForegroundColor Cyan
