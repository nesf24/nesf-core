# NESF Core: Supabase Quick Start

Your Supabase project is ready! Follow these 5 steps to complete the setup.

**Credentials:**
- Project: https://mixbtfnjdzmfbctkxnwk.supabase.co
- Email: (logged in Chrome)
- Password: NEsports@#2026

---

## ⏱️ Time Required: 15 minutes

---

## Step 1: Run Database Schema Migration (2 min)

### Option A: Via Supabase SQL Editor (Recommended - No Tools Needed)

1. **Open Supabase Dashboard**
   - In Chrome (already logged in): https://app.supabase.com
   - Select your project `nesf-core`

2. **Go to SQL Editor**
   - Left sidebar → "SQL Editor"
   - Click "+ New Query"

3. **Paste and Execute Schema**
   - Read the file: `D:\new app\nesf-core\api\schema.sql`
   - Copy ALL contents
   - Paste into the SQL Editor query window
   - Click "Run" button (or Ctrl+Enter)
   - Wait for success message ✅

### Option B: Via Command Line (psql)

```bash
cd D:\new app\nesf-core
psql -h mixbtfnjdzmfbctkxnwk.supabase.co -U postgres -d postgres < api/schema.sql
# Password: NEsports@#2026
```

---

## Step 2: Verify Schema (1 min)

In Supabase SQL Editor, run:

```sql
SELECT table_name FROM information_schema.tables 
WHERE table_schema = 'public' 
ORDER BY table_name;
```

You should see:
- `employees`
- `leave_requests`
- `leave_balances`
- `ta_da_requests`
- `leave_types`
- `ta_da_rates`
- `holidays`
- `activity_photos`
- `documents`
- `document_approvals`

---

## Step 3: Seed Initial Data (3 min)

Copy `.env.supabase` to `.env`:

```bash
cd D:\new app\nesf-core\api

# Copy the environment file
copy .env.supabase .env

# Install dependencies (if needed)
npm install

# Run seeder
npm run seed
```

Expected output:
```
✓ Admin account created: biki@nesportsfoundation.in
✓ Leave types created: 4
✓ TA/DA rates created: 2
✓ Holidays created: 12
✓ Database seeding complete!
```

---

## Step 4: Deploy API to Vercel (5 min)

### Step 4A: Set up Vercel Project

```bash
cd D:\new app\nesf-core\api

# Login to Vercel (if not already)
vercel login

# Deploy to Vercel
vercel deploy --prod
```

During deployment, Vercel will ask:
- **Project Name:** `nesf-core-api` (or similar)
- **Environment:** Select "Production"

Vercel will return a URL like: `https://nesf-core-api-xxxxx.vercel.app`

### Step 4B: Set Environment Variables in Vercel

1. Go to Vercel Dashboard: https://vercel.com/dashboard
2. Click on your `nesf-core-api` project
3. Settings → Environment Variables
4. Add these variables:

| Variable | Value |
|----------|-------|
| `DATABASE_URL` | `postgres://postgres:NEsports%40%232026@mixbtfnjdzmfbctkxnwk.supabase.co:6543/postgres?sslmode=require` |
| `JWT_SECRET` | Generate new: `node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"` |
| `NODE_ENV` | `production` |
| `CORS_ORIGINS` | `https://app.nesportsfoundation.in,https://nesf-core-web.vercel.app` |

5. Click "Redeploy" to apply variables

---

## Step 5: Update Flutter Web App (3 min)

1. **Go to Vercel Web App Settings**
   - Dashboard → `nesf-core` project (the web app)
   - Settings → Environment Variables

2. **Update API_BASE**
   - Find variable: `API_BASE`
   - Change value to your deployed API URL (from Step 4)
   - Example: `https://nesf-core-api-xxxxx.vercel.app`

3. **Redeploy**
   - Deployments → Redeploy latest version
   - Wait for build to complete

---

## ✅ Testing Your Setup

### Test 1: API Health Check
```bash
# Replace with your Vercel API URL
curl https://nesf-core-api-xxxxx.vercel.app/health
```

Expected response:
```json
{ "status": "ok", "timestamp": "2026-08-12T..." }
```

### Test 2: Database Connection
```bash
# From api directory
npm run test
```

### Test 3: Full Login Flow

1. **Open the Web App**
   - Go to: https://nesf-core.vercel.app

2. **Login with Credentials**
   - Email: `biki@nesportsfoundation.in`
   - Password: `ChangeMe@123`

3. **Expected**: Dashboard loads with:
   - Attendance widget
   - Leave balance
   - TA/DA form
   - Reports section

---

## 📱 Android APK Configuration

Update the APK with the deployed API URL:

**File:** `D:\new app\nesf-core\app\lib\config.dart`

```dart
const String apiBaseUrl = 'https://nesf-core-api-xxxxx.vercel.app';
```

Then rebuild:
```bash
cd D:\new app\nesf-core\app
flutter build apk
```

---

## 🆘 Troubleshooting

### "connection refused" or "no such host"
- ✅ Check DATABASE_URL in .env
- ✅ Verify Supabase project is active (not paused)
- ✅ Try adding `?sslmode=require` to connection string

### "schema migration failed"
- ✅ Go to SQL Editor in Supabase
- ✅ Check for error messages in output
- ✅ Verify you're pasting the ENTIRE schema.sql file

### "API returns 500"
- ✅ Check Vercel Logs: Dashboard → Logs
- ✅ Verify all environment variables are set
- ✅ Try redeploying: `vercel deploy --prod`

### "Can't login to Flutter app"
- ✅ Check API_BASE URL in Vercel environment
- ✅ Verify CORS_ORIGINS includes your domain
- ✅ Check browser console for errors (F12)

---

## 🎯 What's Running Now

```
┌─────────────────────────────────┐
│ Flutter Web (Vercel Static)     │
│ → https://nesf-core.vercel.app  │
└───────────────┬─────────────────┘
                ↓ (API calls)
┌─────────────────────────────────┐
│ Node.js API (Vercel Serverless) │
│ → https://nesf-core-api-xxx      │
└───────────────┬─────────────────┘
                ↓ (SQL queries)
┌─────────────────────────────────┐
│ PostgreSQL (Supabase)           │
│ → mixbtfnjdzmfbctkxnwk.supabase │
└─────────────────────────────────┘
```

---

## 📊 Import NESF Staff (Optional)

To add your 14 NESF staff members automatically:

```bash
cd D:\new app\nesf-core\api

# Make sure .env is set up
DATABASE_URL=... node ../scripts/import-staff-nesf.js
```

This creates accounts for:
- Tashi Dorjee Thongon (Authority)
- Bindiya Ligu (Staff - Psychologist)
- Tanyang Mobin (Manager - Communications)
- ... and 11 others

**Temporary Password:** `Nesf@2026` (staff must change on first login)

---

## 🚀 You're Done!

All components are now deployed:
- ✅ Database: Supabase PostgreSQL
- ✅ API: Vercel Serverless
- ✅ Web: Vercel Static
- ✅ Mobile: Ready for APK build

Next: Test login and start using NESF Core!

---

## 💬 Support

- **Supabase Docs:** https://supabase.com/docs
- **Vercel Docs:** https://vercel.com/docs
- **Flutter Docs:** https://flutter.dev/docs

---

**Last Updated:** 2026-08-12
**Status:** Ready for Production ✅
