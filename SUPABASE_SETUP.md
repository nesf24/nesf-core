# NESF Core: Supabase Setup Guide

## 🚀 Quick Start

Supabase gives you:
- ✅ PostgreSQL database (exactly what NESF Core uses)
- ✅ Auto-generated REST API
- ✅ Authentication
- ✅ Real-time subscriptions
- ✅ Free tier (5 projects)

---

## 📋 Step 1: Create Supabase Project

1. Go to https://supabase.com
2. Click **"Start your project"**
3. Sign up with email or GitHub
4. Create a new project:
   - **Project name:** `nesf-core`
   - **Database password:** Use a strong password
   - **Region:** Asia (Singapore recommended for India)
   - **Pricing:** Free tier is fine for testing

5. Wait for project to initialize (2-3 minutes)

---

## 🔑 Step 2: Get Your Credentials

Once your project is ready:

1. Go to **Settings** → **Database**
2. Copy these credentials:
   - **Host:** `xxx.supabase.co`
   - **Port:** `5432`
   - **Database:** `postgres`
   - **User:** `postgres`
   - **Password:** The one you set

3. Go to **Settings** → **API**
4. Copy these:
   - **Project URL:** `https://xxx.supabase.co`
   - **Anon Key:** (public key)
   - **Service Role Key:** (secret key - keep safe!)

---

## 📦 Step 3: Migrate Database Schema

### Option A: Using psql (Recommended)

```bash
# Download psql if needed (comes with PostgreSQL)
# Then connect to Supabase and run schema

psql -h xxx.supabase.co -U postgres -d postgres << EOF
# Password: (your database password)

-- Run NESF Core schema
\i api/schema.sql

EOF
```

### Option B: Using pgAdmin (GUI)

1. Go to Supabase Dashboard → **SQL Editor**
2. Click **New Query**
3. Paste contents of `api/schema.sql`
4. Click **Run**

### Option C: Using Supabase Studio (Easiest)

1. In Supabase dashboard, go to **SQL Editor**
2. Create new query
3. Copy-paste the entire `api/schema.sql` file
4. Execute

---

## ⚙️ Step 4: Configure API for Supabase

Update `api/.env`:

```bash
# Database connection (Supabase PostgreSQL)
DATABASE_URL=postgres://postgres:[PASSWORD]@[HOST]:5432/postgres

# Or use connection pooling (recommended for serverless):
DATABASE_URL=postgres://postgres:[PASSWORD]@[HOST]:6543/postgres?sslmode=require

# Keep other settings
JWT_SECRET=[generate new one]
NODE_ENV=production
STORAGE_DRIVER=local  # Or switch to supabase storage later
CORS_ORIGINS=https://nesf-core-4rqwq0t6e-nesports.vercel.app
```

**Replace:**
- `[PASSWORD]` = Your database password
- `[HOST]` = Your Supabase host (e.g., `abcdefg.supabase.co`)

---

## 📤 Step 5: Seed Initial Data

```bash
cd api
npm install
npm run seed
```

This creates:
- Admin account (biki@nesportsfoundation.in / ChangeMe@123)
- Leave types
- TA/DA rates
- Holidays

---

## 🚀 Step 6: Deploy API to Vercel

You can now deploy the Node.js API to Vercel as a serverless function:

### Option A: Deploy with Vercel CLI

```bash
cd api
vercel deploy --prod
```

### Option B: Deploy via Git

1. Push your changes to GitHub:
```bash
git add .env.supabase
git commit -m "Configure Supabase backend"
git push origin master
```

2. In Vercel dashboard:
   - Click **Add New** → **Project**
   - Import GitHub repo `nesf24/nesf-core`
   - Set environment variables:
     - `DATABASE_URL` = Your Supabase connection string
     - `JWT_SECRET` = Your secret
   - Deploy!

---

## 🔗 Step 7: Update Flutter App

The Vercel-deployed API will be at: `https://[api-project-name].vercel.app`

Update Vercel app environment to point to it:

**In Vercel dashboard:**
1. Go to your NESF Core project
2. Settings → Environment Variables
3. Add:
   - `API_BASE`: `https://[api-project-name].vercel.app`
4. Redeploy

---

## ✅ Testing the Full Stack

Once everything is deployed:

1. **Database:** Supabase PostgreSQL (with your data)
2. **API:** Vercel serverless (Node.js)
3. **Web App:** Vercel static (Flutter web)
4. **Mobile:** APK (points to API)

### Test Login:
- Email: `biki@nesportsfoundation.in`
- Password: `ChangeMe@123`

---

## 📊 Architecture Diagram

```
┌─────────────────────────────────────────┐
│  Flutter Web App (Vercel Static)        │
│  https://nesf-core-...-nesports.app     │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│  Node.js API (Vercel Serverless)        │
│  https://nesf-core-api.vercel.app       │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│  PostgreSQL Database (Supabase)         │
│  postgres://user@xxx.supabase.co        │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│  Android APK (Mobile)                   │
│  → API_BASE: https://nesf-core-api...   │
└─────────────────────────────────────────┘
```

---

## 🆘 Troubleshooting

### Connection refused
- Check `DATABASE_URL` in `.env`
- Verify Supabase project is active (not paused)
- Try adding `?sslmode=require` to connection string

### Schema migration failed
- Go to Supabase SQL Editor
- Check for error messages
- Ensure you have admin permissions

### API can't connect to database
- Test connection locally first:
  ```bash
  psql -h [HOST] -U postgres -d postgres
  ```
- Verify password is correct
- Check IP whitelist (Supabase allows all by default)

### Vercel API still returning 500
- Check Vercel logs: Dashboard → Logs
- Verify all env vars are set correctly
- Try redeploying: `vercel deploy --prod`

---

## 💾 Backup & Restore

### Backup Supabase Database
```bash
pg_dump -h xxx.supabase.co -U postgres -d postgres > backup.sql
```

### Restore from Backup
```bash
psql -h xxx.supabase.co -U postgres -d postgres < backup.sql
```

---

## 🎯 Cost Estimate

| Component | Price |
|-----------|-------|
| Supabase (Free) | $0 |
| Vercel API (Free tier) | $0 |
| Vercel Web App | $0 |
| Custom domain | ~$10/year |
| **Total** | **~$10/year** |

Supabase free tier includes:
- 500 MB database
- 2 GB bandwidth
- Real-time API
- Auth with unlimited users

---

## 🔄 Next Steps

1. ✅ Create Supabase project (5 min)
2. ✅ Migrate schema (2 min)
3. ✅ Deploy API to Vercel (3 min)
4. ✅ Update environment variables (2 min)
5. ✅ Test login (5 min)

**Total time: ~20 minutes**

---

## 📞 Support

- **Supabase Docs:** https://supabase.com/docs
- **Vercel Docs:** https://vercel.com/docs
- **NESF Core API:** See `DEPLOYMENT.md` for original Cloud Run setup

---

## ✨ Summary

With Supabase + Vercel:
- ✅ Free database (PostgreSQL)
- ✅ Free API hosting
- ✅ Free web hosting
- ✅ Scales automatically
- ✅ No infrastructure management

Perfect for NESF Core's scale and budget!
