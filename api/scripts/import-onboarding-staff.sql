-- NESF Core: Import Staff from Excel Onboarding Form
-- Database: mixbtfnjdzmfbctkxnwk.supabase.co
-- Table: public.employees
--
-- Instructions:
-- 1. Go to https://supabase.com → Your Project → SQL Editor
-- 2. Create a new query
-- 3. Copy-paste this entire script
-- 4. Click "Run"
--
-- This script creates 14 new staff members from the NESF Onboarding form.
-- All staff are assigned role='staff' and is_active=true.
-- Existing records (matched by email) are skipped to prevent duplicates.

BEGIN;

-- Staff 1: Tashi Dorjee Thongon
INSERT INTO employees (emp_code, full_name, email, phone, designation, role, is_active, created_at, updated_at)
VALUES ('NESF-001', 'Tashi Dorjee Thongon', 'tashidorjeethongon@gmail.com', '8731978807', 'Operational Head', 'staff', true, NOW(), NOW())
ON CONFLICT (email) DO UPDATE SET updated_at = NOW();

-- Staff 2: Bindiya Ligu
INSERT INTO employees (emp_code, full_name, email, phone, designation, role, is_active, created_at, updated_at)
VALUES ('NESF-002', 'Bindiya Ligu', 'ligubindiya@gmail.com', '7085696855', 'Sports Psychologist', 'staff', true, NOW(), NOW())
ON CONFLICT (email) DO UPDATE SET updated_at = NOW();

-- Staff 3: Tanyang Mobin
INSERT INTO employees (emp_code, full_name, email, phone, designation, role, is_active, created_at, updated_at)
VALUES ('NESF-003', 'Tanyang Mobin', 'moventanyang@gmail.com', '7005218418', 'Chief Editor', 'staff', true, NOW(), NOW())
ON CONFLICT (email) DO UPDATE SET updated_at = NOW();

-- Staff 4: Dipankar Barman
INSERT INTO employees (emp_code, full_name, email, phone, designation, role, is_active, created_at, updated_at)
VALUES ('NESF-004', 'Dipankar Barman', 'dipankarbarman343@gmail.com', '9089276206', 'Admin Head', 'staff', true, NOW(), NOW())
ON CONFLICT (email) DO UPDATE SET updated_at = NOW();

-- Staff 5: BAPI MANDAL
INSERT INTO employees (emp_code, full_name, email, phone, designation, role, is_active, created_at, updated_at)
VALUES ('NESF-005', 'BAPI MANDAL', 'bapimandal2468@gmail.com', '7005515996', 'Young Professional', 'staff', true, NOW(), NOW())
ON CONFLICT (email) DO UPDATE SET updated_at = NOW();

-- Staff 6: Karan Nath
INSERT INTO employees (emp_code, full_name, email, phone, designation, role, is_active, created_at, updated_at)
VALUES ('NESF-006', 'Karan Nath', 'karannath2759@gmail.com', '6009222190', 'Young Professional', 'staff', true, NOW(), NOW())
ON CONFLICT (email) DO UPDATE SET updated_at = NOW();

-- Staff 7: Nonya Radhe
INSERT INTO employees (emp_code, full_name, email, phone, designation, role, is_active, created_at, updated_at)
VALUES ('NESF-007', 'Nonya Radhe', 'nonyaradhe@gmail.com', '6398580665', 'Secretary', 'staff', true, NOW(), NOW())
ON CONFLICT (email) DO UPDATE SET updated_at = NOW();

-- Staff 8: Tana Pumin
INSERT INTO employees (emp_code, full_name, email, phone, designation, role, is_active, created_at, updated_at)
VALUES ('NESF-008', 'Tana Pumin', 'tanapumin17@gmail.com', '8729979045', 'Editor', 'staff', true, NOW(), NOW())
ON CONFLICT (email) DO UPDATE SET updated_at = NOW();

-- Staff 9: Aditya Baruah
INSERT INTO employees (emp_code, full_name, email, phone, designation, role, is_active, created_at, updated_at)
VALUES ('NESF-009', 'Aditya Baruah', 'adityabaruah00@gmail.com', '6001902629', 'Young Professional', 'staff', true, NOW(), NOW())
ON CONFLICT (email) DO UPDATE SET updated_at = NOW();

-- Staff 10: YOMLI BAM
INSERT INTO employees (emp_code, full_name, email, phone, designation, role, is_active, created_at, updated_at)
VALUES ('NESF-010', 'YOMLI BAM', 'peterpsych3@gmail.com', '8259802618', 'Photographer', 'staff', true, NOW(), NOW())
ON CONFLICT (email) DO UPDATE SET updated_at = NOW();

-- Staff 11: Ony kino
INSERT INTO employees (emp_code, full_name, email, phone, designation, role, is_active, created_at, updated_at)
VALUES ('NESF-011', 'Ony kino', 'onykini53@gmail.com', '8118983390', 'Archery Coach', 'staff', true, NOW(), NOW())
ON CONFLICT (email) DO UPDATE SET updated_at = NOW();

-- Staff 12: Dr.Tadar Anam (PT)
INSERT INTO employees (emp_code, full_name, email, phone, designation, role, is_active, created_at, updated_at)
VALUES ('NESF-012', 'Dr.Tadar Anam (PT)', 'anamtadar11@gmail.com', '8074303987', 'Phsyiotherapist', 'staff', true, NOW(), NOW())
ON CONFLICT (email) DO UPDATE SET updated_at = NOW();

-- Staff 13: Michi Jaon Tanyang
INSERT INTO employees (emp_code, full_name, email, phone, designation, role, is_active, created_at, updated_at)
VALUES ('NESF-013', 'Michi Jaon Tanyang', 'jaonmichi13@gmail.com', '7005219019', 'Young Professional', 'staff', true, NOW(), NOW())
ON CONFLICT (email) DO UPDATE SET updated_at = NOW();

-- Staff 14: Tage sambyo
INSERT INTO employees (emp_code, full_name, email, phone, designation, role, is_active, created_at, updated_at)
VALUES ('NESF-014', 'Tage sambyo', 'tagemoka180@gmail.com', '7085164242', 'Young Professional', 'staff', true, NOW(), NOW())
ON CONFLICT (email) DO UPDATE SET updated_at = NOW();

-- Verify the import
SELECT
  COUNT(*) as total_staff,
  COUNT(CASE WHEN role = 'staff' THEN 1 END) as staff_count,
  COUNT(CASE WHEN role = 'admin' THEN 1 END) as admin_count
FROM employees;

COMMIT;
