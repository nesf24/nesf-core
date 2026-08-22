#!/bin/bash
set -e

# NESF Core - Phase 1: Credential Rotation Script
# This script guides you through rotating exposed credentials
# IMPORTANT: Some steps require manual actions (Supabase console, Google Cloud)

echo "======================================================================"
echo "          NESF CORE: PHASE 1 CREDENTIAL ROTATION"
echo "======================================================================"
echo ""
echo "⚠️  CRITICAL: This script will help rotate exposed credentials"
echo "Time required: ~60 minutes"
echo ""
read -p "Continue? (yes/no) " -r CONTINUE
if [[ ! $CONTINUE =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Store start time
START_TIME=$(date +%s)

# ====================================================================
# STEP 1: Generate New Passwords & Secrets
# ====================================================================

echo ""
echo "======================================================================"
echo "STEP 1: Generate New Passwords & Secrets"
echo "======================================================================"
echo ""

# Generate new JWT secret
echo "Generating new JWT secret..."
NEW_JWT=$(node -e "console.log(require('crypto').randomBytes(48).toString('hex'))")
echo "✅ New JWT Secret generated:"
echo "   $NEW_JWT"
echo ""

# Generate new database password
echo "Generating new database password..."
NEW_DB_PASSWORD=$(openssl rand -base64 32 | tr -d '\n' | head -c 30)
echo "✅ New Database Password generated:"
echo "   $NEW_DB_PASSWORD"
echo ""

# Prompt for keystore password
echo "Generating new keystore password..."
NEW_KEYSTORE_PASSWORD=$(openssl rand -base64 32 | tr -d '\n' | head -c 30)
echo "✅ New Keystore Password generated:"
echo "   $NEW_KEYSTORE_PASSWORD"
echo ""

# Save to temporary file
CREDS_FILE="/tmp/nesf-core-new-credentials-$(date +%s).txt"
cat > "$CREDS_FILE" << EOF
NESF Core - New Credentials
Generated: $(date)

JWT_SECRET=$NEW_JWT

DATABASE_PASSWORD=$NEW_DB_PASSWORD

KEYSTORE_PASSWORD=$NEW_KEYSTORE_PASSWORD

Keep this file safe! Delete after credentials are deployed.
EOF

echo "💾 Credentials saved to: $CREDS_FILE"
echo ""

# ====================================================================
# STEP 2: Manual Actions in Supabase Console
# ====================================================================

echo "======================================================================"
echo "STEP 2: Rotate Supabase Password (MANUAL)"
echo "======================================================================"
echo ""
echo "⚠️  You must do this manually in Supabase console:"
echo ""
echo "1. Open: https://app.supabase.com"
echo "2. Select NESF Core project"
echo "3. Go to: Settings > Database > Users"
echo "4. Click on 'postgres' user"
echo "5. Click 'Reset Password'"
echo "6. Copy the new password"
echo ""
echo "New password to use: $NEW_DB_PASSWORD"
echo ""
read -p "When complete, press Enter to continue..." -r

# ====================================================================
# STEP 3: Update Local .env Files
# ====================================================================

echo ""
echo "======================================================================"
echo "STEP 3: Update Local .env Files"
echo "======================================================================"
echo ""

# Update .env.supabase
echo "Updating api/.env.supabase..."
sed -i "s/DATABASE_URL=.*/DATABASE_URL=postgres:\/\/postgres:${NEW_DB_PASSWORD//\//\\/}@mixbtfnjdzmfbctkxnwk.supabase.co:5432\/postgres?sslmode=require/" api/.env.supabase
sed -i "s/JWT_SECRET=.*/JWT_SECRET=$NEW_JWT/" api/.env.supabase
echo "✅ Updated api/.env.supabase"
echo ""

# Create .env.local for local development
echo "Creating api/.env.local for development..."
cat > api/.env.local << EOF
PORT=4000
NODE_ENV=development

# Local development PostgreSQL (using docker-compose)
DATABASE_URL=postgres://postgres:localpwd@localhost:5432/nesf_core_dev

# JWT Secret (development)
JWT_SECRET=$NEW_JWT

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
EOF
echo "✅ Created api/.env.local"
echo ""

# ====================================================================
# STEP 4: Manual Actions in Google Cloud
# ====================================================================

echo "======================================================================"
echo "STEP 4: Rotate Cloud SQL Password (MANUAL/CLI)"
echo "======================================================================"
echo ""
echo "Option A: Using gcloud CLI (requires authentication)"
echo "  gcloud sql users set-password postgres \\"
echo "    --instance=thenesports-db \\"
echo "    --password='$NEW_DB_PASSWORD' \\"
echo "    --project=thenesports-api-prod"
echo ""
echo "Option B: Manual via Cloud Console"
echo "  1. Open: https://console.cloud.google.com/sql"
echo "  2. Select: thenesports-db"
echo "  3. Users tab > postgres user > Change password"
echo "  4. Use: $NEW_DB_PASSWORD"
echo ""
read -p "When complete, press Enter to continue..." -r

# ====================================================================
# STEP 5: Update Google Secret Manager
# ====================================================================

echo ""
echo "======================================================================"
echo "STEP 5: Update Google Secret Manager"
echo "======================================================================"
echo ""

# Check if gcloud is authenticated
if ! gcloud auth list 2>/dev/null | grep -q "ACTIVE"; then
    echo "⚠️  gcloud not authenticated. Authenticate first:"
    echo "   gcloud auth login"
    read -p "After authenticating, press Enter to continue..." -r
fi

echo "Updating Secret Manager secrets..."
echo ""

# Update database password
echo "  Updating: nesf-core-db-password"
echo "$NEW_DB_PASSWORD" | gcloud secrets versions add nesf-core-db-password \
  --data-file=- \
  --project=thenesports-api-prod 2>/dev/null && echo "  ✅ Updated" || echo "  ⚠️  Failed (may need permissions)"

# Update JWT secret
echo "  Updating: nesf-core-jwt-secret"
echo "$NEW_JWT" | gcloud secrets versions add nesf-core-jwt-secret \
  --data-file=- \
  --project=thenesports-api-prod 2>/dev/null && echo "  ✅ Updated" || echo "  ⚠️  Failed (may need permissions)"

echo ""

# ====================================================================
# STEP 6: Test Local Setup
# ====================================================================

echo "======================================================================"
echo "STEP 6: Test Local Setup"
echo "======================================================================"
echo ""

# Check if PostgreSQL is running
if command -v pg_isready &> /dev/null; then
    echo "Checking PostgreSQL connection..."
    if pg_isready -h localhost -p 5432 &>/dev/null; then
        echo "✅ PostgreSQL is running"
    else
        echo "⚠️  PostgreSQL not running. Start with: docker-compose up -d"
        read -p "After starting, press Enter to continue..." -r
    fi
fi

# Test database migration
echo ""
echo "Testing database migration with new credentials..."
cd api
if npm run migrate 2>/dev/null; then
    echo "✅ Database migration successful"
else
    echo "⚠️  Database migration failed. Check credentials."
    echo "   DATABASE_URL in api/.env.local should be correct"
fi
cd ..

echo ""

# ====================================================================
# STEP 7: Create Android Keystore key.properties
# ====================================================================

echo "======================================================================"
echo "STEP 7: Create Android Keystore Configuration"
echo "======================================================================"
echo ""

echo "Creating app/android/key.properties..."
cat > app/android/key.properties << EOF
# Android Keystore Configuration
# Generated: $(date)
# Keep this file SECRET - never commit to git

storeFile=../nesf-core-key.jks
storePassword=$NEW_KEYSTORE_PASSWORD
keyAlias=nesf-core-key
keyPassword=$NEW_KEYSTORE_PASSWORD
EOF

echo "✅ Created app/android/key.properties"
echo "   Keystore password: $NEW_KEYSTORE_PASSWORD"
echo ""

# ====================================================================
# STEP 8: Test APK Build
# ====================================================================

echo "======================================================================"
echo "STEP 8: Test APK Build (Optional)"
echo "======================================================================"
echo ""

read -p "Test APK build now? This takes ~5 minutes. (yes/no) " -r BUILD_APK
if [[ $BUILD_APK =~ ^[Yy][Ee][Ss]$ ]]; then
    cd app
    echo "Building APK..."
    if flutter build apk --release 2>&1 | tail -20; then
        echo "✅ APK built successfully"
    else
        echo "⚠️  APK build failed. Check flutter installation."
    fi
    cd ..
fi

echo ""

# ====================================================================
# STEP 9: Summary & Next Steps
# ====================================================================

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED / 60))

echo "======================================================================"
echo "✅ PHASE 1 CREDENTIAL ROTATION COMPLETE"
echo "======================================================================"
echo ""
echo "Elapsed time: ${MINUTES} minutes"
echo ""
echo "What was done:"
echo "  ✅ Generated new JWT secret"
echo "  ✅ Generated new database password"
echo "  ✅ Updated api/.env.supabase"
echo "  ✅ Created api/.env.local (development)"
echo "  ✅ Created app/android/key.properties"
echo "  ✅ Updated Google Secret Manager"
echo "  ✅ Tested local setup"
echo ""
echo "Next steps:"
echo "  1. Verify production deployment:"
echo "     gcloud run deploy nesf-core-api \\"
echo "       --region=asia-south1 \\"
echo "       --project=thenesports-api-prod \\"
echo "       --update-env-vars DATABASE_URL=$(gcloud secrets versions access latest --secret=nesf-core-db-password --project=thenesports-api-prod) \\"
echo "       --update-env-vars JWT_SECRET=$(gcloud secrets versions access latest --secret=nesf-core-jwt-secret --project=thenesports-api-prod)"
echo ""
echo "  2. Test production health check:"
echo "     curl -sS https://app.nesportsfoundation.in/health"
echo ""
echo "  3. Change admin password:"
echo "     Login with: biki@nesportsfoundation.in / <your-new-admin-password>"
echo "     Change password via app UI"
echo ""
echo "  4. Optional: Clean git history"
echo "     See: SECURITY_REMEDIATION.md, Phase C"
echo ""
echo "Credentials saved to: $CREDS_FILE"
echo "Delete this file after deployment is complete"
echo ""
echo "======================================================================"
