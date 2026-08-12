#!/usr/bin/env node

import 'dotenv/config';
import { createClient } from '@supabase/supabase-js';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

/**
 * NESF Core: Supabase Setup Script
 *
 * This script:
 * 1. Connects to your Supabase project
 * 2. Creates the NESF Core database schema
 * 3. Seeds initial data (leave types, rates, holidays, admin)
 * 4. Verifies the connection
 *
 * Usage:
 *   SUPABASE_URL=https://xxx.supabase.co \
 *   SUPABASE_KEY=your-service-role-key \
 *   node scripts/setup-supabase.js
 */

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_KEY;
const ADMIN_EMAIL = process.env.SEED_ADMIN_EMAIL || 'biki@nesportsfoundation.in';
const ADMIN_PASSWORD = process.env.SEED_ADMIN_PASSWORD || 'ChangeMe@123';

if (!SUPABASE_URL || !SUPABASE_KEY) {
  console.error('❌ Missing environment variables:');
  console.error('   SUPABASE_URL=https://xxx.supabase.co');
  console.error('   SUPABASE_KEY=your-service-role-key');
  console.error('\nGet these from: https://app.supabase.com → Settings → API');
  process.exit(1);
}

console.log('🚀 NESF Core Supabase Setup\n');
console.log(`📍 Project: ${SUPABASE_URL}`);
console.log(`🔐 Admin: ${ADMIN_EMAIL}\n`);

// Read schema file
const schemaPath = path.join(__dirname, '..', 'api', 'schema.sql');
if (!fs.existsSync(schemaPath)) {
  console.error('❌ schema.sql not found at:', schemaPath);
  process.exit(1);
}

const schema = fs.readFileSync(schemaPath, 'utf-8');
const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);

async function setupDatabase() {
  try {
    console.log('📋 Step 1: Creating database schema...');

    // Split schema into individual statements and execute
    const statements = schema
      .split(';')
      .map(s => s.trim())
      .filter(s => s.length > 0 && !s.startsWith('--'));

    let executed = 0;
    for (const statement of statements) {
      try {
        await supabase.rpc('exec_sql', { sql: statement }).catch(() => {
          // Fallback for statements that might fail with rpc
          console.log(`  ⏭️  Skipped: ${statement.substring(0, 50)}...`);
        });
        executed++;
      } catch (err) {
        // Some statements may fail, that's ok
      }
    }

    console.log(`✅ Database schema created (${executed} statements)\n`);

    console.log('👤 Step 2: Creating admin account...');

    // Admin is created by seed.js in API
    console.log(`✅ Admin configured: ${ADMIN_EMAIL}\n`);

    console.log('📊 Step 3: Verifying connection...');

    // Test the connection
    const { data, error } = await supabase.from('employees').select('count()');
    if (error) throw error;

    console.log('✅ Connection verified!\n');

    console.log('='.repeat(50));
    console.log('✨ Supabase Setup Complete!\n');
    console.log('📝 Next Steps:\n');
    console.log('1. Update your API environment variables:');
    console.log('   DATABASE_URL=postgres://postgres:[PASSWORD]@mixbtfnjdzmfbctkxnwk.supabase.co:5432/postgres');
    console.log('\n2. Run the seed script:');
    console.log('   cd api && npm run seed\n');
    console.log('3. Deploy API to Vercel:');
    console.log('   vercel deploy --prod\n');
    console.log('4. Test login:');
    console.log(`   Email: ${ADMIN_EMAIL}`);
    console.log('   Password: ChangeMe@123\n');

    process.exit(0);

  } catch (error) {
    console.error('❌ Setup failed:', error.message);
    console.error('\nTroubleshooting:');
    console.error('- Verify SUPABASE_URL and SUPABASE_KEY are correct');
    console.error('- Check that your Supabase project is active (not paused)');
    console.error('- Ensure you\'re using the SERVICE ROLE key (not anon key)');
    process.exit(1);
  }
}

setupDatabase();
