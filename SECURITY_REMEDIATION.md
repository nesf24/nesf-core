# NESF Core Security Remediation Guide

## ⚠️ CRITICAL: Exposed Credentials in Git History

This guide provides step-by-step instructions to remediate the security breach where database passwords, JWT secrets, and Android keystore passwords were committed to git.

**Severity:** 🔴 CRITICAL  
**Time to Complete:** ~30 minutes  
**Risk if Ignored:** Unauthorized database access, forged authentication tokens, compromised app signing

---

## Summary of Exposed Secrets

| Secret | Location | Exposed Value | Severity |
|--------|----------|---|---|
| DB Password (Supabase) | `.env.supabase` | `NEsports@#2026` | 🔴 CRITICAL |
| DB Password (Cloud SQL) | `DEPLOYMENT_STATUS.md` | `NEsf@Core2026#Prod!Secure` | 🔴 CRITICAL |
| JWT Secret (Old) | `.env.supabase` + `DEPLOYMENT_STATUS.md` | See SECURITY.md | 🔴 CRITICAL |
| Admin Password | `.env`, `DEPLOYMENT_STATUS.md` | `ChangeMe@123` | 🟡 HIGH |
| Android Keystore Password | `build.gradle.kts` | `nesf_core_2026` | 🔴 CRITICAL |

**Status:** ✅ Mitigated locally (secrets removed from working copy)  
**Status:** ❌ NOT YET fixed in git history (still accessible in all commits)

---

## Phase A: Immediate Local Actions (RIGHT NOW - No Git Changes Yet)

### Step 1: Verify Fixes Were Applied

These were already done:
- ✅ `.env.supabase` - redacted with warnings
- ✅ `.env` - redacted with warnings
- ✅ `DEPLOYMENT_STATUS.md` - redacted with warnings
- ✅ `build.gradle.kts` - converted to use key.properties
- ✅ `.gitignore` - enhanced with secret patterns
- ✅ `SECURITY.md` - created with remediation procedures
- ✅ `.env.example` - created without secrets
- ✅ `.env.supabase.example` - created without secrets
- ✅ `key.properties.example` - created without secrets

### Step 2: Verify Current State

```bash
cd D:\new app\nesf-core

# Check that current .env files have been redacted
cat api/.env | grep -i password    # Should show: CHANGE_PASSWORD_IMMEDIATELY or ROTATE_THIS_IMMEDIATELY
cat api/.env.supabase | grep -i password

# Verify .gitignore additions
cat .gitignore | grep "\.env"   # Should show multiple .env patterns
cat .gitignore | grep "\.jks"   # Should show keystore patterns
```

**Expected Output:** All real passwords replaced with warnings

---

## Phase B: Credential Rotation (Before Pushing to Git)

### Step 1: Rotate Supabase Database Password

**Current Exposed Password:** `NEsports@#2026`

```bash
# 1. Log in to Supabase console: https://app.supabase.com

# 2. Select the NESF Core project
# 3. Go to Settings > Database > Users
# 4. Click on the "postgres" user
# 5. Click "Reset Password"
# 6. Copy the new password (will be displayed once)
# 7. Update it in your secure password manager

# 8. From your terminal, update .env.supabase with the new password:
# DATABASE_URL=postgres://postgres:NEW_PASSWORD@mixbtfnjdzmfbctkxnwk.supabase.co:5432/postgres?sslmode=require
```

### Step 2: Rotate Cloud SQL Database Password

**Current Exposed Password:** `NEsf@Core2026#Prod!Secure`

```bash
# If using Cloud SQL (production):
gcloud sql users set-password postgres \
  --instance=thenesports-db \
  --password=$(openssl rand -base64 32) \
  --project=thenesports-api-prod

# This will output the new password - SAVE IT
# Then update Google Secret Manager:
echo "NEW_PASSWORD_HERE" | gcloud secrets versions add nesf-core-db-password \
  --data-file=- \
  --project=thenesports-api-prod

# Verify update:
gcloud secrets versions access latest --secret=nesf-core-db-password \
  --project=thenesports-api-prod
```

### Step 3: Generate New JWT Secret

**Current Exposed Secrets:** See SECURITY.md

```bash
# Generate new JWT secret
NEW_JWT=$(node -e "console.log(require('crypto').randomBytes(48).toString('hex'))")
echo "New JWT Secret: $NEW_JWT"

# Update Google Secret Manager (for production Cloud Run)
echo "$NEW_JWT" | gcloud secrets versions add nesf-core-jwt-secret \
  --data-file=- \
  --project=thenesports-api-prod

# Update local .env.supabase for development
# JWT_SECRET=<paste-new-jwt-here>

# IMPACT: All existing tokens become INVALID
# - Users will be logged out automatically (tokens expire or invalid signature)
# - Next login will get new token with new secret
# Timeline: Deploy this change at off-hours to minimize disruption
```

### Step 4: Change Admin Password

**Current Exposed Password:** `ChangeMe@123`

```bash
# Method 1: Via API (after deployment)
curl -X POST https://app.nesportsfoundation.in/api/auth/change-password \
  -H "Authorization: Bearer <your-jwt-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "oldPassword": "ChangeMe@123",
    "newPassword": "NewSecurePassword@2026"
  }'

# Method 2: Via database
# DANGEROUS - use API method instead
# psql: UPDATE employees SET password_hash = crypt('NewSecurePassword@2026', gen_salt('bf', 10)) WHERE email = 'biki@nesportsfoundation.in'
```

### Step 5: Regenerate Android Keystore

**Current Exposed Password:** `nesf_core_2026`

```bash
# WARNING: This will make old APK signatures invalid
# Only do this if the keystore password has been compromised

# Step 1: Backup old keystore
cp app/android/nesf-core-key.jks app/android/nesf-core-key.jks.backup

# Step 2: Delete old keystore
rm app/android/nesf-core-key.jks

# Step 3: Generate new keystore
keytool -genkey -v \
  -keystore app/android/nesf-core-key.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias nesf-core-key \
  -storepass <NEW_KEYSTORE_PASSWORD> \
  -keypass <NEW_KEY_PASSWORD>

# Step 4: Create key.properties file (GITIGNORED)
cat > app/android/key.properties << EOF
storeFile=../nesf-core-key.jks
storePassword=<NEW_KEYSTORE_PASSWORD>
keyAlias=nesf-core-key
keyPassword=<NEW_KEY_PASSWORD>
EOF

# Step 5: Verify new APK can be built
cd app
flutter build apk --release
cd ..

# Step 6: Upload new APK to Play Store
# Old APK will still install (different signing key = different APK)
# New releases MUST use new keystore
# Users CANNOT auto-update from old APK to new APK (different signature)
# Workaround: Uninstall old, install new
```

---

## Phase C: Clean Git History (Destructive - Requires Force Push)

⚠️ **WARNING:** This rewrites git history and requires all team members to re-clone. Coordinate with your team before proceeding.

### Prerequisites

- All team members have pushed their changes
- No work-in-progress on local branches
- Decision made to rewrite history (vs. ignoring old commits)

### Option 1: Using BFG Repo-Cleaner (Recommended, Safer)

**Download:** https://rtyley.github.io/bfg-repo-cleaner/

```bash
cd D:\new app\nesf-core

# 1. Create fresh clone (so original is backed up)
cd ..
git clone --mirror nesf-core nesf-core-backup.git

# 2. Use BFG to remove exposed secrets
# Remove .env files from all commits
java -jar bfg.jar --delete-files '.env*' --no-blob-protection nesf-core-backup.git

# 3. Remove password strings from files
java -jar bfg.jar --replace-text <(echo 'NEsports@#2026==>REDACTED') --no-blob-protection nesf-core-backup.git
java -jar bfg.jar --replace-text <(echo 'NEsf@Core2026#Prod!Secure==>REDACTED') --no-blob-protection nesf-core-backup.git
java -jar bfg.jar --replace-text <(echo 'nesf_core_2026==>REDACTED') --no-blob-protection nesf-core-backup.git
java -jar bfg.jar --replace-text <(echo 'de1d34de38b1a41f344751de4405276de8b9e3a82bbf7665a652b190635b8cfa372baef6068b8106bd1725ea412095e9==>REDACTED') --no-blob-protection nesf-core-backup.git

# 4. Clean up git
cd nesf-core-backup.git
git reflog expire --expire=now --all
git gc --prune=now --aggressive
cd ..

# 5. Replace original with cleaned version
rm -rf nesf-core/.git
git clone nesf-core-backup.git nesf-core
cd nesf-core
git log --oneline | head -5  # Verify history is cleaned
```

### Option 2: Using Git Filter Branch (Built-in, More Complex)

```bash
cd D:\new app\nesf-core

# 1. Remove .env files from ALL commits
git filter-branch --force --index-filter \
  'git rm --cached --ignore-unmatch .env .env.supabase DEPLOYMENT_STATUS.md' \
  --prune-empty --tag-name-filter cat -- --all

# 2. Clean refs
rm -rf .git/refs/original/
git reflog expire --expire=now --all
git gc --prune=now --aggressive

# 3. Push to origin (requires force-push permission)
git push --force-with-lease origin main
# or
git push --force-with-lease origin master
```

### After Rewriting History

**All team members must re-clone:**

```bash
# For each team member:
cd ~
rm -rf nesf-core              # Delete old clone
git clone <repo-url> nesf-core  # Fresh clone from origin
cd nesf-core
git log --oneline | head -5   # Verify history is cleaned
```

---

## Phase D: Verify Clean Repository

After git history cleanup, verify:

```bash
# 1. No secrets in current HEAD
git show HEAD:api/.env        # Should fail (file not present)
git show HEAD:DEPLOYMENT_STATUS.md | grep -i password  # Should show: REDACTED (if file exists)

# 2. No secrets in recent history
git log -p -- api/.env | grep "NEsports"  # Should output nothing
git log -p -- api/.env.supabase | grep "NEsports"  # Should output nothing

# 3. Secrets are in .gitignore
cat .gitignore | grep "\.env"  # Should show .env* patterns
cat .gitignore | grep "\.jks"  # Should show *.jks pattern

# 4. No APK files in history
git log --all --name-only | grep "\.apk"  # Should output nothing
```

**Expected:** All commands return nothing or "file not found"

---

## Phase E: Post-Rotation Deployment

### For Development (Local Testing)

```bash
cd D:\new app\nesf-core

# 1. Create fresh .env.local (NOT committed)
cp api/.env.example api/.env.local

# 2. Fill in test values
# DATABASE_URL=postgres://localhost:5432/nesf_core_dev
# JWT_SECRET=<your-test-secret>

# 3. Test connection
npm run migrate    # Should succeed
npm run seed       # Should succeed
npm start          # Server should start
```

### For Production (Cloud Run)

```bash
# 1. Deploy updated Cloud Run service with new secrets
gcloud run deploy nesf-core-api \
  --region=asia-south1 \
  --project=thenesports-api-prod \
  --update-env-vars DATABASE_URL=$(gcloud secrets versions access latest --secret=nesf-core-db-password --project=thenesports-api-prod) \
  --update-env-vars JWT_SECRET=$(gcloud secrets versions access latest --secret=nesf-core-jwt-secret --project=thenesports-api-prod)

# 2. Verify health check
curl -sS https://app.nesportsfoundation.in/health

# 3. Check logs for errors
gcloud run services logs read nesf-core-api \
  --region=asia-south1 \
  --project=thenesports-api-prod \
  --limit=50
```

### For Mobile App

```bash
# 1. Update api.dart with new API URL (if changed)
# lib/services/api.dart: static const String BASE_URL = "https://app.nesportsfoundation.in/api"

# 2. Test login on device
# Users should be logged out (old tokens invalid)
# Login with biki@nesportsfoundation.in and new password

# 3. Build new APK if keystore was regenerated
cd app
flutter build apk --release
# Upload NESF-Core-<version>.apk to Play Store Internal Testing
```

---

## Phase F: Timeline & Checklist

### ✅ COMPLETED (Just Now)
- [x] Created SECURITY.md with remediation procedures
- [x] Created .env.example without secrets
- [x] Redacted .env files with warnings
- [x] Redacted DEPLOYMENT_STATUS.md
- [x] Fixed build.gradle.kts to use key.properties
- [x] Enhanced .gitignore with secret patterns
- [x] Created key.properties.example

### ⏳ TODO (Next Steps)

**TODAY (Immediate - 30 minutes):**
- [ ] Rotate Supabase database password
- [ ] Rotate Cloud SQL database password (if applicable)
- [ ] Generate new JWT secret
- [ ] Change admin password
- [ ] Create key.properties file locally
- [ ] Test local dev setup with new secrets

**THIS WEEK (Before next deployment):**
- [ ] Decide on git history cleanup (with team)
- [ ] If yes: Run BFG or git-filter-branch
- [ ] Force-push to origin
- [ ] Have all team members re-clone
- [ ] Deploy new secrets to Cloud Run
- [ ] Verify production health check

**NEXT RELEASE:**
- [ ] Build and sign new APK with new keystore (if regenerated)
- [ ] Upload to Play Store Internal Testing
- [ ] Have QA verify login works (users logged out, can re-login)
- [ ] Promote to production

### 📋 Checklist Before Go-Live

- [ ] All exposed passwords changed
- [ ] Git history cleaned (if decided)
- [ ] All team members re-cloned (if git history changed)
- [ ] Local .env.local works with new secrets
- [ ] Cloud Run deployed with new secrets
- [ ] Health check returns 200: `curl https://app.nesportsfoundation.in/health`
- [ ] Admin can login with new password
- [ ] New APK built if keystore changed
- [ ] APK tested on 2+ devices
- [ ] No "401 Unauthorized" errors in logs (means JWT secret is correct)

---

## Rollback Plan

If something goes wrong:

### Git History Rewrite Fails

```bash
# Restore from backup
rm -rf .git
git clone nesf-core-backup.git .
git status  # Should show clean

# Or restore from origin
git fetch origin main
git reset --hard origin/main
```

### Credentials Already Leaked Elsewhere

If you discover credentials were leaked outside git (e.g., in Slack, logs, backups):

1. **Immediately** rotate ALL passwords (database, JWT, admin, keystore)
2. **Audit logs** for unauthorized access:
   ```bash
   gcloud sql operations list --instance=thenesports-db  # Check for unusual activity
   gcloud run services logs read nesf-core-api --limit=1000  # Check for errors/access
   ```
3. **Freeze deployments** until investigation complete
4. **Review permissions** - Was there unauthorized database access?
5. **Restore from backup** if data was modified:
   ```bash
   gcloud sql backups list --instance=thenesports-db
   gcloud sql backups restore BACKUP_ID --backup-instance=thenesports-db
   ```

### New APK Build Fails After Keystore Change

```bash
# Old APK still works (users not forced to update)
# Users can temporarily use old APK while you fix build

# Common issues:
# 1. key.properties not found → Create it from key.properties.example
# 2. Wrong password → Verify with: keytool -list -v -keystore app/android/nesf-core-key.jks
# 3. Keystore corrupted → Regenerate: keytool -genkey -v -keystore ...
```

---

## Questions?

Refer to `SECURITY.md` for detailed sections on:
- Credential management procedures
- Authentication & authorization model
- Data protection standards
- Incident response playbook
- Best practices for developers & operations

---

## Final Reminder

🔴 **This is a security incident. Take it seriously.**

- Don't skip any steps
- Coordinate with your team
- Test thoroughly before announcing "fixed"
- Monitor logs closely for 24 hours after rotation
- Archive this document for future reference
