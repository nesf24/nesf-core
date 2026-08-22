# NESF Core - Rotated Credentials
**Date:** 2026-08-15  
**Status:** ⚠️ NEW CREDENTIALS GENERATED - MANUAL STEPS REQUIRED

---

## New Credentials (Keep Secure - Delete After Deployment)

### JWT Secret (New)
```
1d5699e240100c6e797dc960ed9193cb15a3879a01476e07137622fbe441c64fd8b0f4799a1767270ce38281ab00017d
```
**Where to update:**
- Google Secret Manager: `nesf-core-jwt-secret`
- Cloud Run environment variables

### Database Password (New)
```
NHkqdjmVkHfaPXC899TclbxqrYm5Tc4V
```
**Where to update:**
- Supabase console: Settings > Database > Users > postgres
- Google Cloud SQL: gcloud sql users set-password
- Google Secret Manager: `nesf-core-db-password`
- Cloud Run environment variables

### Android Keystore Password (New)
```
6f6gLjTMwJHp4F0YEqcV2PfYeTHsENDE
```
**Where to update:**
- `app/android/key.properties` (already done ✅)

---

## Files Already Updated ✅

- ✅ `api/.env.supabase` - New database password & JWT inserted
- ✅ `api/.env.local` - Created for local development
- ✅ `app/android/key.properties` - Created with new keystore password

---

## Manual Steps Required (TODAY)

### STEP 1: Update Supabase Database Password

```bash
# 1. Log in to https://app.supabase.com
# 2. Select "NESF Core" project
# 3. Navigate to: Settings > Database > Users
# 4. Find and click on "postgres" user
# 5. Click "Reset Password"
# 6. Enter new password: NHkqdjmVkHfaPXC899TclbxqrYm5Tc4V
# 7. Confirm the change
```

**Verification:** After 2-3 minutes, the change should take effect

### STEP 2: Update Google Cloud SQL Password

**Option A: Using gcloud CLI (Recommended)**

```bash
gcloud sql users set-password postgres \
  --instance=thenesports-db \
  --password=NHkqdjmVkHfaPXC899TclbxqrYm5Tc4V \
  --project=thenesports-api-prod
```

**Option B: Using Cloud Console**

```
1. Open: https://console.cloud.google.com/sql
2. Click: thenesports-db
3. Click: Users tab
4. Click: postgres user
5. Click: Edit
6. Enter password: NHkqdjmVkHfaPXC899TclbxqrYm5Tc4V
7. Click: Save
```

### STEP 3: Update Google Secret Manager

These commands update the secrets used by Cloud Run:

```bash
# Update database password secret
echo "NHkqdjmVkHfaPXC899TclbxqrYm5Tc4V" | \
  gcloud secrets versions add nesf-core-db-password \
  --data-file=- \
  --project=thenesports-api-prod

# Update JWT secret
echo "1d5699e240100c6e797dc960ed9193cb15a3879a01476e07137622fbe441c64fd8b0f4799a1767270ce38281ab00017d" | \
  gcloud secrets versions add nesf-core-jwt-secret \
  --data-file=- \
  --project=thenesports-api-prod
```

**Verify updates:**
```bash
gcloud secrets versions access latest --secret=nesf-core-db-password --project=thenesports-api-prod
gcloud secrets versions access latest --secret=nesf-core-jwt-secret --project=thenesports-api-prod
```

### STEP 4: Test Local Setup

```bash
cd D:\new app\nesf-core

# Install dependencies
npm install

# Test database migration
npm run migrate

# (Optional) Seed test data
npm run seed

# (Optional) Start dev server
npm start
```

Expected output:
```
✅ Database connection successful
✅ Migrations applied
✅ Server running on http://localhost:4000
```

### STEP 5: Deploy to Production

Once you've verified the local setup works:

```bash
# Deploy to Cloud Run with new environment variables
gcloud run deploy nesf-core-api \
  --region=asia-south1 \
  --project=thenesports-api-prod \
  --update-env-vars \
  DATABASE_URL=$(gcloud secrets versions access latest --secret=nesf-core-db-password --project=thenesports-api-prod) \
  JWT_SECRET=$(gcloud secrets versions access latest --secret=nesf-core-jwt-secret --project=thenesports-api-prod)
```

Or use the shorter form:
```bash
gcloud run deploy nesf-core-api \
  --region=asia-south1 \
  --project=thenesports-api-prod
```

Cloud Run will use the Secret Manager values automatically.

### STEP 6: Verify Production

```bash
# Test health check
curl -sS https://app.nesportsfoundation.in/health

# Check logs
gcloud run services logs read nesf-core-api \
  --region=asia-south1 \
  --project=thenesports-api-prod \
  --limit=50
```

Expected:
- Health check returns: `{"status":"ok"}`
- Logs show no errors or "401 Unauthorized"

### STEP 7: Change Admin Password

After the new JWT secret is deployed:

```bash
# Method 1: Via API
curl -X POST https://app.nesportsfoundation.in/api/auth/change-password \
  -H "Authorization: Bearer <your-jwt-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "oldPassword": "ChangeMe@123",
    "newPassword": "NewSecurePassword@2026"
  }'

# Method 2: Via app UI
# 1. Login with: biki@nesportsfoundation.in
# 2. Password: ChangeMe@123
# 3. Go to Profile Settings
# 4. Change password
```

---

## Timeline

| Step | Time | Status |
|------|------|--------|
| Update Supabase | 5 min | ⏳ Manual |
| Update Cloud SQL | 5 min | ⏳ Manual |
| Update Secret Manager | 5 min | ⏳ CLI |
| Test locally | 10 min | ⏳ Pending |
| Deploy to production | 5 min | ⏳ Pending |
| Verify production | 5 min | ⏳ Pending |
| Change admin password | 5 min | ⏳ Pending |
| **TOTAL** | **~40 min** | |

---

## Rollback (If Something Goes Wrong)

### If production breaks after deployment:

1. **Immediate:** Revert to previous Cloud Run revision
   ```bash
   gcloud run rollouts create \
     --revision=<previous-revision-id> \
     nesf-core-api \
     --region=asia-south1 \
     --project=thenesports-api-prod
   ```

2. **Check logs for errors:**
   ```bash
   gcloud run services logs read nesf-core-api \
     --region=asia-south1 \
     --project=thenesports-api-prod \
     --limit=100
   ```

3. **Common issues:**
   - `401 Unauthorized` → JWT secret mismatch
   - `Connection refused` → Database password wrong
   - `DATABASE_URL not found` → Secret Manager not updated

---

## After Deployment - Optional Git Cleanup

Once credentials are rotated and production is stable, optionally clean git history to remove traces:

```bash
# Clean git history (requires force-push)
# See: SECURITY_REMEDIATION.md, Phase C & D
```

---

## Security Checklist

- [ ] Supabase password changed
- [ ] Cloud SQL password changed
- [ ] Google Secret Manager updated (both secrets)
- [ ] Local setup tested (npm run migrate works)
- [ ] Production deployed
- [ ] Health check working: https://app.nesportsfoundation.in/health
- [ ] Logs show no errors
- [ ] Admin password changed
- [ ] Old credentials deleted/archived
- [ ] Git history cleaned (optional)

---

## Questions?

Refer to:
- `SECURITY_REMEDIATION.md` - Detailed step-by-step procedures
- `SECURITY.md` - Complete security policy
- `SECURITY_STATUS.md` - Progress tracking

---

**DELETE THIS FILE after deployment is complete and verified.**
