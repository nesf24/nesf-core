# NESF Core Security Policy

## Credential Management

### ⚠️ CRITICAL: Exposed Secrets (REMEDIATION REQUIRED)

The following credentials have been exposed in git history and must be rotated immediately:

**Database Credentials:**
- Supabase password: `NEsports@#2026` (in `.env.supabase`)
- Production password: `NEsf@Core2026#Prod!Secure` (in `DEPLOYMENT_STATUS.md`)
- **ACTION:** Change Supabase & Cloud SQL database passwords NOW

**JWT Secrets:**
- `de1d34de38b1a41f344751de4405276de8b9e3a82bbf7665a652b190635b8cfa372baef6068b8106bd1725ea412095e9` (in `.env.supabase`)
- `ce7b5514d34f9d9f443919c94a13dd7da98c7f02a01610ce8c446040b628afdcefee4665233a022242d0c2436cd74b77` (in `DEPLOYMENT_STATUS.md`)
- **ACTION:** Deploy new JWT secrets to Google Secret Manager. All existing tokens become invalid (users must re-login).

**Admin Account:**
- Initial password: `ChangeMe@123` (in multiple files)
- **ACTION:** Change admin password immediately after login

**Android Keystore:**
- Hardcoded password: `nesf_core_2026` (in `build.gradle.kts`)
- **ACTION:** Regenerate keystore, revoke old signing key if distributed

---

## Immediate Actions (Next 24 Hours)

### 1. Rotate Database Password

**Supabase:**
```bash
# Login to Supabase dashboard
# Navigate to Project Settings > Database > Users
# Click on 'postgres' user
# Change password from: NEsports@#2026
# To: <new-strong-password>
```

**Cloud SQL:**
```bash
gcloud sql users set-password postgres \
  --instance=thenesports-db \
  --password=<new-strong-password>
```

Then update:
- Google Secret Manager: `nesf-core-db-password`
- Local `.env.supabase`: `DATABASE_URL=...` with new password

### 2. Rotate JWT Secret

```bash
# Generate new JWT secret
node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"

# Example output: a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6a7b8c9d0

# Update Google Secret Manager
gcloud secrets versions add nesf-core-jwt-secret \
  --data-file=- <<< "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6a7b8c9d0"

# Update local .env.supabase
# JWT_SECRET=a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6a7b8c9d0
```

**Impact:** All users must re-authenticate (existing tokens invalid).

### 3. Change Admin Password

```bash
# Run seed with new password
SEED_ADMIN_EMAIL="biki@nesportsfoundation.in" \
SEED_ADMIN_PASSWORD="<new-strong-password>" \
npm run seed
```

Then change password via app UI after first login.

### 4. Regenerate Android Keystore

```bash
# Generate new keystore
keytool -genkey -v -keystore nesf-core-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias nesf-core-key

# Update build.gradle.kts to use environment variables
# See: Android Signing Configuration (below)
```

### 5. Remove Secrets from Git History

```bash
# Use BFG Repo-Cleaner (recommended, safer than git-filter-branch)
# Download: https://rtyley.github.io/bfg-repo-cleaner/

# Remove .env files from all commits
bfg --delete-files '.env*' --no-blob-protection

# Remove passwords from markdown files
bfg --replace-text <(echo "NEsports@#2026==>REDACTED") --no-blob-protection
bfg --replace-text <(echo "NEsf@Core2026#Prod!Secure==>REDACTED") --no-blob-protection
bfg --replace-text <(echo "nesf_core_2026==>REDACTED") --no-blob-protection

# Clean and push
git reflog expire --expire=now --all
git gc --prune=now --aggressive
git push --force-with-lease
```

**⚠️ WARNING:** This rewrites git history and requires force-push. All team members must re-clone the repository.

---

## Secure Configuration

### Environment Variables Setup

**For Local Development:**

```bash
# Create api/.env.local (add to .gitignore)
cp api/.env.example api/.env.local

# Edit with your local values:
DATABASE_URL=postgres://localhost:5432/nesf_core_dev
JWT_SECRET=<your-dev-secret-from-node-crypto>
SEED_ADMIN_PASSWORD=LocalTestPassword123!
```

**For Vercel/Cloud Run:**

Use Google Secret Manager or environment variable secrets:

```bash
# Cloud Run (via Secret Manager)
gcloud run services update nesf-core-api \
  --set-env-vars DATABASE_URL=$(gcloud secrets versions access latest --secret=nesf-core-db-password) \
  --set-env-vars JWT_SECRET=$(gcloud secrets versions access latest --secret=nesf-core-jwt-secret)

# Vercel (via dashboard)
# Settings > Environment Variables
# Add each secret with "Encrypted" toggle enabled
```

### .gitignore Configuration

Ensure the following patterns are in `.gitignore`:

```gitignore
# Environment variables (CRITICAL)
.env
.env.local
.env.*.local
.env.supabase
.env.example.local

# Android signing (CRITICAL)
key.properties
*.keystore
*.jks
/app/android/app/debug.keystore

# Build artifacts (optional but recommended)
*.apk
*.aab
build/
dist/
node_modules/
app/build/

# IDE & OS files
.vscode/
.idea/
*.swp
*.swo
.DS_Store
```

---

## Android Signing Configuration

### Current Issue

The `app/android/app/build.gradle.kts` has hardcoded keystore password:

```kotlin
signingConfigs {
    create("release") {
        keyAlias = "nesf-core-key"
        keyPassword = "nesf_core_2026"          // ❌ HARDCODED
        storeFile = file("../nesf-core-key.jks")
        storePassword = "nesf_core_2026"        // ❌ HARDCODED
    }
}
```

### Solution

**Step 1:** Create `app/android/key.properties` (gitignored):

```properties
storePassword=<your-keystore-password>
keyPassword=<your-key-password>
keyAlias=nesf-core-key
storeFile=../nesf-core-key.jks
```

**Step 2:** Update `build.gradle.kts`:

```kotlin
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    // ... rest of config
    
    signingConfigs {
        release {
            if (keystoreProperties.size() > 0) {
                keyAlias keystoreProperties['keyAlias']
                keyPassword keystoreProperties['keyPassword']
                storeFile file(keystoreProperties['storeFile'])
                storePassword keystoreProperties['storePassword']
            }
        }
    }
    
    buildTypes {
        release {
            signingConfig = signingConfigs.release
        }
    }
}
```

**Step 3:** For CI/CD, use environment variables in build script:

```bash
#!/bin/bash
cd app/android
echo "storePassword=${KEYSTORE_PASSWORD}" > key.properties
echo "keyPassword=${KEY_PASSWORD}" >> key.properties
echo "keyAlias=nesf-core-key" >> key.properties
echo "storeFile=../nesf-core-key.jks" >> key.properties

cd ..
flutter build apk --release
```

Then in GitHub Actions / Cloud Build secrets, set:
- `KEYSTORE_PASSWORD`
- `KEY_PASSWORD`

---

## Authentication & Authorization

### User Roles

| Role | Permissions | Data Access |
|------|---|---|
| **Admin** | All operations, staff management | All |
| **HR** | Attendance, leave, TA/DA approvals | All staff except super-admin |
| **Manager** | Approve reports, TA/DA, activities | Direct reports only |
| **Staff** | Submit forms, view own data | Own records only |

### JWT Token Structure

Tokens contain:
- `userId` - Unique identifier
- `role` - User role (determines API permissions)
- `exp` - Expiration (2 hours)
- `iat` - Issued at

Tokens are signed with `JWT_SECRET`. If secret is compromised, tokens can be forged.

### API Authentication

All `/api/*` endpoints except `/api/auth/login` require:

```bash
Authorization: Bearer <jwt-token>
```

The token is validated on every request:
1. Signature verified using `JWT_SECRET`
2. Expiration checked
3. Role checked against endpoint permission

If token is expired, client can refresh using refresh token.

---

## Data Protection

### Sensitive Data

- **Passwords:** Hashed with bcrypt (10 rounds)
- **Tokens:** Stored only in device secure storage (Flutter)
- **Files:** Encrypted at rest in Google Cloud Storage
- **Database:** Encrypted via Cloud SQL (AES-256)
- **Backups:** Daily, encrypted, 14-day retention

### Access Control

- **Database:** Only Cloud Run service account can access via Unix socket
- **Storage:** Only authenticated users can access via `/api/media/` endpoint
- **Files:** Individual user files (selfies, signatures) only readable by user + admin

### Audit Logging

All material changes logged to `audit_log` table:
- Who changed what, when, and from where (IP)
- Sensitive operations flagged (password change, role change, document approval)

---

## Incident Response

### If Credentials Leaked

1. **Immediate (< 1 hour):**
   - Rotate database password
   - Generate new JWT secret
   - Reset admin password

2. **Short-term (< 24 hours):**
   - Change Android keystore password
   - Rewrite git history with BFG
   - Force-push to origin (all team re-clones)

3. **Medium-term (< 1 week):**
   - Review audit logs for unauthorized access
   - Check file storage for data exfiltration
   - Monitor Cloud SQL slow query logs

4. **Long-term:**
   - Implement IP whitelisting for database access
   - Enable VPC peering for Cloud SQL (no internet exposure)
   - Set up intrusion detection alerts

### If Service Account Compromised

```bash
# Disable compromised service account
gcloud iam service-accounts disable COMPROMISED_ACCOUNT_EMAIL \
  --project=thenesports-api-prod

# Create new service account
gcloud iam service-accounts create nesf-core-api-v2 \
  --project=thenesports-api-prod

# Grant permissions (same as old account)
gcloud projects add-iam-policy-binding thenesports-api-prod \
  --member=serviceAccount:nesf-core-api-v2@thenesports-api-prod.iam.gserviceaccount.com \
  --role=roles/cloudsql.client
```

---

## Compliance & Privacy

### Data Retention

- **Active records:** Kept indefinitely (soft-delete only)
- **Deleted records:** Kept 90 days, then hard-deleted
- **Session logs:** Kept 30 days
- **Audit logs:** Kept 2 years

### Privacy Policy Requirements

- ✅ Collect only necessary data (name, email, location)
- ✅ Encrypt data in transit (HTTPS only)
- ✅ Encrypt data at rest (Cloud SQL + GCS)
- ✅ Delete on request (GDPR right to be forgotten)
- ✅ Never share with third parties without consent

See `docs/PRIVACY.md` for full policy.

---

## Best Practices

### For Developers

1. **Never commit secrets** - Always use .gitignore + environment variables
2. **Rotate tokens regularly** - Don't store tokens in version control
3. **Use HTTPS only** - Never log in over HTTP
4. **Enable 2FA** - On all admin accounts
5. **Review code changes** - Before merging to main

### For Operations

1. **Least privilege** - Grant minimum permissions needed
2. **Regular backups** - Test restore procedures
3. **Monitor logs** - Set up alerts for errors & unauthorized access
4. **Update dependencies** - Run `npm audit` regularly
5. **Security headers** - Enforce HSTS, CSP, X-Frame-Options

### For QA

1. **Test access control** - Verify users can't access others' data
2. **Test rate limiting** - Verify brute-force protection works
3. **Test input validation** - Verify SQL injection protection
4. **Test error messages** - Verify they don't leak sensitive data

---

## Resources

- [OWASP Top 10 Security Risks](https://owasp.org/www-project-top-ten/)
- [Google Cloud Security Best Practices](https://cloud.google.com/security/best-practices)
- [Node.js Security Checklist](https://nodejs.org/en/docs/guides/security/)
- [Flutter Security Best Practices](https://flutter.dev/docs/development/data-and-backend/google-apis)
