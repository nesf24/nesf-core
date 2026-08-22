# NESF Core - Testing & Launch Guide

**Current Status**: ✅ Ready for Testing & Launching

---

## 📱 Testing the Android App

### Install APK on Device/Emulator

```bash
adb install -r "D:\new app\nesf-core\app\build\app\outputs\flutter-apk\app-debug.apk"
```

### What to Expect

1. **Splash Screen** (1.5 seconds)
   - Animated particles breaking apart and reassembling
   - NESF Foundation logo (yellow soccer ball with blue pentagon) bouncing
   - "Loading..." text below the logo

2. **Login Screen**
   - "Sign in with Google" button
   - Login requirements listed
   - Error message if API is not running (see troubleshooting below)

### Features Ready to Test

- ✅ Splash screen with animated logo
- ✅ Google Sign-In (Firebase integrated)
- ✅ App routing structure
- ✅ Provider state management
- ✅ Theme with NE SPORTS branding colors

---

## 🚀 Getting the API Running for Full Testing

### 1. Start the API Server (Local Testing)

```bash
cd "D:\new app\nesf-core\api"
npm start
```

The API will start on `http://localhost:4000`

Check health:
```bash
curl http://localhost:4000/health
```

### 2. Android Emulator Configuration

The app is already configured to reach the local API from Android emulator:
- **Emulator API endpoint**: `http://10.0.2.2:4000/api`
- **10.0.2.2** = host machine's localhost (special routing in Android emulator)

### 3. Database Status

**Current Issue**: Supabase database was paused and is being restored.

**Check status**:
1. Log into Supabase console at https://supabase.com/dashboard
2. Look for project: `thenesports-api`
3. Wait for restoration to complete (usually 5-15 minutes for small databases)

Once restoration is complete:
- API will connect to database ✅
- Login will work with test credentials
- All HR features will be functional

---

## 🔑 Test Credentials

### Admin User
- **Email**: `biki@nesportsfoundation.in`
- **Temporary Password**: `h5t/PaNtGRlEGflS` (set this in key.properties for APK signing)

### First Login Flow
1. Open app on device/emulator
2. Tap "Sign in with Google"
3. Select test account (must be @nesportsfoundation.in)
4. Account created automatically on first login
5. Will be given staff role by default

---

## 🌐 Web App Testing

### Local Testing
```bash
cd "D:\new app\nesf-core\api"
npm start
```

Navigate to: `http://localhost:4000`

### Production Testing
URL: `https://app.nesportsfoundation.in`

Note: Vercel deployment will auto-sync with latest code push to master branch

---

## 🧪 Testing Checklist

### Splash Screen
- [ ] Animated NESF Foundation logo bounces
- [ ] Particles break apart and reassemble
- [ ] Splash appears for ~1.5 seconds
- [ ] Transitions smoothly to login screen

### Login Screen
- [ ] Google Sign-In button visible and tappable
- [ ] Login requirements display correctly
- [ ] No force-close or crashes

### API Connection
- [ ] No socket timeout error (after database restoration)
- [ ] Health check endpoint responds
- [ ] API logs show successful connection

### Database
- [ ] Supabase restoration completed
- [ ] Login creates user record
- [ ] Can fetch staff/employee data

### Theming
- [ ] Blue (#1a237e) and Yellow (#FFC107) colors match branding
- [ ] Responsive layout on different screen sizes

---

## 📋 Known Issues & Fixes

### 1. Database Connection Timeout
**Status**: Supabase database being restored (in progress)
**Solution**: Wait 5-15 minutes, then restart the API

### 2. APK Signing (Release Build)
**Status**: Debug APK working, release signing config needs path fix
**Next Step**: Fix key.properties path resolution in build.gradle.kts

### 3. Firebase Authentication
**Status**: Configured and working
**Requirement**: Google Sign-In requires @nesportsfoundation.in domain email

---

## 🚀 Production Deployment Checklist

### Before Production Release

- [ ] Database restoration verified complete
- [ ] Login tested with real user account
- [ ] All staff can access dashboard
- [ ] Attendance, leave, reports workflows tested
- [ ] PDF document generation verified
- [ ] File uploads working (selfies, signatures, receipts)
- [ ] Permissions configured correctly

### APK Release (Google Play Store)

- [ ] Fix signing config path issue
- [ ] Build release APK: `flutter build apk --release`
- [ ] Test APK on multiple devices
- [ ] Update version code in pubspec.yaml
- [ ] Create Android App Bundle for Play Store
- [ ] Set up Google Play Console for app listing

### Web App Deployment

- [ ] Vercel deployment auto-syncs from master branch ✅
- [ ] Test at https://app.nesportsfoundation.in
- [ ] Verify SSL certificate valid
- [ ] Configure custom domain if needed

### Infrastructure

- [ ] Supabase database backed up
- [ ] Cloud Storage (if used) configured
- [ ] Rate limiting configured
- [ ] Error logging set up
- [ ] Monitoring/alerts configured

---

## 📞 Support & Troubleshooting

### Common Issues

#### "No Directionality widget found" Error
**Fixed** ✅ - Moved SplashOverlay inside MaterialApp

#### "SocketConnection timed out" Error
**Cause**: API not running or database not responding
**Fix**: 
1. Start API: `npm start` in api directory
2. Wait for Supabase restoration to complete
3. Restart app

#### APK Won't Install
**Fix**: Use `-r` flag to replace existing version:
```bash
adb install -r app-debug.apk
```

#### Can't Connect to API from Emulator
**Ensure**: Using `http://10.0.2.2:4000` (not localhost)
**Status**: Already configured in AppConfig ✅

---

## 📦 Build Information

- **Flutter Version**: 3.44.1
- **Android SDK**: 36
- **Min SDK**: 23
- **Target SDK**: Latest (36)
- **APK Size**: ~155 MB (debug)
- **App ID**: `in.nesportsfoundation.nesf_core`

---

## 🎯 Next Steps

1. **Immediate** (Today)
   - [ ] Test splash screen animation on device
   - [ ] Wait for Supabase restoration
   - [ ] Verify API connection

2. **This Week**
   - [ ] Test complete login flow
   - [ ] Test attendance check-in
   - [ ] Test document generation

3. **Before Release**
   - [ ] Fix release APK signing
   - [ ] Perform full workflow testing
   - [ ] Deploy to production

---

**Last Updated**: 2026-08-22
**Status**: Ready for Testing ✅
