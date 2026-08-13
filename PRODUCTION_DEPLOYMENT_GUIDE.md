# NESF Core: Production Deployment Guide

**Status:** Ready for Production Deploy ✅  
**Date:** 2026-08-13  
**Production APK:** `NESF-Core-production.apk` (arm64-v8a, 19.7 MB)

---

## 🎯 What Changed

✅ **Fixed production URLs:**
- `vercel.json` → API base: `https://app.nesportsfoundation.in`
- `app/lib/config.dart` → Production origin: `https://app.nesportsfoundation.in`
- **Built production APK** with correct endpoint

---

## 🚀 Deployment Path: Choose One

### Option A: Cloud Run + Cloud SQL (Recommended for Production)

**Pros:**
- Single-origin deployment (web + API from one service)
- Native Google Cloud integration with NESF Foundation's existing infrastructure
- Better for sensitive staff data (HR/CRM system)
- Auto-scaling, native cert management

**Setup Time:** ~45 minutes (GCP access required)

Follow: [DEPLOYMENT.md](DEPLOYMENT.md) - Steps 1-7

**Quick start:**
```bash
# Step 1: Create database
gcloud sql databases create nesf_core --instance=thenesports-db
gcloud sql users create nesf_core --instance=thenesports-db --password='<strong-password>'

# Step 2: Migrate schema
cd api
DATABASE_URL='postgres://nesf_core:<password>@localhost:5433/nesf_core' npm run migrate
DATABASE_URL='postgres://nesf_core:<password>@localhost:5433/nesf_core' \
  SEED_ADMIN_EMAIL='biki@nesportsfoundation.in' \
  SEED_ADMIN_PASSWORD='<temp-password>' npm run seed

# Step 3: Deploy to Cloud Run
gcloud builds submit --config=cloudbuild.yaml .

# Step 4: Configure domain
gcloud beta run domain-mappings create \
  --service=nesf-core-api \
  --domain=app.nesportsfoundation.in \
  --region=asia-south1

# Step 5: Add DNS in Cloudflare
# (Use CNAME from step 4 output, DNS only, not proxied)
```

---

### Option B: Vercel (Current Setup)

**Pros:**
- Already configured
- Faster initial deployment
- Lower operational overhead

**Cons:**
- Separate API/web deployments
- Less suitable for HR/sensitive data long-term

**Setup Time:** ~15 minutes

```bash
# Step 1: Deploy API to Vercel
cd api
vercel deploy --prod

# Step 2: Set Vercel environment variables
# DATABASE_URL, JWT_SECRET, NODE_ENV=production, CORS_ORIGINS

# Step 3: Update web app environment
# API_BASE → new Vercel API URL

# Step 4: Redeploy web app
cd .. && vercel deploy --prod
```

---

## 📱 Android APK: Ready to Deploy

**File:** `NESF-Core-production.apk`  
**Size:** 19.7 MB (arm64-v8a - most devices)  
**Endpoint:** `https://app.nesportsfoundation.in` ✅  
**Built:** 2026-08-13

### Deployment to Staff Devices

1. **Local Testing** (Recommended):
   ```bash
   # Install on connected device/emulator
   adb install -r NESF-Core-production.apk
   
   # Test:
   # - Login with admin credentials
   # - Check attendance check-in
   # - Verify API connection
   ```

2. **Distribution Methods**:
   - **USB cable** (quickest for first rollout)
   - **QR code link** (if hosted on server)
   - **Google Play Store** (requires signing key + review, 1-3 days)
   - **Firebase App Distribution** (recommended for beta testing)

### For Play Store (Future)

```bash
# Generate release signing key (one-time)
keytool -genkey -v -keystore nesf-core-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload

# Create app/android/key.properties with:
# storeFile=../nesf-core-upload.jks
# storePassword=<password>
# keyAlias=upload
# keyPassword=<password>

# Rebuild with signing:
cd app
flutter build appbundle --release \
  --dart-define=API_BASE=https://app.nesportsfoundation.in
```

---

## ✅ Pre-Deployment Checklist

### Configuration
- [x] Production URLs updated (vercel.json, config.dart)
- [x] Production APK built with correct endpoint
- [ ] Database credentials secured (Cloud SQL or Supabase)
- [ ] JWT secret generated and stored securely
- [ ] Signing key for APK created (if Play Store release)

### Database
- [ ] Schema migrated
- [ ] Admin account seeded: `biki@nesportsfoundation.in`
- [ ] Leave types configured
- [ ] TA/DA rates configured
- [ ] Holidays configured

### Deployment
- [ ] Choose Option A (Cloud Run) or Option B (Vercel)
- [ ] Deploy API with correct DATABASE_URL and JWT_SECRET
- [ ] Configure domain DNS (app.nesportsfoundation.in)
- [ ] Set CORS_ORIGINS correctly
- [ ] Verify SSL certificate issued

### Testing
- [ ] Health check: `curl https://app.nesportsfoundation.in/health`
- [ ] Login works: admin credentials
- [ ] Web app loads dashboard
- [ ] APK tested on at least one device
- [ ] Staff can check in attendance

### Post-Deploy
- [ ] Admin changes seeded password immediately
- [ ] Signature upload configured
- [ ] Geofence location set
- [ ] Staff briefed on new system
- [ ] Backup strategy verified

---

## 🔐 Security Checklist

- [ ] HTTPS enabled on all endpoints
- [ ] Database password strong (≥20 chars, mixed case/numbers/symbols)
- [ ] JWT_SECRET regenerated and not committed to git
- [ ] Database user has least-privilege permissions
- [ ] Storage bucket (Cloud Storage/S3) not publicly readable
- [ ] API rate limiting enabled
- [ ] CORS restricted to known domains only
- [ ] Sensitive data (salaries, leaves) not logged
- [ ] Staff data encrypted in transit (HTTPS) and at rest

---

## 📊 Architecture

```
┌──────────────────────────────┐
│   Staff Phones (Android APK) │
│   + Flutter Web Browser      │
│   https://app.nesportsfoundation.in
└──────────────┬───────────────┘
               │
               ↓
┌──────────────────────────────┐
│  API Server                  │
│  (Cloud Run or Vercel)       │
│  /api/attendance             │
│  /api/leave                  │
│  /api/approval               │
│  /media/<key> (private)      │
└──────────────┬───────────────┘
               │
               ↓
┌──────────────────────────────┐
│  PostgreSQL Database         │
│  (Cloud SQL or Supabase)     │
│  - Employees & Auth          │
│  - Attendance Records        │
│  - Leave Requests            │
│  - Approval Chain            │
└──────────────────────────────┘
```

---

## 🆘 Quick Troubleshooting

| Problem | Fix |
|---------|-----|
| APK crashes on startup | Check API_BASE matches deployed URL |
| Login fails | Verify admin user seeded: `SELECT * FROM employees WHERE role='admin'` |
| "Connection refused" | Database URL wrong or database not running |
| CORS error in web app | Add domain to CORS_ORIGINS in API env vars |
| SSL certificate pending | Wait 30 minutes or check domain mapping status |
| Domain not resolving | Verify CNAME in Cloudflare DNS (grey cloud, not proxied) |

---

## 📝 Next Steps

**Choose your deployment path:**

1. **Cloud Run (Recommended)**
   - More secure for HR/sensitive data
   - Run steps in [DEPLOYMENT.md](DEPLOYMENT.md)
   - ~45 minutes

2. **Vercel (Faster)**
   - Use existing setup
   - Follow Option B above
   - ~15 minutes

**Then distribute APK:**
   - Test on device first
   - Share with staff
   - Brief them on login

---

**Questions?** Check DEPLOYMENT.md for Cloud Run details or DEPLOYMENT_CHECKLIST.md for Supabase/Vercel details.

**Status:** Production APK ready ✅ | Awaiting deployment decision ⏳
