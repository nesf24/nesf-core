import pkg from 'pg';
const { Client } = pkg;

const connectionString = process.env.DATABASE_URL ||
  'postgres://postgres:NEsports%40%232026@mixbtfnjdzmfbctkxnwk.supabase.co:6543/postgres?sslmode=require';

const staffData = [
  { emp: 'NESF-001', name: 'Tashi Dorjee Thongon', email: 'tashidorjeethongon@gmail.com', phone: '8731978807', desig: 'Operational Head', dept: 'Operations', grade: 'B' },
  { emp: 'NESF-002', name: 'Bindiya Ligu', email: 'ligubindiya@gmail.com', phone: '7085696855', desig: 'Sports Psychologist', dept: 'Sports', grade: 'B' },
  { emp: 'NESF-003', name: 'Tanyang Mobin', email: 'moventanyang@gmail.com', phone: '7005218418', desig: 'Chief Editor', dept: 'Communications', grade: 'B' },
  { emp: 'NESF-004', name: 'Dipankar Barman', email: 'dipankarbarman343@gmail.com', phone: '9089276206', desig: 'Admin Head', dept: 'Administration', grade: 'B' },
  { emp: 'NESF-005', name: 'BAPI MANDAL', email: 'bapimandal2468@gmail.com', phone: '7005515996', desig: 'Young Professional', dept: 'Administration', grade: 'C' },
  { emp: 'NESF-006', name: 'Karan Nath', email: 'karannath2759@gmail.com', phone: '6009222190', desig: 'Young Professional', dept: 'Sports', grade: 'C' },
  { emp: 'NESF-007', name: 'Nonya Radhe', email: 'nonyaradhe@gmail.com', phone: '6398580665', desig: 'Secretary', dept: 'Administration', grade: 'B' },
  { emp: 'NESF-008', name: 'Tana Pumin', email: 'tanapumin17@gmail.com', phone: '8729979045', desig: 'Editor', dept: 'Communications', grade: 'B' },
  { emp: 'NESF-009', name: 'Aditya Baruah', email: 'adityabaruah00@gmail.com', phone: '6001902629', desig: 'Young Professional', dept: 'Sports', grade: 'C' },
  { emp: 'NESF-010', name: 'YOMLI BAM', email: 'peterpsych3@gmail.com', phone: '8259802618', desig: 'Photographer', dept: 'Communications', grade: 'C' },
  { emp: 'NESF-011', name: 'Ony kino', email: 'Onykini53@gmail.com', phone: '8118983390', desig: 'Archery Coach', dept: 'Sports', grade: 'B' },
  { emp: 'NESF-012', name: 'Dr.Tadar Anam (PT)', email: 'anamtadar11@gmail.com', phone: '8074303987', desig: 'Physiotherapist', dept: 'Sports', grade: 'B' },
  { emp: 'NESF-013', name: 'Michi Jaon Tanyang', email: 'Jaonmichi13@gmail.com', phone: '7005219019', desig: 'Young Professional', dept: 'Sports', grade: 'C' },
  { emp: 'NESF-014', name: 'Tage sambyo', email: 'tagemoka180@gmail.com', phone: '7085164242', desig: 'Young Professional', dept: 'Operations', grade: 'C' },
];

async function importStaff() {
  const client = new Client({ connectionString, ssl: { rejectUnauthorized: false } });

  try {
    await client.connect();
    console.log('Connected to Supabase!');

    for (const s of staffData) {
      await client.query(
        `INSERT INTO employees (emp_code, full_name, email, phone, designation, department, grade, role, is_active)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
         ON CONFLICT (email) DO UPDATE SET full_name = $2, phone = $4, designation = $5, department = $6, grade = $7`,
        [s.emp, s.name, s.email.trim(), s.phone, s.desig, s.dept, s.grade, 'staff', true]
      );
      console.log(`✓ ${s.name}`);
    }

    await client.query(
      `UPDATE employees SET role = $1, designation = $2 WHERE email = $3`,
      ['director', 'Director & Chief Functionary', 'biki@nesportsfoundation.in']
    );
    console.log('✓ Biki set as Director');

    const result = await client.query('SELECT COUNT(*) as total FROM employees');
    console.log(`\n✅ Total staff: ${result.rows[0].total}`);

  } catch (err) {
    console.error('❌ Error:', err.message);
  } finally {
    await client.end();
  }
}

importStaff();
