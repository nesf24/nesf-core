import 'dotenv/config';
import pool from '../src/db.js';

const staffData = [
  { email: "tashidorjeethongon@gmail.com", phone: "8731978807", name: "Tashi Dorjee Thongon", designation: "Operational Head", department: "Operations", grade: "B" },
  { email: "ligubindiya@gmail.com", phone: "7085696855", name: "Bindiya Ligu", designation: "Sports Psychologist", department: "Sports", grade: "B" },
  { email: "moventanyang@gmail.com", phone: "7005218418", name: "Tanyang Mobin", designation: "Chief Editor", department: "Communications", grade: "B" },
  { email: "dipankarbarman343@gmail.com", phone: "9089276206", name: "Dipankar Barman", designation: "Admin Head", department: "Administration", grade: "B" },
  { email: "bapimandal2468@gmail.com", phone: "7005515996", name: "BAPI MANDAL", designation: "Young Professional", department: "Administration", grade: "C" },
  { email: "karannath2759@gmail.com", phone: "6009222190", name: "Karan Nath", designation: "Young Professional", department: "Sports", grade: "C" },
  { email: "nonyaradhe@gmail.com", phone: "6398580665", name: "Nonya Radhe", designation: "Secretary", department: "Administration", grade: "B" },
  { email: "tanapumin17@gmail.com", phone: "8729979045", name: "Tana Pumin", designation: "Editor", department: "Communications", grade: "B" },
  { email: "adityabaruah00@gmail.com", phone: "6001902629", name: "Aditya Baruah", designation: "Young Professional", department: "Sports", grade: "C" },
  { email: "peterpsych3@gmail.com", phone: "8259802618", name: "YOMLI BAM", designation: "Photographer", department: "Communications", grade: "C" },
  { email: "Onykini53@gmail.com", phone: "8118983390", name: "Ony kino", designation: "Archery Coach", department: "Sports", grade: "B" },
  { email: "anamtadar11@gmail.com", phone: "8074303987", name: "Dr.Tadar Anam (PT)", designation: "Physiotherapist", department: "Sports", grade: "B" },
  { email: "Jaonmichi13@gmail.com", phone: "7005219019", name: "Michi Jaon Tanyang", designation: "Young Professional", department: "Sports", grade: "C" },
  { email: "tagemoka180@gmail.com", phone: "7085164242", name: "Tage sambyo", designation: "Young Professional", department: "Operations", grade: "C" },
];

async function importStaff() {
  try {
    console.log('Starting staff import...');

    for (const staff of staffData) {
      const empCode = `NESF-${String(Math.random()).slice(2, 5).padStart(3, '0')}`;

      const result = await pool.query(
        `INSERT INTO employees (
          emp_code, full_name, email, phone, designation, department, grade, role, is_active
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        ON CONFLICT (email) DO UPDATE SET
          full_name = $2, phone = $4, designation = $5, department = $6, grade = $7
        RETURNING id, full_name, email, role`,
        [empCode, staff.name, staff.email.trim(), staff.phone, staff.designation, staff.department, staff.grade, 'staff', true]
      );

      console.log(`✓ ${result.rows[0].full_name} (${result.rows[0].role})`);
    }

    // Update Biki as Director/Admin
    await pool.query(
      `UPDATE employees SET role = $1, designation = $2 WHERE email = $3`,
      ['director', 'Director & Chief Functionary', 'biki@nesportsfoundation.in']
    );
    console.log('✓ Biki Moni Saikia updated as Director');

    console.log('\n✅ Staff import complete!');
    process.exit(0);
  } catch (err) {
    console.error('❌ Error:', err.message || JSON.stringify(err));
    console.error('Details:', err);
    process.exit(1);
  }
}

importStaff();
