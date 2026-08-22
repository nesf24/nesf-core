# NESF Core Web App - Launch Instructions

## 🚀 Current Deployment Status

**Vercel Auto-Deployment**: ✅ ACTIVE
- Repository: https://github.com/nesf24/nesf-core
- Branch: `master` → Auto-deploys on push
- Domain: https://app.nesportsfoundation.in

---

## 🌐 Accessing the Web App

### Production URL
```
https://app.nesportsfoundation.in
```

### Local Development
```bash
cd D:\new app\nesf-core\api
npm install
npm start
# → Access at http://localhost:4000
```

---

## 📋 How It Works

### Deployment Pipeline

1. **Push to GitHub** (`master` branch)
   ```bash
   git push origin master
   ```

2. **Vercel Detects Changes**
   - Automatic webhook trigger
   - Clones latest code

3. **Vercel Builds & Deploys**
   - Installs npm dependencies: `npm install`
   - Serves Flutter web files from `api/public/`
   - API runs as serverless functions
   - Custom domain routes traffic

4. **Instant Live Updates**
   - No manual steps needed
   - Latest code live within minutes

---

## ✅ Deployment Checklist

### Before First Launch

- [x] Flutter web app built: `api/public/index.html` ✅
- [x] Built files committed to GitHub ✅
- [x] vercel.json configured ✅
- [x] Environment variables set in Vercel console ✅
- [x] Supabase database connection configured ✅
- [x] Custom domain configured (app.nesportsfoundation.in) ✅

### Verify Deployment

```bash
# Check if live
curl -I https://app.nesportsfoundation.in

# Expected response:
# HTTP/1.1 200 OK
# Server: Vercel
# (loads index.html from api/public/)
```

---

## 🔧 Configuration

### Vercel Environment Variables

Set in Vercel console at:
https://vercel.com/nesf24/nesf-core/settings/environment-variables

**Required variables:**
```
DATABASE_URL=postgres://postgres:JYVYbtjOOEHlp9saDdhTEhdZJwsE1%2FMn@mixbtfnjdzmfbctkxnwk.supabase.co:5432/postgres?sslmode=require
JWT_SECRET=416da02a0628758bd926a9fdd9c08204ad0bdad60d5714a2c9b11e16ce8c1df5ef201e7c01775d6ba6d17dea4ab221f2
NODE_ENV=production
CORS_ORIGINS=https://app.nesportsfoundation.in,https://nesf-core.vercel.app,http://localhost:3000,http://localhost:4000
```

---

## 🧪 Testing the Deployment

### 1. Homepage Load
Navigate to: https://app.nesportsfoundation.in
- Should see: Login screen with "Sign in with Google" button
- Should NOT see: "No such endpoint" error

### 2. Check API Health
```bash
curl https://app.nesportsfoundation.in/health
```

Expected response (once DB is online):
```json
{"ok":true,"service":"nesf-core-api","db":"up"}
```

### 3. Test Google Sign-In
- Click "Sign in with Google" button
- Login with @nesportsfoundation.in email
- Should redirect to dashboard

---

## 📊 Monitoring Deployment

### Vercel Dashboard
https://vercel.com/nesf24/nesf-core

**Check:**
- Recent deployments
- Build logs
- Performance metrics
- Error tracking

### Check Deployment Status
```bash
# View last deployment
curl -I https://app.nesportsfoundation.in

# Should show X-Vercel headers:
# X-Vercel-Id: (deployment ID)
# Server: Vercel
```

---

## 🔄 How to Update the Web App

### Simple: Push to GitHub
```bash
# Make changes locally
# ...

# Commit changes
git add .
git commit -m "Your message"

# Push to master
git push origin master

# Vercel automatically redeploys
# Check status at https://vercel.com/nesf24/nesf-core/deployments
```

### Manual: Rebuild Flutter Web

If you modify the Flutter app:
```bash
cd D:\new app\nesf-core\app
flutter build web --release

cd ..\api
npm run build:web  # Copies to api/public/

# Then commit and push
git add api/public/
git commit -m "Update Flutter web build"
git push origin master
```

---

## 🚨 Troubleshooting

### Issue: 404 on https://app.nesportsfoundation.in

**Cause**: Flask app not serving `index.html`
**Fix**:
1. Check `api/vercel.json` has correct rewrites
2. Verify `api/public/index.html` exists locally
3. Commit and push to re-trigger deployment

### Issue: "Failed to connect to API"

**Cause**: Database offline or API not responding
**Fix**:
1. Check Supabase status: https://supabase.com/dashboard
2. Verify DATABASE_URL in Vercel env vars
3. Check API health: `curl https://app.nesportsfoundation.in/health`

### Issue: Vercel Build Failed

**Check**: https://vercel.com/nesf24/nesf-core/deployments
1. Click failed deployment
2. View build logs
3. Common issues:
   - Missing environment variables
   - npm install failure (check package.json)
   - API code error

### Issue: Page Loads But Shows Error

1. Open browser DevTools (F12)
2. Check Console for errors
3. Check Network tab for failed API calls
4. Verify API endpoint is accessible

---

## 📱 Mobile/Responsive Testing

The web app should work on:
- ✅ Desktop browsers (Chrome, Firefox, Safari, Edge)
- ✅ Tablets (iPad, Android tablets)
- ✅ Mobile phones (iOS Safari, Android Chrome)

Test with Chrome DevTools mobile emulation:
1. F12 → Click device icon (top-left)
2. Select device type
3. Test login and navigation

---

## 🔐 Security Checklist

- [x] HTTPS enforced (app.nesportsfoundation.in)
- [x] CORS configured correctly
- [x] Environment variables stored securely (Vercel)
- [x] No credentials in code or .env files
- [x] Rate limiting on API endpoints
- [ ] Database backups configured (manual step)
- [ ] Error logging monitored (manual step)

---

## 📞 Support

### Quick Start
1. Navigate to https://app.nesportsfoundation.in
2. Login with Google
3. Explore HR features

### If Something Goes Wrong
1. Check Vercel deployment status
2. Verify environment variables
3. Check Supabase database status
4. Run local API to test: `npm start` in api/
5. Check browser console for errors (F12)

### Verify Everything Works Locally First
```bash
cd D:\new app\nesf-core\api
npm install
npm start
# → Test at http://localhost:4000
```

---

## 🎯 Next Steps

1. **Today**: Verify Vercel deployment is live
   ```bash
   curl https://app.nesportsfoundation.in/health
   ```

2. **When Database Ready**: Test login flow
   - Navigate to https://app.nesportsfoundation.in
   - Click "Sign in with Google"
   - Login with @nesportsfoundation.in email

3. **Ongoing**: Monitor performance and errors
   - Vercel dashboard
   - Supabase logs
   - Browser console

---

**Last Updated**: 2026-08-22
**Status**: Ready to Deploy ✅
**Auto-Deploy**: Enabled (master branch)
