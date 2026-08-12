import 'dotenv/config';
import bcrypt from 'bcryptjs';
import pool from '../src/db.js';
import { toPaise } from '../src/utils.js';

// Leave entitlements. Adjust quotas from Settings once the HR policy is fixed.
const LEAVE_TYPES = [
  { code: 'CL', name: 'Casual Leave', quota: 12, paid: true, carry: false, order: 1 },
  { code: 'EL', name: 'Earned Leave', quota: 15, paid: true, carry: true, order: 2 },
  { code: 'ML', name: 'Medical Leave', quota: 10, paid: true, carry: false, order: 3 },
  { code: 'CO', name: 'Compensatory Off', quota: 0, paid: true, carry: false, order: 4 },
  { code: 'MAT', name: 'Maternity Leave', quota: 180, paid: true, carry: false, order: 5 },
  { code: 'PAT', name: 'Paternity Leave', quota: 15, paid: true, carry: false, order: 6 },
  { code: 'LWP', name: 'Leave Without Pay', quota: 0, paid: false, carry: false, order: 7 },
  { code: 'OD', name: 'On Duty / Official Tour', quota: 0, paid: true, carry: false, order: 8 },
];

// Per-km road rates; air and train are reimbursed on the actual ticket.
const TA_RATES = [
  { mode: 'two_wheeler', per_km: 5, actual: false },
  { mode: 'own_car', per_km: 12, actual: false },
  { mode: 'taxi', per_km: 15, actual: false },
  { mode: 'bus', per_km: 0, actual: true },
  { mode: 'shared', per_km: 0, actual: true },
  { mode: 'train', per_km: 0, actual: true },
  { mode: 'air', per_km: 0, actual: true },
  { mode: 'other', per_km: 0, actual: true },
];

// DA slabs by grade and where the duty was performed.
const DA_RATES = [
  { grade: 'default', area: 'ordinary', per_day: 300, lodging: 800 },
  { grade: 'default', area: 'state_capital', per_day: 450, lodging: 1500 },
  { grade: 'default', area: 'metro', per_day: 600, lodging: 2500 },
  { grade: 'A', area: 'ordinary', per_day: 500, lodging: 1500 },
  { grade: 'A', area: 'state_capital', per_day: 700, lodging: 2500 },
  { grade: 'A', area: 'metro', per_day: 1000, lodging: 4000 },
  { grade: 'B', area: 'ordinary', per_day: 400, lodging: 1200 },
  { grade: 'B', area: 'state_capital', per_day: 550, lodging: 2000 },
  { grade: 'B', area: 'metro', per_day: 750, lodging: 3000 },
  { grade: 'C', area: 'ordinary', per_day: 300, lodging: 800 },
  { grade: 'C', area: 'state_capital', per_day: 450, lodging: 1500 },
  { grade: 'C', area: 'metro', per_day: 600, lodging: 2500 },
];

// Arunachal Pradesh / national holidays for the current year. Verify against the
// state gazette each January — these are the commonly observed dates.
function holidaysFor(year) {
  return [
    [`${year}-01-01`, 'New Year’s Day'],
    [`${year}-01-26`, 'Republic Day'],
    [`${year}-02-20`, 'Statehood Day (Arunachal Pradesh)'],
    [`${year}-04-14`, 'Ambedkar Jayanti'],
    [`${year}-05-01`, 'May Day'],
    [`${year}-08-15`, 'Independence Day'],
    [`${year}-10-02`, 'Gandhi Jayanti'],
    [`${year}-12-25`, 'Christmas Day'],
  ];
}

try {
  // -- Leave types -----------------------------------------------------------
  for (const t of LEAVE_TYPES) {
    await pool.query(
      `INSERT INTO leave_types (code, name, annual_quota, is_paid, carry_forward, sort_order)
       VALUES ($1,$2,$3,$4,$5,$6)
       ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name`,
      [t.code, t.name, t.quota, t.paid, t.carry, t.order]
    );
  }
  console.log(`✓ ${LEAVE_TYPES.length} leave types`);

  // -- TA / DA rates ---------------------------------------------------------
  for (const r of TA_RATES) {
    const { rows } = await pool.query(
      'SELECT id FROM ta_rates WHERE mode = $1 AND grade IS NULL LIMIT 1', [r.mode]
    );
    if (!rows[0]) {
      // Back-date the opening rates so claims for travel earlier in the year
      // still resolve a rate instead of falling back.
      await pool.query(
        `INSERT INTO ta_rates (mode, grade, paise_per_km, actual_fare, effective_from)
         VALUES ($1, NULL, $2, $3, DATE '2026-01-01')`,
        [r.mode, toPaise(r.per_km), r.actual]
      );
    }
  }
  for (const d of DA_RATES) {
    await pool.query(
      `INSERT INTO da_rates (grade, area, da_paise_per_day, lodging_cap_paise, effective_from)
       VALUES ($1, $2, $3, $4, DATE '2026-01-01')
       ON CONFLICT (grade, area, effective_from) DO NOTHING`,
      [d.grade, d.area, toPaise(d.per_day), toPaise(d.lodging)]
    );
  }
  console.log(`✓ ${TA_RATES.length} TA rates, ${DA_RATES.length} DA slabs`);

  // -- Holidays --------------------------------------------------------------
  const year = new Date().getFullYear();
  for (const [date, name] of holidaysFor(year)) {
    await pool.query(
      `INSERT INTO holidays (holiday_on, name, kind) VALUES ($1, $2, 'public')
       ON CONFLICT (holiday_on) DO NOTHING`,
      [date, name]
    );
  }
  console.log(`✓ holidays for ${year}`);

  // -- Founding admin --------------------------------------------------------
  const email = process.env.SEED_ADMIN_EMAIL || 'admin@nesportsfoundation.in';
  const password = process.env.SEED_ADMIN_PASSWORD || 'ChangeMe@123';

  const { rows: existing } = await pool.query(
    'SELECT id FROM employees WHERE lower(email) = lower($1)', [email]
  );

  if (existing[0]) {
    console.log(`• admin ${email} already exists (id ${existing[0].id}) — left unchanged`);
  } else {
    const { rows } = await pool.query(
      `INSERT INTO employees (emp_code, full_name, email, password_hash, role, designation,
                              department, grade, signature_title, is_active, must_change_pw)
       VALUES ('NESF-001', $1, $2, $3, 'admin', 'Founder & Chief Functionary',
               'Administration', 'A', 'Chief Functionary', TRUE, TRUE)
       RETURNING id`,
      ['Bikram Bharadwaj', email, await bcrypt.hash(password, 10)]
    );
    console.log(`✓ admin created: ${email} / ${password} (id ${rows[0].id})`);
    console.log('  ⚠ Sign in and change this password immediately.');
  }

  console.log('\nSeed complete.');
} catch (err) {
  console.error('✗ Seed failed:', err.message);
  process.exitCode = 1;
} finally {
  await pool.end();
}
