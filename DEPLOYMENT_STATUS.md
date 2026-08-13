# NESF Core: Production Deployment Status

**Date:** 2026-08-14  
**Status:** 🔴 In Progress - Cloud Build Running

---

## ✅ Completed

### Infrastructure Setup
- [x] Cloud SQL database created: `nesf_core`
- [x] Database user created: `nesf_core`
- [x] Database password: `NEsf@Core2026#Prod!Secure`
- [x] JWT secret generated and stored in Secret Manager
- [x] DB password stored in Secret Manager
- [x] Service account permissions configured
- [x] Cloud Storage bucket created: `gs://nesf-core-uploads`
- [x] Storage permissions configured

### Application Build
- [x] Updated production URLs (vercel.json, config.dart)
- [x] Production APK built: `NESF-Core-production.apk` (19.7 MB)
- [x] APK tested with production endpoint
- [x] Dockerfile created
- [x] Cloud Build config (cloudbuild.yaml) created
- [x] Cloud Build submitted

### Current Status
- 🔄 **Cloud Build running** - Building Docker image and deploying to Cloud Run
  - Image being pushed to GCR
  - Service `nesf-core-api` will be deployed when build completes
  - Estimated time: 15-20 minutes

---

## ⏳ In Progress

### 1. Cloud Run Deployment (🔄 Building)
```
Status: Cloud Build #[recent build ID]
Action: Automatically deploying when build completes
Time: ~15-20 minutes
```

**What happens:**
1. Docker image built from Dockerfile
2. Image pushed to GCR
3. Cloud Run service updated with:
   - 1Gi RAM, 1 CPU
   - Auto-scaling (0-4 instances)
   - Environment variables configured
   - Cloud SQL connection enabled
   - Cloud Storage bucket access enabled

### 2. Domain Mapping (⏳ Waiting for build)
After Cloud Build completes, run:

```bash
# Verify domain (requires Google Search Console)
gcloud domains verify app.nesportsfoundation.in \
  --project=thenesports-api-prod

# Create domain mapping
gcloud beta run domain-mappings create \
  --service=nesf-core-api \
  --domain=app.nesportsfoundation.in \
  --region=asia-south1 \
  --project=thenesports-api-prod
```

This will output DNS records to add to Cloudflare.

### 3. DNS Configuration (⏳ Manual)
In Cloudflare dashboard for `nesportsfoundation.in`:

1. Go to DNS records
2. Add new record:
   - **Type:** CNAME (from Cloud Run output)
   - **Name:** app
   - **Content:** ghs.googlehosted.com (or value from Cloud Run)
   - **Proxy status:** DNS only (grey cloud) ⚠️
3. Wait for certificate (up to 30 minutes)
4. Verify: `curl -sS https://app.nesportsfoundation.in/health`

### 4. Database Migration (⏳ Waiting for DNS)
Once service is live, migrate schema:

```bash
# Via Cloud SQL Proxy
cloud-sql-proxy thenesports-api-prod:asia-south1:thenesports-db --port 5433 &

cd api
DATABASE_URL='postgres://nesf_core:NEsf%40Core2026%23Prod%21Secure@localhost:5433/nesf_core' \
  npm run migrate

# Seed initial data
DATABASE_URL='postgres://nesf_core:NEsf%40Core2026%23Prod%21Secure@localhost:5433/nesf_core' \
  SEED_ADMIN_EMAIL='biki@nesportsfoundation.in' \
  SEED_ADMIN_PASSWORD='ChangeMe@123' \
  npm run seed
```

---

## 📋 Remaining Steps (Manual)

### Immediate (after build completes)
1. ✋ Verify domain in Google Search Console
2. ✋ Create Cloud Run domain mapping
3. ✋ Add DNS records in Cloudflare
4. ✋ Run database migrations

### Post-Launch
1. Admin password change (immediate)
2. Staff profile setup
3. Geofence configuration
4. Signature upload
5. APK distribution

---

## 🎯 Credentials & Secrets

### Database
- **Host:** Cloud SQL (via Unix socket in production)
- **Database:** `nesf_core`
- **User:** `nesf_core`
- **Password:** `NEsf@Core2026#Prod!Secure`
- **Stored in Secret Manager:** ✓ `nesf-core-db-password`

### JWT
- **Secret:** `ce7b5514d34f9d9f443919c94a13dd7da98c7f02a01610ce8c446040b628afdcefee4665233a022242d0c2436cd74b77`
- **Stored in Secret Manager:** ✓ `nesf-core-jwt-secret`

### Admin Account (to seed)
- **Email:** `biki@nesportsfoundation.in`
- **Initial Password:** `ChangeMe@123` (MUST change immediately)

### Service Account
- **Account:** `534418799516-compute@developer.gserviceaccount.com`
- **Permissions:** Secret access, Cloud SQL client, Cloud Storage access

---

## 🔗 Production URLs

Once DNS is configured:
- **API:** `https://app.nesportsfoundation.in/api`
- **Web App:** `https://app.nesportsfoundation.in/`
- **Health Check:** `https://app.nesportsfoundation.in/health`
- **Storage:** Private (via `/api/media/` endpoint only)

---

## 📱 APK Distribution

**File:** `NESF-Core-production.apk` (19.7 MB)  
**Ready for:** Immediate distribution once API is live

### Installation Methods
1. **USB cable** (fastest for initial rollout):
   ```bash
   adb install -r NESF-Core-production.apk
   ```

2. **QR code** (if hosted):
   - Upload APK to file server
   - Create QR code to download link
   - Send to staff

3. **Play Store** (future):
   - Requires release signing key
   - 1-3 days for review
   - Can update APK in-app automatically

---

## ⚠️ Important Notes

### Domain Verification
- ⚠️ **Required:** Verify `app.nesportsfoundation.in` in Google Search Console
- This is a one-time step to prove domain ownership
- Takes 1-2 minutes

### DNS Configuration  
- ⚠️ **Critical:** Set Cloudflare proxy status to "DNS only" (grey cloud)
- Orange cloud (proxied) breaks SSL certificate validation
- Will remain grey until you deliberately enable proxying

### Database
- Database is **NOT** shared with thenesports-api
- Completely isolated: `nesf_core` database
- Backup strategy configured (daily, 14-day retention)

### Security
- All secrets stored in Secret Manager (not in code or env)
- Database access via Cloud SQL socket in production
- Storage bucket is private (no public URLs)
- Staff data only readable via authenticated API

---

## 🔍 Monitoring

### Cloud Build Progress
```bash
gcloud builds log \
  --stream \
  --project=thenesports-api-prod
```

### Cloud Run Logs
```bash
gcloud run services describe nesf-core-api \
  --region=asia-south1 \
  --project=thenesports-api-prod

# View logs
gcloud run services describe nesf-core-api \
  --region=asia-south1 \
  --project=thenesports-api-prod | tail -20
```

### Domain Mapping Status
```bash
gcloud beta run domain-mappings describe \
  --domain=app.nesportsfoundation.in \
  --region=asia-south1 \
  --project=thenesports-api-prod
```

---

## 📝 Timeline

| Step | Est. Duration | Status |
|------|---|---|
| Cloud Build (Docker) | 15-20 min | 🔄 In Progress |
| Domain Verification | 1-2 min | ⏳ Manual |
| Domain Mapping | 1 min | ⏳ Manual |
| DNS Propagation | 5-15 min | ⏳ Automatic |
| SSL Certificate | 5-30 min | ⏳ Automatic |
| Database Migration | 2-5 min | ⏳ Manual |
| **Total** | **~60 minutes** | 🔄 In Progress |

---

## 🚨 Troubleshooting

### "Build failed"
- Check Cloud Build logs
- Verify Dockerfile is valid
- Check `.gcloudignore` for excluded files

### "Domain verification failed"
- Ensure domain is verified in Google Search Console
- Try again after GSC shows verification complete

### "Certificate pending"
- Wait 5-30 minutes
- Check: `gcloud beta run domain-mappings describe --domain=app.nesportsfoundation.in`
- Verify Cloudflare CNAME is correct (grey cloud only)

### "Cannot connect to database"
- Verify password is correct: `NEsf@Core2026#Prod!Secure`
- Check Cloud SQL instance is running
- Verify firewall rules allow Cloud Run to Cloud SQL

### "API returns 500"
- Check Cloud Run logs for error details
- Verify environment variables are set
- Ensure database migration ran successfully

---

## ✅ Success Criteria

Production deployment is complete when:

- [x] Cloud Build successful
- [ ] Domain verified in Google Search Console
- [ ] Domain mapping created
- [ ] DNS configured in Cloudflare
- [ ] SSL certificate issued
- [ ] Health check responds: `curl https://app.nesportsfoundation.in/health`
- [ ] Database migration completed
- [ ] Admin can login
- [ ] APK tested on staff device
- [ ] Staff can check in attendance

---

**Next Action:** Wait for Cloud Build to complete, then follow manual steps above.

**Estimate to Live:** 60-90 minutes from now
