# NESF Staff Import Guide

## Overview

This guide provides instructions for importing 14 staff members from the NESF Onboarding Excel form into the Supabase database.

**Staff to be imported:**
1. Tashi Dorjee Thongon (Operational Head)
2. Bindiya Ligu (Sports Psychologist)
3. Tanyang Mobin (Chief Editor)
4. Dipankar Barman (Admin Head)
5. BAPI MANDAL (Young Professional)
6. Karan Nath (Young Professional)
7. Nonya Radhe (Secretary)
8. Tana Pumin (Editor)
9. Aditya Baruah (Young Professional)
10. YOMLI BAM (Photographer)
11. Ony kino (Archery Coach)
12. Dr.Tadar Anam (PT) (Phsyiotherapist)
13. Michi Jaon Tanyang (Young Professional)
14. Tage sambyo (Young Professional)

**Database Details:**
- Project: mixbtfnjdzmfbctkxnwk.supabase.co
- Database: postgres
- Table: public.employees
- All staff will have role: `staff`
- Admin (biki@nesportsfoundation.in) will retain role: `admin`

---

## Method 1: Supabase Web Console (Recommended)

This is the easiest method if you don't have direct network access to the database.

### Steps:

1. **Open Supabase Dashboard:**
   - Go to https://supabase.com
   - Sign in to your account
   - Select the project: **mixbtfnjdzmfbctkxnwk**

2. **Navigate to SQL Editor:**
   - Click **SQL Editor** in the left sidebar
   - Click **New query**

3. **Copy the SQL Script:**
   - Open the file: `api/scripts/import-onboarding-staff.sql`
   - Copy the entire contents

4. **Paste and Execute:**
   - Paste the SQL script into the query editor
   - Click the **Run** button (or press Ctrl+Enter)
   - The script will create all 14 staff members

5. **Verify:**
   - You should see output showing:
     - 14 new employee records created with role='staff'
     - Admin users preserved in the system

---

## Method 2: Node.js Script (from NESF Core API)

If you have network access from the API server:

```bash
cd D:\new\ app\nesf-core\api

# First, ensure .env or .env.supabase is properly configured
cat .env.supabase

# Run the import script
npm run import:onboarding-staff
```

**Requirements:**
- Node.js 18+
- npm packages installed (`npm install`)
- Network connectivity to Supabase from the API server

---

## Method 3: psql Command Line

If you have the PostgreSQL client installed:

```bash
# Using the connection string
psql "postgres://postgres:NEsports%40%232026@mixbtfnjdzmfbctkxnwk.supabase.co:5432/postgres?sslmode=require" \
  -f api/scripts/import-onboarding-staff.sql
```

---

## Employee Codes

Each staff member is assigned a unique employee code:

- NESF-001: Tashi Dorjee Thongon
- NESF-002: Bindiya Ligu
- NESF-003: Tanyang Mobin
- NESF-004: Dipankar Barman
- NESF-005: BAPI MANDAL
- NESF-006: Karan Nath
- NESF-007: Nonya Radhe
- NESF-008: Tana Pumin
- NESF-009: Aditya Baruah
- NESF-010: YOMLI BAM
- NESF-011: Ony kino
- NESF-012: Dr.Tadar Anam (PT)
- NESF-013: Michi Jaon Tanyang
- NESF-014: Tage sambyo

---

## Verification

After import, verify the records in Supabase:

### Query 1: Check staff count
```sql
SELECT COUNT(*) as staff_count, COUNT(CASE WHEN role = 'admin' THEN 1 END) as admin_count
FROM employees;
```

**Expected result:** 14 staff, 1+ admin

### Query 2: List all staff
```sql
SELECT emp_code, full_name, email, phone, designation, role, is_active
FROM employees
WHERE role = 'staff'
ORDER BY emp_code;
```

**Expected result:** 14 rows with all staff details

### Query 3: Check for Biki (admin)
```sql
SELECT emp_code, full_name, email, role
FROM employees
WHERE email = 'biki@nesportsfoundation.in';
```

**Expected result:** 1 row with role='admin'

---

## Troubleshooting

### "Connection timeout" errors

**Cause:** Local network doesn't have external access to Supabase.

**Solution:** Use **Method 1** (Supabase Web Console) instead, which works from any browser.

### "Duplicate email" errors

**Cause:** A staff member already exists in the database with that email.

**Solution:** The SQL script uses `ON CONFLICT DO UPDATE`, so it will skip duplicates automatically. No action needed.

### "Role enum validation" errors

**Cause:** Role value is invalid (must be 'staff', 'manager', 'authority', or 'admin').

**Solution:** This shouldn't happen with the provided scripts. All staff are assigned role='staff' only.

---

## Support

For issues or questions:
- Check the import script logs for specific error messages
- Verify the database connection details
- Ensure Supabase project is active (not paused)
- Contact the database administrator

---

## Files Included

```
D:\new app\nesf-core\
├── STAFF_IMPORT_GUIDE.md          ← This file
├── api/
│   ├── scripts/
│   │   ├── import-onboarding-staff.js    ← Node.js import script
│   │   └── import-onboarding-staff.sql   ← SQL import script
│   └── package.json                      ← Updated with import:onboarding-staff script
```

---

## Created: 2026-08-13
## Last Updated: 2026-08-13
