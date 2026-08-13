#!/usr/bin/env node

/**
 * NESF Core — Import Staff from Excel Onboarding Form
 *
 * This script imports 14 staff members from the NESF Onboarding form directly
 * into the database with "staff" role (except Biki who remains "admin").
 *
 * Run from the api directory:
 *   npm run import:onboarding-staff
 *
 * Or directly:
 *   node scripts/import-onboarding-staff.js
 */

import 'dotenv/config';
import pg from 'pg';
import bcrypt from 'bcryptjs';

const { Pool } = pg;

// Use the DATABASE_URL from .env or .env.supabase
const DATABASE_URL = process.env.DATABASE_URL;
if (!DATABASE_URL) {
  console.error('✗ DATABASE_URL not set in .env or .env.supabase');
  process.exit(1);
}

const pool = new Pool({
  connectionString: DATABASE_URL,
  ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false,
  connectionTimeoutMillis: 15000,
  idleTimeoutMillis: 30000,
});

// Staff data from Excel (NESF Onboarding form responses)
const staffData = [
  { name: "Tashi Dorjee Thongon", email: "tashidorjeethongon@gmail.com", phone: "8731978807", designation: "Operational Head" },
  { name: "Bindiya Ligu", email: "ligubindiya@gmail.com", phone: "7085696855", designation: "Sports Psychologist" },
  { name: "Tanyang Mobin", email: "moventanyang@gmail.com", phone: "7005218418", designation: "Chief Editor" },
  { name: "Dipankar Barman", email: "dipankarbarman343@gmail.com", phone: "9089276206", designation: "Admin Head" },
  { name: "BAPI MANDAL", email: "bapimandal2468@gmail.com", phone: "7005515996", designation: "Young Professional" },
  { name: "Karan Nath", email: "karannath2759@gmail.com", phone: "6009222190", designation: "Young Professional" },
  { name: "Nonya Radhe", email: "nonyaradhe@gmail.com", phone: "6398580665", designation: "Secretary" },
  { name: "Tana Pumin", email: "tanapumin17@gmail.com", phone: "8729979045", designation: "Editor" },
  { name: "Aditya Baruah", email: "adityabaruah00@gmail.com", phone: "6001902629", designation: "Young Professional" },
  { name: "YOMLI BAM", email: "peterpsych3@gmail.com", phone: "8259802618", designation: "Photographer" },
  { name: "Ony kino", email: "Onykini53@gmail.com", phone: "8118983390", designation: "Archery Coach" },
  { name: "Dr.Tadar Anam (PT)", email: "anamtadar11@gmail.com", phone: "8074303987", designation: "Phsyiotherapist" },
  { name: "Michi Jaon Tanyang", email: "Jaonmichi13@gmail.com", phone: "7005219019", designation: "Young Professional" },
  { name: "Tage sambyo", email: "tagemoka180@gmail.com", phone: "7085164242", designation: "Young Professional" }
];

// Temporary password for new accounts
const TEMP_PASSWORD = 'Nesf@2026';

async function freeEmpCode(pool, preferred) {
  for (let n = 0; n < 50; n++) {
    const candidate = n === 0 ? preferred : `${preferred}-${n}`;
    const { rows } = await pool.query(
      'SELECT 1 FROM employees WHERE emp_code = $1', [candidate]
    );
    if (!rows[0]) return candidate;
  }
  throw new Error(`Could not find a free employee code near ${preferred}`);
}

try {
  console.log('🚀 NESF Core — Staff Onboarding Import\n');
  console.log(`📍 Database: ${DATABASE_URL.replace(/:[^@]*@/, ':***@')}`);
  console.log(`📊 Staff to import: ${staffData.length}\n`);

  const hash = await bcrypt.hash(TEMP_PASSWORD, 10);
  const client = await pool.connect();

  let created = 0;
  let updated = 0;
  const results = {
    success: [],
    errors: [],
    total: staffData.length
  };

  try {
    // Begin transaction
    await client.query('BEGIN');

    // Process each staff member
    for (let i = 0; i < staffData.length; i++) {
      const row = staffData[i];
      const email = row.email.trim().toLowerCase();

      try {
        // Check if email already exists
        const { rows: existing } = await client.query(
          'SELECT id, full_name, role FROM employees WHERE lower(email) = $1 LIMIT 1',
          [email]
        );

        if (existing[0]) {
          // Update existing record (preserve role and password)
          const { rows: updated_row } = await client.query(
            `UPDATE employees
             SET full_name = $1,
                 phone = COALESCE($2, phone),
                 designation = COALESCE($3, designation),
                 is_active = true,
                 updated_at = NOW()
             WHERE id = $4
             RETURNING id, emp_code, full_name, email, role`,
            [row.name, row.phone || null, row.designation || null, existing[0].id]
          );

          results.success.push({
            emp_code: updated_row[0].emp_code,
            name: updated_row[0].full_name,
            email: updated_row[0].email,
            role: updated_row[0].role,
            action: 'updated'
          });

          console.log(`✓ [${i + 1}/14] UPDATED: ${row.name} (${existing[0].role})`);
          updated++;
        } else {
          // Create new staff member
          const empCode = await freeEmpCode(pool, `NESF-${String(i + 1).padStart(3, '0')}`);
          const { rows: new_row } = await client.query(
            `INSERT INTO employees (
              emp_code, full_name, email, phone, password_hash, role,
              designation, is_active, must_change_pw
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
            RETURNING id, emp_code, full_name, email, role`,
            [
              empCode, row.name, email, row.phone || null, hash, 'staff',
              row.designation || null, true, true
            ]
          );

          results.success.push({
            emp_code: new_row[0].emp_code,
            name: new_row[0].full_name,
            email: new_row[0].email,
            role: new_row[0].role,
            action: 'created'
          });

          console.log(`✓ [${i + 1}/14] CREATED: ${empCode} - ${row.name}`);
          created++;
        }
      } catch (error) {
        results.errors.push({
          name: row.name,
          email: row.email,
          error: error.message
        });
        console.log(`✗ [${i + 1}/14] ERROR: ${row.name} - ${error.message}`);
      }
    }

    // Commit the transaction
    await client.query('COMMIT');

    console.log('\n' + '='.repeat(60));
    console.log('VERIFICATION — Querying Database\n');

    // Verify the import
    const { rows: staffRows } = await client.query(
      `SELECT id, emp_code, full_name, email, phone, designation, role, created_at
       FROM employees
       WHERE role = 'staff'
       ORDER BY created_at DESC
       LIMIT 14`
    );

    console.log(`Total staff records: ${staffRows.length}\n`);

    staffRows.forEach((row, idx) => {
      console.log(`${idx + 1}. [${row.emp_code}] ${row.full_name}`);
      console.log(`   Email: ${row.email}`);
      console.log(`   Phone: ${row.phone}`);
      console.log(`   Designation: ${row.designation}`);
      console.log(`   Role: ${row.role}`);
      console.log();
    });

    // Check admin user
    console.log('='.repeat(60));
    console.log('Admin Verification:\n');

    const { rows: adminRows } = await client.query(
      `SELECT id, emp_code, full_name, email, role
       FROM employees
       WHERE role = 'admin'
       ORDER BY created_at DESC`
    );

    if (adminRows.length > 0) {
      console.log('Admin users in database:');
      adminRows.forEach(row => {
        console.log(`  ✓ ${row.full_name} (${row.email}) [${row.role}]`);
      });
    } else {
      console.log('⚠️  No admin users found.');
      console.log('   Biki (biki@nesportsfoundation.in) should be created as admin.');
    }

    client.release();

  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  }

  console.log('\n' + '='.repeat(60));
  console.log('IMPORT SUMMARY\n');
  console.log(`✓ Created: ${created}`);
  console.log(`✓ Updated: ${updated}`);
  console.log(`Total processed: ${created + updated}`);
  console.log(`✗ Errors: ${results.errors.length}`);

  if (results.errors.length > 0) {
    console.log('\nErrors:');
    results.errors.forEach(err => {
      console.log(`  • ${err.name} (${err.email}): ${err.error}`);
    });
  }

  console.log('\n📝 Temporary password for new staff: ' + TEMP_PASSWORD);
  console.log('   Staff must change it at first sign-in.\n');

  console.log('='.repeat(60) + '\n');

  // Save report
  const report = { created, updated, errors: results.errors.length, staff: results.success };
  const fs = await import('fs');
  fs.writeFileSync('./import-report.json', JSON.stringify(report, null, 2));
  console.log('Report saved to: import-report.json\n');

} catch (err) {
  console.error('✗ Import failed:', err.message);
  console.error(err.stack);
  process.exitCode = 1;
} finally {
  await pool.end();
}
