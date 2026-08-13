# NESF Core Production: Quick Start

**Status:** Cloud Build running (attempt #2 with fixed Dockerfile)

---

## 📋 What's Deployed

| Component | Status | URL/Location |
|-----------|--------|---|
| **APK** | ✅ Ready | `NESF-Core-production.apk` (19.7 MB) |
| **API** | 🔄 Building | Cloud Run (asia-south1) |
| **Database** | ✅ Created | Cloud SQL `nesf_core` |
| **Storage** | ✅ Created | Cloud Storage `gs://nesf-core-uploads` |
| **Secrets** | ✅ Created | Secret Manager (JWT + DB password) |
| **Domain DNS** | ⏳ Pending | `app.nesportsfoundation.in` |

---

## 🚀 After Build Completes

### 1️⃣ Verify Domain (1 minute)
```bash
gcloud domains verify app.nesportsfoundation.in
# Opens Google Search Console - just verify ownership
```

### 2️⃣ Create Domain Mapping (1 minute)
```bash
gcloud beta run domain-mappings create \
  --service=nesf-core-api \
  --domain=app.nesportsfoundation.in \
  --region=asia-south1 \
  --project=thenesports-api-prod
```

**Save the CNAME record output** - you'll need it for Cloudflare.

### 3️⃣ Update Cloudflare DNS (2 minutes)
1. Go to Cloudflare dashboard
2. DNS for `nesportsfoundation.in`
3. Add/edit `app` record:
   - Type: CNAME
   - Content: `ghs.googlehosted.com` (from step 2 output)
   - Proxy: **DNS only** (grey cloud ⚠️)
4. Save

### 4️⃣ Wait for Certificate (~10 minutes)
```bash
# Check status every minute
gcloud beta run domain-mappings describe \
  --domain=app.nesportsfoundation.in \
  --region=asia-south1 \
  --project=thenesports-api-prod
```

### 5️⃣ Verify Endpoint
```bash
curl -sS https://app.nesportsfoundation.in/health
# Should return: {"ok":true,"service":"nesf-core-api","db":"up"}
```

### 6️⃣ Migrate Database (5 minutes)
```bash
# Terminal 1: Start Cloud SQL proxy
cloud-sql-proxy thenesports-api-prod:asia-south1:thenesports-db --port 5433 &

# Terminal 2: Run migrations
cd D:\new app\nesf-core\api
DATABASE_URL='postgres://nesf_core:NEsf%40Core2026%23Prod%21Secure@localhost:5433/nesf_core' \
  npm run migrate

# Seed admin account
DATABASE_URL='postgres://nesf_core:NEsf%40Core2026%23Prod%21Secure@localhost:5433/nesf_core' \
  SEED_ADMIN_EMAIL='biki@nesportsfoundation.in' \
  SEED_ADMIN_PASSWORD='ChangeMe@123' \
  npm run seed
```

### 7️⃣ Test Login
- Open: `https://app.nesportsfoundation.in`
- Email: `biki@nesportsfoundation.in`
- Password: `ChangeMe@123`
- **IMMEDIATELY change the password**

### 8️⃣ Distribute APK
```bash
# To a connected device
adb install -r "D:\new app\nesf-core\NESF-Core-production.apk"

# Or upload to server for QR distribution
```

---

## 🔐 Important Credentials

**Database:**
```
Host: Cloud SQL (unix socket in prod)
User: nesf_core
Password: NEsf@Core2026#Prod!Secure
Database: nesf_core
```

**Admin Account (after seed):**
```
Email: biki@nesportsfoundation.in
Password: ChangeMe@123 ← MUST CHANGE IMMEDIATELY
```

---

## 📊 Estimated Timeline

- Cloud Build: 10-15 min (running now)
- Domain verify + DNS: 10 min
- Certificate issuance: 10 min
- Database migration: 5 min
- Testing: 5 min

**Total: ~45 minutes to production**

---

## ⚠️ Critical Notes

1. **Cloudflare Proxy Status** = "DNS only" (grey cloud)
   - Orange cloud breaks SSL certificate
   - Can enable proxying AFTER cert is issued

2. **Admin Password** - Change immediately after first login
   - Temporary password: `ChangeMe@123`
   - This password is in your git history and logs

3. **Database is Fresh**
   - No data migrated from old systems
   - You'll import staff manually or via import script

4. **APK is Production-Ready**
   - Uses correct endpoint: `https://app.nesportsfoundation.in`
   - Will work anywhere (not just on WiFi)
   - Can distribute immediately

---

## 🆘 Quick Troubleshooting

**Build failed?**
- Check: `gcloud builds list --project=thenesports-api-prod`
- View logs: Cloud Console → Cloud Build

**Domain won't verify?**
- Check: Google Search Console for `app.nesportsfoundation.in`
- May take 1-2 hours to show as verified

**Certificate stuck "pending"?**
- Ensure Cloudflare is set to "DNS only" (grey cloud)
- Orange cloud breaks verification
- Wait 30 minutes max

**Can't connect to database?**
- Verify password: `NEsf%40Core2026%23Prod%21Secure` (URL-encoded)
- Ensure cloud-sql-proxy is running
- Check: `gcloud sql instances describe thenesports-db`

**Login not working?**
- Verify seed ran successfully
- Check database:
  ```sql
  SELECT email, role FROM employees WHERE role='admin';
  ```

---

## 📞 Resources

- **Deployment Details:** `DEPLOYMENT_STATUS.md`
- **Full Guide:** `PRODUCTION_DEPLOYMENT_GUIDE.md`
- **GCP Console:** https://console.cloud.google.com
- **Cloudflare DNS:** https://dash.cloudflare.com

---

**Next:** Wait for build to complete, then follow steps 1️⃣-8️⃣ above.

Build status: `gcloud builds log --limit=100 --project=thenesports-api-prod`
