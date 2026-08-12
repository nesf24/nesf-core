import 'dotenv/config';
import pg from 'pg';
import bcrypt from 'bcryptjs';
import pool from '../src/db.js';

/**
 * One-time import of the staff directory from the existing thenesports-api
 * database into NESF Core, so the office does not re-type everyone.
 *
 *   LEGACY_DATABASE_URL=postgres://... npm run import:employees
 *
 * Column mapping (legacy -> NESF Core):
 *   name            -> full_name
 *   doj             -> date_of_joining
 *   branch          -> department
 *   status='Active' -> is_active
 *   reporting_to_id -> reporting_to_id  (remapped to the new ids)
 *
 * Re-running is safe: existing people are matched on EMAIL ONLY and updated
 * rather than duplicated. Nothing is ever deleted.
 *
 * Matching deliberately ignores emp_code. The code is derived from the legacy
 * row id ("NESF-007"), and such a code can already belong to a different person
 * in NESF Core — the seeded admin is NESF-001 — so matching on it would rename
 * the wrong employee. Where a derived code is taken, a free variant is used.
 *
 * Every imported account gets a temporary password and must_change_pw = TRUE.
 * Legacy rows carry no password hash, so staff cannot sign in until the office
 * hands them the temporary password printed at the end of this run.
 */

const LEGACY_URL = process.env.LEGACY_DATABASE_URL;
if (!LEGACY_URL) {
  console.error('✗ Set LEGACY_DATABASE_URL to the thenesports-api database connection string.');
  console.error('  Example: LEGACY_DATABASE_URL=postgres://user:pass@host:5432/thenesports npm run import:employees');
  process.exit(1);
}

const legacy = new pg.Pool({
  connectionString: LEGACY_URL,
  ssl: process.env.LEGACY_DB_SSL === 'true' ? { rejectUnauthorized: false } : false,
});

// Temporary password for imported accounts; staff change it at first sign-in.
const TEMP_PASSWORD = process.env.IMPORT_TEMP_PASSWORD || 'Nesf@2026';

// Emails are the natural key, but the legacy table allows them to be blank.
// Those rows get a synthetic placeholder so the NOT NULL/UNIQUE holds, and are
// listed at the end so the office can fill in the real address.
function placeholderEmail(row) {
  const slug = String(row.name || 'staff').toLowerCase()
    .replace(/[^a-z0-9]+/g, '.').replace(/^\.|\.$/g, '').slice(0, 30);
  return `${slug}.${row.id}@staff.nesportsfoundation.in`;
}

try {
  const { rows: staff } = await legacy.query(
    `SELECT id, name, doj, phone, email, designation, branch, reporting_to_id, status, photo_url
       FROM employees ORDER BY id`
  );
  console.log(`Found ${staff.length} employees in the legacy database.\n`);
  if (!staff.length) process.exit(0);

  const hash = await bcrypt.hash(TEMP_PASSWORD, 10);
  const idMap = new Map();       // legacy id -> new id
  const missingEmail = [];
  let created = 0;
  let updated = 0;

  // Returns `preferred` if free, otherwise the first free "preferred-N".
  // Prevents a derived code from colliding with an existing employee's code.
  async function freeEmpCode(preferred) {
    for (let n = 0; n < 50; n++) {
      const candidate = n === 0 ? preferred : `${preferred}-${n}`;
      const { rows } = await pool.query(
        'SELECT 1 FROM employees WHERE emp_code = $1', [candidate]
      );
      if (!rows[0]) return candidate;
    }
    throw new Error(`Could not find a free employee code near ${preferred}`);
  }

  // Pass 1: upsert everyone without the reporting link, since a manager may
  // appear later in the list than their reportee.
  for (const row of staff) {
    const email = (row.email || '').trim() || placeholderEmail(row);
    if (!(row.email || '').trim()) missingEmail.push(row.name);

    const isActive = String(row.status || 'Active').toLowerCase() === 'active';

    // Email is the only safe identity here — see the note at the top of the file.
    const { rows: existing } = await pool.query(
      'SELECT id FROM employees WHERE lower(email) = lower($1) LIMIT 1',
      [email]
    );

    if (existing[0]) {
      // Do not touch role, password or signature on an existing account.
      const { rows } = await pool.query(
        `UPDATE employees SET full_name = $1, phone = COALESCE($2, phone),
                designation = COALESCE($3, designation),
                department = COALESCE($4, department),
                date_of_joining = COALESCE($5, date_of_joining),
                photo_url = COALESCE($6, photo_url),
                is_active = $7, updated_at = NOW()
          WHERE id = $8 RETURNING id`,
        [row.name, row.phone || null, row.designation || null, row.branch || null,
         row.doj || null, row.photo_url || null, isActive, existing[0].id]
      );
      idMap.set(String(row.id), rows[0].id);
      updated++;
    } else {
      // Preserve a recognisable code derived from the legacy id, sidestepping
      // any code already in use.
      const empCode = await freeEmpCode(`NESF-${String(row.id).padStart(3, '0')}`);
      const { rows } = await pool.query(
        `INSERT INTO employees (emp_code, full_name, email, phone, password_hash, role,
              designation, department, date_of_joining, photo_url, is_active, must_change_pw)
         VALUES ($1,$2,$3,$4,$5,'staff',$6,$7,$8,$9,$10,TRUE)
         RETURNING id`,
        [empCode, row.name, email, row.phone || null, hash, row.designation || null,
         row.branch || null, row.doj || null, row.photo_url || null, isActive]
      );
      idMap.set(String(row.id), rows[0].id);
      created++;
    }
  }

  // Pass 2: wire up the reporting hierarchy using the remapped ids.
  let linked = 0;
  for (const row of staff) {
    if (!row.reporting_to_id) continue;
    const newSelf = idMap.get(String(row.id));
    const newManager = idMap.get(String(row.reporting_to_id));
    if (!newSelf || !newManager || newSelf === newManager) continue;
    await pool.query('UPDATE employees SET reporting_to_id = $1 WHERE id = $2',
      [newManager, newSelf]);
    linked++;
  }

  // Anyone who has reportees is a manager, so approvals route correctly. The
  // authority role is deliberately left for an admin to assign by hand — that
  // decides whose signature appears on issued documents.
  const { rowCount: promoted } = await pool.query(
    `UPDATE employees SET role = 'manager'
      WHERE role = 'staff'
        AND id IN (SELECT DISTINCT reporting_to_id FROM employees WHERE reporting_to_id IS NOT NULL)`
  );

  console.log(`✓ created ${created}, updated ${updated}`);
  console.log(`✓ ${linked} reporting links restored`);
  console.log(`✓ ${promoted} promoted to 'manager' (they have reportees)`);
  console.log(`\nTemporary password for newly imported accounts: ${TEMP_PASSWORD}`);
  console.log('Staff must change it at first sign-in.');

  if (missingEmail.length) {
    console.log(`\n⚠ ${missingEmail.length} had no email — placeholder addresses were generated.`);
    console.log('  Update these from Settings → Staff before they can sign in:');
    for (const n of missingEmail) console.log(`   • ${n}`);
  }

  console.log('\n⚠ Next step: assign the "authority" role to whoever signs documents,');
  console.log('  and upload their signature image (Profile → Signature).');
} catch (err) {
  console.error('✗ Import failed:', err.message);
  process.exitCode = 1;
} finally {
  await legacy.end();
  await pool.end();
}
