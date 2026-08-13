#!/bin/bash
# NESF Core Production Deployment Commands
# Run these commands in order after Cloud Build completes

PROJECT="thenesports-api-prod"
REGION="asia-south1"
DOMAIN="app.nesportsfoundation.in"
SERVICE="nesf-core-api"

echo "🚀 NESF Core Production Deployment"
echo "=================================="
echo ""

# Step 1: Verify domain (requires manual Google Search Console)
echo "📋 Step 1: Verify domain in Google Search Console"
echo "   URL: https://search.google.com/search-console/"
echo "   Add TXT record from GSC to DNS"
echo ""
read -p "   Press Enter once domain is verified in GSC..."

# Step 2: Create domain mapping
echo "🌐 Step 2: Creating Cloud Run domain mapping..."
gcloud beta run domain-mappings create \
  --service=$SERVICE \
  --domain=$DOMAIN \
  --region=$REGION \
  --project=$PROJECT

echo ""
echo "📝 NOTE: Google returned DNS records above."
echo "   Add them to Cloudflare for nesportsfoundation.in:"
echo "   1. Type: CNAME"
echo "   2. Name: app"
echo "   3. Content: (from above output)"
echo "   4. Proxy: DNS only (grey cloud)"
echo "   5. SSL/TLS: Full (strict) once proxying enabled"
echo ""

read -p "Press Enter once DNS is configured in Cloudflare..."

# Step 3: Wait for certificate
echo "⏳ Waiting for SSL certificate (up to 30 minutes)..."
gcloud beta run domain-mappings describe \
  --domain=$DOMAIN \
  --region=$REGION \
  --project=$PROJECT \
  --format='value(status.conditions[0].reason)'

# Step 4: Verify HTTPS
echo ""
echo "✅ Step 3: Verify HTTPS endpoint..."
until curl -sS https://$DOMAIN/health > /dev/null 2>&1; do
  echo "   Waiting for $DOMAIN to respond..."
  sleep 10
done

echo "   ✓ Health check: https://$DOMAIN/health"

# Step 5: Run database migrations
echo ""
echo "🗄️  Step 4: Running database migrations..."
echo "   Note: This requires Cloud SQL Proxy access"
echo ""

# Step 6: Seed initial data
echo "🌱 Step 5: Seeding initial data..."
cat << 'SQL'
Run this in Cloud Shell or via cloud-sql-proxy:

cd api
DATABASE_URL='postgres://nesf_core:PASSWORD@/nesf_core?host=/cloudsql/thenesports-api-prod:asia-south1:thenesports-db' \
  SEED_ADMIN_EMAIL='biki@nesportsfoundation.in' \
  SEED_ADMIN_PASSWORD='ChangeMe@123' \
  npm run seed

SQL

echo ""
echo "🎉 Deployment complete!"
echo "   - API: https://$DOMAIN/api"
echo "   - Web: https://$DOMAIN"
echo "   - Health: https://$DOMAIN/health"
echo ""
echo "📱 APK: NESF-Core-production.apk"
echo ""
