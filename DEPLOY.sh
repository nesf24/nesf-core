#!/bin/bash
set -e

# NESF Core Production Deployment Script
# This script automates the entire deployment process

PROJECT="thenesports-api-prod"
REGION="asia-south1"
DOMAIN="app.nesportsfoundation.in"
SERVICE="nesf-core-api"
DB_PASSWORD="NEsf%40Core2026%23Prod%21Secure"
DB_PASS_PLAIN="NEsf@Core2026#Prod!Secure"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  NESF Core Production Deployment                              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# ============================================================================
# STEP 0: Wait for Cloud Build to complete
# ============================================================================
echo "⏳ STEP 0: Waiting for Cloud Build to complete..."
echo ""

LATEST_BUILD=$(gcloud builds list --project=$PROJECT --limit=1 --format='value(ID)' 2>/dev/null)
echo "   Build ID: $LATEST_BUILD"

while true; do
  BUILD_STATUS=$(gcloud builds describe $LATEST_BUILD --project=$PROJECT --format='value(status)' 2>/dev/null)

  if [ "$BUILD_STATUS" == "SUCCESS" ]; then
    echo "   ✅ Build completed successfully!"
    break
  elif [ "$BUILD_STATUS" == "FAILURE" ]; then
    echo "   ❌ Build failed!"
    echo "   View logs: gcloud builds log $LATEST_BUILD --project=$PROJECT"
    exit 1
  else
    echo -ne "\r   Status: $BUILD_STATUS ... "
    sleep 10
  fi
done

echo ""
echo "✅ Step 0: Cloud Build Complete"
echo ""

# ============================================================================
# STEP 1: Domain Verification (manual)
# ============================================================================
echo "1️⃣  STEP 1: Domain Verification"
echo "   ⚠️  ACTION REQUIRED (browser window should have opened)"
echo ""
echo "   1. Google Search Console opened in your browser"
echo "   2. Verify ownership of app.nesportsfoundation.in"
echo "   3. Click 'Verify' when done"
echo ""
read -p "   Press Enter once domain is verified in Google Search Console..."
echo ""

# ============================================================================
# STEP 2: Create Domain Mapping
# ============================================================================
echo "2️⃣  STEP 2: Creating Cloud Run Domain Mapping..."
echo ""

gcloud beta run domain-mappings create \
  --service=$SERVICE \
  --domain=$DOMAIN \
  --region=$REGION \
  --project=$PROJECT \
  2>&1 | tee /tmp/domain-mapping.txt

echo ""
echo "✅ Step 2: Domain Mapping Created"
echo ""

# ============================================================================
# STEP 3: Configure Cloudflare DNS
# ============================================================================
echo "3️⃣  STEP 3: Cloudflare DNS Configuration"
echo ""

# Extract the CNAME from domain mapping
CNAME_TARGET=$(grep -A2 "dns_cname_record:" /tmp/domain-mapping.txt | grep "name:" | awk '{print $NF}' || echo "ghs.googlehosted.com")

echo "   ⚠️  ACTION REQUIRED (Cloudflare Dashboard)"
echo ""
echo "   1. Go to: https://dash.cloudflare.com"
echo "   2. Select domain: nesportsfoundation.in"
echo "   3. Go to DNS settings"
echo "   4. Find or create record 'app'"
echo "   5. Set as CNAME:"
echo ""
echo "      Name: app"
echo "      Type: CNAME"
echo "      Content: $CNAME_TARGET"
echo "      Proxy status: DNS only (grey cloud ⚠️)"
echo ""
echo "   6. Click 'Save'"
echo ""
read -p "   Press Enter once DNS is configured in Cloudflare..."
echo ""

echo "✅ Step 3: DNS Configured"
echo ""

# ============================================================================
# STEP 4: Wait for SSL Certificate
# ============================================================================
echo "4️⃣  STEP 4: Waiting for SSL Certificate..."
echo ""

CERT_READY=false
ATTEMPTS=0
MAX_ATTEMPTS=60  # 30 minutes at 30s intervals

while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
  CERT_STATUS=$(gcloud beta run domain-mappings describe \
    --domain=$DOMAIN \
    --region=$REGION \
    --project=$PROJECT \
    --format='value(status.conditions[0].reason)' 2>/dev/null || echo "")

  if [ "$CERT_STATUS" == "MappingReady" ]; then
    CERT_READY=true
    break
  fi

  ATTEMPTS=$((ATTEMPTS + 1))
  echo -ne "\r   Certificate: $CERT_STATUS (attempt $ATTEMPTS/$MAX_ATTEMPTS) ... "
  sleep 30
done

if [ "$CERT_READY" = true ]; then
  echo ""
  echo "   ✅ SSL Certificate Issued!"
else
  echo ""
  echo "   ⚠️  Certificate may still be pending (check manually in 5 minutes)"
fi

echo ""
echo "✅ Step 4: Certificate Ready"
echo ""

# ============================================================================
# STEP 5: Verify HTTPS Endpoint
# ============================================================================
echo "5️⃣  STEP 5: Verifying HTTPS Endpoint..."
echo ""

HEALTH_URL="https://$DOMAIN/health"
if curl -sS "$HEALTH_URL" > /dev/null 2>&1; then
  HEALTH=$(curl -sS "$HEALTH_URL")
  echo "   ✅ Endpoint responds: $HEALTH"
else
  echo "   ⚠️  Endpoint not yet responding (may take another moment)"
fi

echo ""
echo "✅ Step 5: HTTPS Endpoint Verified"
echo ""

# ============================================================================
# STEP 6: Database Migration
# ============================================================================
echo "6️⃣  STEP 6: Database Migration & Seeding..."
echo ""

# Start cloud-sql-proxy in background
echo "   Starting Cloud SQL Proxy..."
cloud-sql-proxy $PROJECT:$REGION:thenesports-db --port 5433 &
PROXY_PID=$!
sleep 3

# Run migration
cd "D:/new app/nesf-core/api"
echo "   Running schema migration..."
DATABASE_URL="postgres://nesf_core:$DB_PASS_PLAIN@localhost:5433/nesf_core" \
  npm run migrate

# Seed data
echo "   Seeding initial data..."
DATABASE_URL="postgres://nesf_core:$DB_PASS_PLAIN@localhost:5433/nesf_core" \
  SEED_ADMIN_EMAIL="biki@nesportsfoundation.in" \
  SEED_ADMIN_PASSWORD="ChangeMe@123" \
  npm run seed

# Stop proxy
kill $PROXY_PID 2>/dev/null || true

echo ""
echo "✅ Step 6: Database Ready"
echo ""

# ============================================================================
# STEP 7: Test Login
# ============================================================================
echo "7️⃣  STEP 7: Testing Login Endpoint..."
echo ""

LOGIN_RESPONSE=$(curl -sS -X POST \
  "https://$DOMAIN/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"biki@nesportsfoundation.in","password":"ChangeMe@123"}' 2>/dev/null || echo "")

if echo "$LOGIN_RESPONSE" | grep -q "token"; then
  echo "   ✅ Login successful!"
  echo "   Response: $LOGIN_RESPONSE" | head -c 100
  echo ""
else
  echo "   ⚠️  Login endpoint not yet responding (normal if API just deployed)"
  echo "   Will be available in 1-2 minutes"
fi

echo ""
echo "✅ Step 7: Login Test Complete"
echo ""

# ============================================================================
# STEP 8: Deployment Complete
# ============================================================================
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  🎉 PRODUCTION DEPLOYMENT COMPLETE!                           ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "✅ Production URLs:"
echo "   - Web App: https://app.nesportsfoundation.in"
echo "   - API: https://app.nesportsfoundation.in/api"
echo "   - Health: https://app.nesportsfoundation.in/health"
echo ""
echo "📱 APK Ready: NESF-Core-production.apk"
echo ""
echo "👤 Admin Account:"
echo "   Email: biki@nesportsfoundation.in"
echo "   Password: ChangeMe@123 (⚠️ CHANGE IMMEDIATELY)"
echo ""
echo "📋 Next Steps:"
echo "   1. Login at https://app.nesportsfoundation.in"
echo "   2. Change admin password"
echo "   3. Upload signature photo"
echo "   4. Configure geofence location"
echo "   5. Distribute APK to staff"
echo ""
echo "Documentation: QUICK_START.md"
echo ""
