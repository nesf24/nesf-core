#!/usr/bin/env node

import 'dotenv/config';
import bcrypt from 'bcryptjs';
import pkg from 'pg';

const { Pool } = pkg;

/**
 * NESF Core Database Seeder
 *
 * Creates initial data:
 * - Admin account (biki@nesportsfoundation.in)
 * - Leave types
 * - TA/DA rates
 * - Holidays
 */

const DATABASE_URL = process.env.DATABASE_URL;

if (!DATABASE_URL) {
  console.error('❌ DATABASE_URL not set in .env');
  process.exit(1);
}

const pool = new Pool({ connectionString: DATABASE_URL });

async function seed() {
  const client = await pool.connect();

  try {
    console.log('🌱 Seeding NESF Core database...\n');

    // Admin account
    console.log('👤 Creating admin account...');
    const adminPassword = await bcrypt.hash('ChangeMe@123', 10);
    const adminEmail = 'biki@nesportsfoundation.in';

    await client.query(
      `INSERT INTO employees (emp_code, full_name, email, phone, password_hash, role, designation, department, is_active, must_change_pw)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
       ON CONFLICT (email) DO UPDATE SET password_hash = $5`,
      ['NESF-ADMIN', 'NESF Administrator', adminEmail, '+91-9999999999', adminPassword, 'admin', 'Administrator', 'Administration', true, false]
    );
    console.log(`✓ Admin: ${adminEmail} / ChangeMe@123\n`);

    // Leave types
    console.log('📋 Creating leave types...');
    const leaveTypes = [
      { code: 'CL', name: 'Casual Leave', days_per_year: 12 },
      { code: 'SL', name: 'Sick Leave', days_per_year: 8 },
      { code: 'EL', name: 'Earned Leave', days_per_year: 20 },
      { code: 'ML', name: 'Maternity Leave', days_per_year: 180 },
    ];

    for (const type of leaveTypes) {
      await client.query(
        `INSERT INTO leave_types (code, name, days_per_year, is_active)
         VALUES ($1, $2, $3, true)
         ON CONFLICT (code) DO UPDATE SET name = $2, days_per_year = $3`,
        [type.code, type.name, type.days_per_year]
      );
    }
    console.log(`✓ ${leaveTypes.length} leave types created\n`);

    // TA/DA Rates
    console.log('💰 Creating TA/DA rates...');
    const rateTypes = [
      {
        grade: 'A',
        rate_name: 'TA/DA Grade A',
        daily_rate_paise: 100000,  // ₹1000
        distance_from_base_m: 50000 // 50 km
      },
      {
        grade: 'B',
        rate_name: 'TA/DA Grade B',
        daily_rate_paise: 80000,   // ₹800
        distance_from_base_m: 30000 // 30 km
      },
    ];

    for (const rate of rateTypes) {
      await client.query(
        `INSERT INTO ta_da_rates (grade, rate_name, daily_rate_paise, distance_from_base_m, valid_from, valid_to, is_active)
         VALUES ($1, $2, $3, $4, NOW(), NULL, true)
         ON CONFLICT (grade, valid_from) DO UPDATE SET rate_name = $2, daily_rate_paise = $3, distance_from_base_m = $4`,
        [rate.grade, rate.rate_name, rate.daily_rate_paise, rate.distance_from_base_m]
      );
    }
    console.log(`✓ ${rateTypes.length} TA/DA rate schedules created\n`);

    // Holidays
    console.log('🎉 Creating holiday calendar...');
    const holidays = [
      { date: '2026-01-26', name: 'Republic Day', state: 'National' },
      { date: '2026-03-08', name: 'Maha Shivaratri', state: 'National' },
      { date: '2026-03-25', name: 'Holi', state: 'National' },
      { date: '2026-04-02', name: 'Good Friday', state: 'National' },
      { date: '2026-04-14', name: 'Ambedkar Jayanti', state: 'National' },
      { date: '2026-05-01', name: 'May Day', state: 'National' },
      { date: '2026-08-15', name: 'Independence Day', state: 'National' },
      { date: '2026-09-16', name: 'Milad-un-Nabi', state: 'National' },
      { date: '2026-10-02', name: 'Gandhi Jayanti', state: 'National' },
      { date: '2026-10-24', name: 'Diwali', state: 'National' },
      { date: '2026-10-25', name: 'Diwali Holiday', state: 'National' },
      { date: '2026-12-25', name: 'Christmas', state: 'National' },
    ];

    for (const holiday of holidays) {
      await client.query(
        `INSERT INTO holidays (holiday_date, holiday_name, state, is_optional)
         VALUES ($1, $2, $3, false)
         ON CONFLICT (holiday_date) DO UPDATE SET holiday_name = $2`,
        [holiday.date, holiday.name, holiday.state]
      );
    }
    console.log(`✓ ${holidays.length} holidays added\n`);

    console.log('='.repeat(50));
    console.log('✨ Database seeding complete!\n');
    console.log('📝 Test Login:');
    console.log(`   Email: ${adminEmail}`);
    console.log(`   Password: ChangeMe@123\n`);
    console.log('Next steps:');
    console.log('1. Verify in Supabase SQL Editor');
    console.log('2. Deploy API to Vercel');
    console.log('3. Test login in Flutter app\n');

  } catch (error) {
    console.error('❌ Seeding failed:', error.message);
    console.error(error.stack);
    process.exit(1);
  } finally {
    client.release();
    await pool.end();
  }
}

seed();
