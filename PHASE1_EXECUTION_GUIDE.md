# Phase 1 Execution Guide - Complete with You
**Status:** Ready for immediate execution  
**Time:** ~30 minutes  
**Complexity:** Low (copy-paste commands + browser clicks)

---

## Summary

You're already logged into Chrome with both Supabase and Google Cloud. I'll guide you through 5 quick steps to complete Phase 1.

**Files already created and ready:**
- ✅ `api/.env.supabase` - New database password already inserted
- ✅ `api/.env.local` - New JWT secret already inserted
- ✅ `app/android/key.properties` - New keystore password already inserted

**What you need to do:**
1. Rotate Supabase password (5 min) - Browser clicks
2. Rotate Cloud SQL password (5 min) - Browser clicks  
3. Update Google Secret Manager (5 min) - Copy-paste CLI commands
4. Test locally (5 min) - Copy-paste CLI commands
5. Deploy to production (5 min) - Copy-paste CLI commands

---

## Step 1: Rotate Supabase Database Password (5 min)

**Your new password:** `NHkqdjmVkHfaPXC899TclbxqrYm5Tc4V`

### Instructions:

1. Open Supabase in Chrome: https://app.supabase.com
2. Select **NESF Core** project (top-left dropdown)
3. Click **Settings** (bottom-left sidebar)
4. Click **Database**
5. Look for **postgres** user in the Users table
6. Click the **postgres** row
7. Click the **Reset Password** button
8. Copy and paste this password:
   ```
   NHkqdjmVkHfaPXC899TclbxqrYm5Tc4V
   ```
9. Click **Reset**
10. Wait 2-3 seconds for confirmation
11. ✅ Done!

**Expected:** You should see "Password reset successfully"

---

## Step 2: Rotate Cloud SQL Password (5 min)

**Your new password:** `NHkqdjmVkHfaPXC899TclbxqrYm5Tc4V`

### Instructions:

1. Open Google Cloud Console in Chrome: https://console.cloud.google.com/sql/instances
2. Click **thenesports-db** instance
3. Click the **Users** tab
4. Find **postgres** user in the list
5. Click the **3-dot menu** (⋮) next to postgres
6. Click **Edit**
7. Paste this new password:
   ```
   NHkqdjmVkHfaPXC899TclbxqrYm5Tc4V
   ```
8. Confirm the password (paste again)
9. Click **Save**
10. Wait 10-15 seconds for update
11. ✅ Done!

**Expected:** Password update takes ~30 seconds, then shows "Updated successfully"

---

## Step 3: Update Google Secret Manager (5 min)

Open PowerShell or Terminal and run these commands (copy-paste each one):

### Command 3A: Update Database Password Secret

```powershell
echo "NHkqdjmVkHfaPXC899TclbxqrYm5Tc4V" | gcloud secrets versions add nesf-core-db-password --data-file=- --project=thenesports-api-prod
```

**Expected output:**
```
Created version [1] of the secret [nesf-core-db-password].
```

### Command 3B: Update JWT Secret

```powershell
echo "1d5699e240100c6e797dc960ed9193cb15a3879a01476e07137622fbe441c64fd8b0f4799a1767270ce38281ab00017d" | gcloud secrets versions add nesf-core-jwt-secret --data-file=- --project=thenesports-api-prod
```

**Expected output:**
```
Created version [1] of the secret [nesf-core-jwt-secret].
```

### Verification Commands (run these to verify):

```powershell
# Should output: NHkqdjmVkHfaPXC899TclbxqrYm5Tc4V
gcloud secrets versions access latest --secret=nesf-core-db-password --project=thenesports-api-prod

# Should output your JWT secret
gcloud secrets versions access latest --secret=nesf-core-jwt-secret --project=thenesports-api-prod
```

---

## Step 4: Test Local Setup (5 min)

Open PowerShell in the project directory and run:

```powershell
cd "D:\new app\nesf-core"

# Test API setup
npm run migrate

# Test seed data (optional)
npm run seed
```

**Expected output for `npm run migrate`:**
```
✅ Database migrations applied successfully
✅ Connected to: postgres://...
✅ All tables created
```

**If you get errors:**
- "Connection refused" → Database password wrong
- "Authentication failed" → JWT secret not deployed yet (it's OK, will work after Cloud Run deployment)

---

## Step 5: Deploy to Production (5 min)

Run this command in PowerShell:

```powershell
gcloud run deploy nesf-core-api `
  --region=asia-south1 `
  --project=thenesports-api-prod `
  --update-env-vars DATABASE_URL=$(gcloud secrets versions access latest --secret=nesf-core-db-password --project=thenesports-api-prod) `
  --update-env-vars JWT_SECRET=$(gcloud secrets versions access latest --secret=nesf-core-jwt-secret --project=thenesports-api-prod)
```

**This will:**
1. Pull the new database password from Secret Manager
2. Pull the new JWT secret from Secret Manager  
3. Deploy to Cloud Run with these new environment variables
4. Takes ~2-3 minutes to deploy

**Expected output:**
```
Service [nesf-core-api] revision [xxxxxxxx] has been deployed and is serving 100 percent of traffic.
```

---

## Step 6: Verify Production (5 min)

### Test Health Check

```powershell
curl -sS https://app.nesportsfoundation.in/health
```

**Expected output:**
```
{"status":"ok"}
```

### Check Logs

```powershell
gcloud run services logs read nesf-core-api --region=asia-south1 --project=thenesports-api-prod --limit=20
```

**Expected:** No errors like "401 Unauthorized" or "Connection refused"

---

## Step 7: Change Admin Password (5 min)

Once everything is verified working, log in to the app and change the admin password:

### Option A: Via Browser

1. Open: https://app.nesportsfoundation.in/
2. Login with: `biki@nesportsfoundation.in` / `ChangeMe@123`
3. Click Profile Settings
4. Change password to something new
5. ✅ Done!

### Option B: Via API

```powershell
# First, get a valid JWT token by logging in via the app
# Then run:

curl -X POST https://app.nesportsfoundation.in/api/auth/change-password `
  -H "Authorization: Bearer <your-jwt-token-from-login>" `
  -H "Content-Type: application/json" `
  -d "{
    \"oldPassword\": \"ChangeMe@123\",
    \"newPassword\": \"YourNewPassword@2026\"
  }"
```

---

## Checklist - Complete These In Order

```
BROWSER TASKS (Requires Chrome login):
[ ] Step 1: Supabase password rotation (5 min)
[ ] Step 2: Cloud SQL password rotation (5 min)

CLI TASKS (Copy-paste commands):
[ ] Step 3A: Update DB password secret (1 min)
[ ] Step 3B: Update JWT secret (1 min)
[ ] Step 3: Verify secrets (2 min)

LOCAL TESTING:
[ ] Step 4: npm run migrate (5 min)

PRODUCTION DEPLOYMENT:
[ ] Step 5: Cloud Run deployment (5 min)
[ ] Step 6: Verify production (5 min)

ADMIN PASSWORD:
[ ] Step 7: Change admin password (5 min)

TOTAL TIME: ~35-45 minutes
```

---

## Troubleshooting

### "Connection refused" when running npm run migrate

**Cause:** Database password is wrong  
**Fix:** Verify you used: `NHkqdjmVkHfaPXC899TclbxqrYm5Tc4V` in both Supabase and Cloud SQL

### Health check returns error

**Cause:** Cloud Run deployment hasn't picked up new secrets yet  
**Fix:** Wait 2 minutes and try again, or check logs:
```powershell
gcloud run services logs read nesf-core-api --region=asia-south1 --project=thenesports-api-prod --limit=50
```

### "401 Unauthorized" in logs

**Cause:** JWT secret mismatch  
**Fix:** Verify Secret Manager has correct JWT secret:
```powershell
gcloud secrets versions access latest --secret=nesf-core-jwt-secret --project=thenesports-api-prod
```

Should output: `1d5699e240100c6e797dc960ed9193cb15a3879a01476e07137622fbe441c64fd8b0f4799a1767270ce38281ab00017d`

---

## After Completion

Once all steps are verified working:

✅ Phase 1 is **COMPLETE**

Next: **Phase 2 Database Schema Verification** (1 day)
- Verify all database tables exist
- Document schema
- Create seed data

Then: **Phase 3 Web Deployment** (1 day)
- Configure for app.nesportsfoundation.in
- PWA/service worker
- CORS setup

---

## Credentials Reference

**Saved in:** `CREDENTIALS_2026-08-15.md`

```
Database Password: NHkqdjmVkHfaPXC899TclbxqrYm5Tc4V
JWT Secret: 1d5699e240100c6e797dc960ed9193cb15a3879a01476e07137622fbe441c64fd8b0f4799a1767270ce38281ab00017d
Keystore Password: 6f6gLjTMwJHp4F0YEqcV2PfYeTHsENDE
```

---

**Start with Step 1 now! Open Supabase in Chrome and reset the postgres password.**

Questions? Refer to `SECURITY_REMEDIATION.md` for detailed procedures.
