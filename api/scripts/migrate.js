import 'dotenv/config';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import pool from '../src/db.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// schema.sql is written to be idempotent, so applying it is also how upgrades
// roll out — there is no separate migration ledger to keep in sync.
const sql = fs.readFileSync(path.join(__dirname, '..', 'schema.sql'), 'utf8');

try {
  await pool.query(sql);
  console.log('✓ Schema applied');
} catch (err) {
  console.error('✗ Migration failed:', err.message);
  process.exitCode = 1;
} finally {
  await pool.end();
}
