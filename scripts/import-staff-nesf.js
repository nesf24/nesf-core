import 'dotenv/config';
import bcrypt from 'bcryptjs';
import pool from '../src/db.js';

/**
 * Import NESF Foundation staff from onboarding responses
 * Creates user accounts with temporary passwords
 *
 * Run: DATABASE_URL=... node scripts/import-staff-nesf.js
 */

const staffData = [
  { emp_code: 'NESF-001', full_name: 'Tashi Dorjee Thongon', email: 'tashidorjeethongon@gmail.com', phone: '8731978807', designation: 'Operational Head', department: 'Administration', role: 'authority' },
  { emp_code: 'NESF-002', full_name: 'Bindiya Ligu', email: 'ligubindiya@gmail.com', phone: '7085696855', designation: 'Sports Psychologist', department: 'Programs', role: 'staff' },
  { emp_code: 'NESF-003', full_name: 'Tanyang Mobin', email: 'moventanyang@gmail.com', phone: '7005218418', designation: 'Chief Editor', department: 'Communications', role: 'manager' },
  { emp_code: 'NESF-004', full_name: 'Dipankar Barman', email: 'dipankarbarman343@gmail.com', phone: '9089276206', designation: 'Admin Head', department: 'Administration', role: 'manager' },
  { emp_code: 'NESF-005', full_name: 'BAPI MANDAL', email: 'bapimandal2468@gmail.com', phone: '7005515996', designation: 'Young Professional', department: 'Programs', role: 'staff' },
  { emp_code: 'NESF-006', full_name: 'Karan Nath', email: 'karannath2759@gmail.com', phone: '6009222190', designation: 'Young Professional', department: 'Programs', role: 'staff' },
  { emp_code: 'NESF-007', full_name: 'Nonya Radhe', email: 'nonyaradhe@gmail.com', phone: '6398580665', designation: 'Secretary', department: 'Administration', role: 'staff' },
  { emp_code: 'NESF-008', full_name: 'Tana Pumin', email: 'tanapumin17@gmail.com', phone: '8729979045', designation: 'Editor', department: 'Communications', role: 'staff' },
  { emp_code: 'NESF-009', full_name: 'Aditya Baruah', email: 'adityabaruah00@gmail.com', phone: '6001902629', designation: 'Young Professional', department: 'Programs', role: 'staff' },
  { emp_code: 'NESF-010', full_name: 'YOMLI BAM', email: 'peterpsych3@gmail.com', phone: '8259802618', designation: 'Photographer', department: 'Communications', role: 'staff' },
  { emp_code: 'NESF-011', full_name: 'Ony kino', email: 'Onykini53@gmail.com', phone: '8118983390', designation: 'Archery Coach', department: 'Sports', role: 'staff' },
  { emp_code: 'NESF-012', full_name: 'Dr.Tadar Anam (PT)', email: 'anamtadar11@gmail.com', phone: '8074303987', designation: 'Physiotherapist', department: 'Health', role: 'staff' },
  { emp_code: 'NESF-013', full_name: 'Michi Jaon Tanyang', email: 'Jaonmichi13@gmail.com', phone: '7005219019', designation: 'Young Professional', department: 'Programs', role: 'staff' },
  { emp_code: 'NESF-014', full_name: 'Tage sambyo', email: 'tagemoka180@gmail.com', phone: '7085164242', designation: 'Young Professional', department: 'Programs', role: 'staff' },
];

try {
  console.log('Importing NESF Foundation staff...\n');
  const hash = await bcrypt.hash('Nesf@2026', 10);
  let created = 0;
  let updated = 0;
  const credentials = [];

  for (const staff of staffData) {
    try {
      const { rows: existing } = await pool.query(
        'SELECT id FROM employees WHERE lower(email) = lower($1)',
        [staff.email]
      );

      if (existing[0]) {
        // Update existing
        await pool.query(
          `UPDATE employees SET full_name=$1, phone=$2, designation=$3,
           department=$4, role=$5, updated_at=NOW() WHERE id=$6`,
          [staff.full_name, staff.phone, staff.designation, staff.department, staff.role, existing[0].id]
        );
        console.log(`✓ Updated: ${staff.full_name} (${staff.email})`);
        updated++;
      } else {
        // Create new
        const { rows } = await pool.query(
          `INSERT INTO employees (emp_code, full_name, email, phone, password_hash,
            designation, department, role, is_active, must_change_pw)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, true, true) RETURNING id`,
          [staff.emp_code, staff.full_name, staff.email, staff.phone, hash,
           staff.designation, staff.department, staff.role]
        );
        console.log(`✓ Created: ${staff.full_name} (${staff.email})`);
        created++;
        credentials.push({
          email: staff.email,
          emp_code: staff.emp_code,
          name: staff.full_name,
          password: 'Nesf@2026',
          role: staff.role
        });
      }
    } catch (err) {
      console.error(`✗ Error with ${staff.email}: ${err.message}`);
    }
  }

  console.log(`\n✓ Import complete: ${created} created, ${updated} updated\n`);

  if (credentials.length > 0) {
    console.log('=== NEW STAFF CREDENTIALS ===\n');
    console.log('Temporary password for all new accounts: Nesf@2026');
    console.log('Staff must change password on first login.\n');

    credentials.forEach(c => {
      console.log(`${c.emp_code} | ${c.name}`);
      console.log(`  Email: ${c.email}`);
      console.log(`  Role: ${c.role}`);
      console.log();
    });
  }

  // Summary
  console.log('\n=== STAFF DIRECTORY ===\n');
  const { rows: allStaff } = await pool.query(
    `SELECT emp_code, full_name, email, designation, role FROM employees
     ORDER BY emp_code`
  );
  allStaff.forEach(s => {
    console.log(`${s.emp_code} | ${s.full_name} | ${s.email} | ${s.designation} | [${s.role}]`);
  });

  process.exit(0);
} catch (err) {
  console.error('✗ Import failed:', err.message);
  process.exit(1);
}
