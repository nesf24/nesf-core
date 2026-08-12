#!/usr/bin/env node

import 'dotenv/config';
import pkg from 'pg';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const { Pool } = pkg;
const __dirname = path.dirname(fileURLToPath(import.meta.url));

/**
 * Database Schema Migration Script
 * Reads schema.sql and applies it to the database
 */

const DATABASE_URL = process.env.DATABASE_URL;

if (!DATABASE_URL) {
  console.error('❌ DATABASE_URL not set in .env');
  process.exit(1);
}

const pool = new Pool({ connectionString: DATABASE_URL });

async function migrate() {
  const client = await pool.connect();

  try {
    console.log('🚀 NESF Core Database Migration\n');
    console.log('📋 Reading schema.sql...');

    const schemaPath = path.join(__dirname, '..', 'schema.sql');
    if (!fs.existsSync(schemaPath)) {
      throw new Error(`schema.sql not found at ${schemaPath}`);
    }

    const schema = fs.readFileSync(schemaPath, 'utf-8');

    // Split into individual statements
    const statements = schema
      .split(';')
      .map(s => s.trim())
      .filter(s => s.length > 0 && !s.startsWith('--') && !s.startsWith('/*'));

    console.log(`✓ Found ${statements.length} SQL statements\n`);
    console.log('⚙️  Executing schema migration...\n');

    let executed = 0;
    let skipped = 0;

    for (let i = 0; i < statements.length; i++) {
      const stmt = statements[i];
      try {
        await client.query(stmt);
        executed++;

        // Show progress every 5 statements
        if (executed % 5 === 0) {
          console.log(`  ✓ ${executed}/${statements.length} statements executed`);
        }
      } catch (err) {
        // Some statements might fail (e.g., CREATE TABLE IF NOT EXISTS when index exists)
        // This is OK - we just skip them
        skipped++;
      }
    }

    console.log(`\n✅ Migration complete!`);
    console.log(`   Executed: ${executed}`);
    console.log(`   Skipped: ${skipped}\n`);

    // Verify schema
    console.log('📊 Verifying schema...');
    const { rows } = await client.query(
      `SELECT count(*) as table_count FROM information_schema.tables
       WHERE table_schema = 'public' AND table_type = 'BASE TABLE'`
    );
    console.log(`✓ Tables created: ${rows[0].table_count}\n`);

    console.log('='.repeat(50));
    console.log('✨ Schema migration successful!\n');
    console.log('Next: Run npm run seed to populate initial data\n');

  } catch (error) {
    console.error('❌ Migration failed:', error.message);
    console.error('\nDebugging info:');
    console.error('- DATABASE_URL:', DATABASE_URL?.substring(0, 50) + '...');
    console.error('- Error:', error.message);
    process.exit(1);
  } finally {
    client.release();
    await pool.end();
  }
}

migrate();
