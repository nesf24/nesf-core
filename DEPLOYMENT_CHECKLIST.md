# NESF Core: Supabase + Vercel Deployment Checklist

**Status:** Ready for Deployment ✅
**Date:** 2026-08-12
**Components:** Database (Supabase), API (Vercel), Web (Vercel), Mobile (APK)

---

## 📋 Pre-Deployment Verification

- [x] Supabase project created: `mixbtfnjdzmfbctkxnwk`
- [x] Database password set: `NEsports@#2026`
- [x] Schema file ready: `api/schema.sql` (complete with all tables)
- [x] Seed script ready: `api/scripts/seed.js` (admin, leave types, TA/DA rates, holidays)
- [x] Environment template ready: `api/.env.supabase`
- [x] Quick-start guide ready: `SUPABASE_QUICK_START.md`

---

## 🚀 Step-by-Step Deployment (20 minutes)

### Step 1: Configure Local Environment (2 min)

```bash
cd D:\new app\nesf-core\api

# Copy Supabase config to .env
copy .env.supabase .env

# Verify DATABASE_URL is set
type .env | grep DATABASE_URL
```

Expected output:
```
DATABASE_URL=postgres://postgres:NEsports%40%232026@mixbtfnjdzmfbctkxnwk.supabase.co:5432/postgres?sslmode=require
```

### Step 2: Run Database Migration (2 min)

**Via Supabase SQL Editor (Recommended):**

1. Open browser (already logged in): https://app.supabase.com
2. Select project `nesf-core`
3. Click **SQL Editor** → **New Query**
4. Open file: `api/schema.sql`
5. Copy ALL content
6. Paste into SQL Editor
7. Click **Run** or press Ctrl+Enter
8. Wait for success ✅

**Via Command Line (Alternative):**

```bash
psql -h mixbtfnjdzmfbctkxnwk.supabase.co -U postgres -d postgres < D:\new-app\nesf-core\api\schema.sql
# When prompted: NEsports@#2026
```

### Step 3: Verify Schema (1 min)

In Supabase SQL Editor, run:

```sql
SELECT COUNT(*) as table_count FROM information_schema.tables 
WHERE table_schema = 'public' AND table_type = 'BASE TABLE';
```

Expected result: `table_count = 11`

### Step 4: Seed Initial Data (3 min)

```bash
cd D:\new app\nesf-core\api

# Install dependencies
npm install

# Run seed script
npm run seed
```

Expected output:
```
🌱 Seeding NESF Core database...
👤 Creating admin account...
✓ Admin: biki@nesportsfoundation.in / ChangeMe@123
📋 Creating leave types...
✓ 8 leave types created
💰 Creating TA/DA rates...
✓ 15 TA/DA rate schedules created
🎉 Creating holiday calendar...
✓ 8 holidays added
✨ Database seeding complete!
```

### Step 5: Test Database Connection (2 min)

```bash
cd D:\new app\nesf-core\api

# Run quick test
npm run test:e2e
```

Expected: All tests should pass ✅

### Step 6: Deploy API to Vercel (5 min)

```bash
cd D:\new app\nesf-core\api

# Login to Vercel
vercel login

# Deploy to production
vercel deploy --prod
```

**Record the API URL from Vercel output:**
```
✓ Production: https://nesf-core-api-XXXXX.vercel.app
```

### Step 7: Configure Vercel Environment Variables (3 min)

1. Go to: https://vercel.com/dashboard
2. Click on `nesf-core-api` project
3. Settings → Environment Variables
4. Add variables:

| Variable | Value |
|----------|-------|
| `DATABASE_URL` | `postgres://postgres:NEsports%40%232026@mixbtfnjdzmfbctkxnwk.supabase.co:6543/postgres?sslmode=require` |
| `JWT_SECRET` | Run: `node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"` |
| `NODE_ENV` | `production` |
| `CORS_ORIGINS` | `https://app.nesportsfoundation.in,https://nesf-core-web.vercel.app` |

5. Click **Save**
6. Click **Redeploy** to apply variables

### Step 8: Update Flutter Web App (2 min)

1. Go to: https://vercel.com/dashboard
2. Click on `nesf-core` project (web app)
3. Settings → Environment Variables
4. Update `API_BASE`:
   - Old: `https://app.nesportsfoundation.in`
   - New: `https://nesf-core-api-XXXXX.vercel.app` (from Step 6)
5. Click **Save**
6. **Deployments** → Redeploy latest build
7. Wait for build to complete (~2 min)

---

## ✅ Verification Checklist

### Database
- [ ] Schema migration completed in Supabase
- [ ] 11 tables created (verified via SQL query)
- [ ] Admin account created: `biki@nesportsfoundation.in`
- [ ] Leave types seeded: 8 types
- [ ] TA/DA rates seeded: 15 rates
- [ ] Holidays seeded: 8 holidays

### API Deployment
- [ ] API deployed to Vercel
- [ ] Environment variables set in Vercel
- [ ] API URL: `https://nesf-core-api-XXXXX.vercel.app`
- [ ] Health check passes: `curl https://nesf-core-api-XXXXX.vercel.app/health`

### Web App
- [ ] Flutter web app redeployed
- [ ] API_BASE updated to point to deployed API
- [ ] Web app URL: `https://nesf-core.vercel.app`

### Testing
- [ ] Login works: `biki@nesportsfoundation.in` / `ChangeMe@123`
- [ ] Dashboard loads
- [ ] Attendance widget visible
- [ ] Leave balance displays
- [ ] TA/DA form accessible

---

## 🎯 Testing Workflow

### Test 1: API Health Check

```bash
# Using curl
curl https://nesf-core-api-XXXXX.vercel.app/health

# Expected response:
# {"status":"ok","timestamp":"2026-08-12T..."}
```

### Test 2: Database Connection

```bash
# From API directory
npm run test:e2e

# Expected: All tests pass ✅
```

### Test 3: Login Flow (Web)

1. Open: https://nesf-core.vercel.app
2. Login:
   - Email: `biki@nesportsfoundation.in`
   - Password: `ChangeMe@123`
3. Verify dashboard loads with:
   - Attendance widget
   - Leave balance widget
   - TA/DA form
   - Reports section

### Test 4: Staff Import (Optional)

```bash
cd D:\new app\nesf-core\api

# Import 14 NESF staff members
DATABASE_URL=... node ../scripts/import-staff-nesf.js

# Temporary password: Nesf@2026
# Staff must change on first login
```

---

## 📱 Android APK (Optional)

To deploy the mobile app, update and rebuild:

```bash
# Update API base URL in Flutter
# File: app/lib/config.dart
const String apiBaseUrl = 'https://nesf-core-api-XXXXX.vercel.app';

# Rebuild APK
cd app
flutter build apk
```

APK location: `build/app/outputs/flutter-apk/app-release.apk`

---

## 🆘 Troubleshooting

### "Connection refused" / "No such host"

**Issue:** Database connection failed

**Fix:**
1. Verify DATABASE_URL in `.env`: `postgres://postgres:NEsports%40%232026@mixbtfnjdzmfbctkxnwk.supabase.co:5432/postgres?sslmode=require`
2. Check Supabase project is active (not paused)
3. For Vercel deployment, use port 6543 instead of 5432 for pooling

**Try:**
```bash
psql -h mixbtfnjdzmfbctkxnwk.supabase.co -U postgres -d postgres
# Password: NEsports@#2026
```

### "Schema migration failed" / "Table already exists"

**Issue:** Schema already exists or migration syntax error

**Fix:**
1. Go to Supabase SQL Editor
2. Check error message at bottom
3. If tables exist, you can either:
   - Drop them (caution: data loss): `DROP TABLE IF EXISTS employees CASCADE;`
   - Re-run seed on existing schema: `npm run seed`

### "API returns 500" / "Internal Server Error"

**Issue:** Vercel API is failing

**Fix:**
1. Check Vercel logs:
   - Dashboard → Logs
   - Search for error messages
2. Verify environment variables:
   - DATABASE_URL must be set
   - JWT_SECRET must be set
3. Try redeploying:
   ```bash
   cd api
   vercel deploy --prod
   ```

### "Can't connect to API from Flutter"

**Issue:** CORS error or wrong API URL

**Fix:**
1. Check browser console (F12) for CORS error
2. Verify API_BASE in Vercel web app environment:
   - Should be: `https://nesf-core-api-XXXXX.vercel.app`
3. Verify CORS_ORIGINS in Vercel API environment:
   - Should include: `https://nesf-core.vercel.app`
4. Redeploy both (API and web app)

### "Login fails" / "Invalid credentials"

**Issue:** User doesn't exist or password is wrong

**Fix:**
1. Verify seed completed: `npm run seed`
2. Check user exists in database:
   ```sql
   SELECT email, role FROM employees WHERE email = 'biki@nesportsfoundation.in';
   ```
3. If not found, re-run seed:
   ```bash
   npm run seed
   ```

---

## 📞 Support Resources

- **Supabase Docs:** https://supabase.com/docs
- **Vercel Docs:** https://vercel.com/docs
- **Flutter Docs:** https://flutter.dev/docs
- **PostgreSQL Docs:** https://www.postgresql.org/docs

---

## 📊 Architecture Summary

```
┌──────────────────────────────────┐
│   Flutter Web Browser            │
│   https://nesf-core.vercel.app   │
└──────────────────┬───────────────┘
                   │ HTTP requests
                   ↓
┌──────────────────────────────────┐
│   Node.js API (Vercel Serverless)│
│   https://nesf-core-api-XXXXX     │
│   - Authentication               │
│   - Business Logic               │
│   - Document Generation          │
└──────────────────┬───────────────┘
                   │ SQL queries
                   ↓
┌──────────────────────────────────┐
│   PostgreSQL (Supabase)          │
│   mixbtfnjdzmfbctkxnwk.supabase  │
│   - Employees & Auth             │
│   - Leave Requests               │
│   - TA/DA Requests               │
│   - Documents & Approvals        │
└──────────────────────────────────┘
```

---

## 🎉 Success Criteria

After completing all steps, you should have:

✅ Database: PostgreSQL on Supabase with complete schema
✅ API: Node.js deployed to Vercel with all endpoints working
✅ Web: Flutter web app deployed to Vercel pointing to API
✅ Mobile: Android APK built and ready for distribution
✅ Users: Admin account created, staff can login
✅ Data: Leave types, TA/DA rates, holidays configured
✅ SSL: HTTPS for all endpoints

---

## 🚀 Production Ready Checklist

- [ ] Database backed up (Supabase: Settings → Database)
- [ ] API monitoring enabled (Vercel: Analytics)
- [ ] SSL certificates verified (automatic with Vercel)
- [ ] Firewall rules configured (Supabase: Network)
- [ ] Email notifications set up (for alerts)
- [ ] Staff trained on login and password change
- [ ] Support contacts documented
- [ ] 24/7 monitoring in place

---

**Deployment Date:** 2026-08-12
**Deployed By:** [Your Name]
**Status:** ✅ Ready for Production
