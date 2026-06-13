import mysql from 'mysql2/promise';
import bcrypt from 'bcryptjs';

async function addAdmin() {
  const connection = await mysql.createConnection({
    host: '127.0.0.1',
    user: 'root',
    password: 'root',
    database: 'yshop_db'
  });

  try {
    const password = 'Alansi77';
    const passwordHash = await bcrypt.hash(password, 10);

    const [existing] = await connection.execute(
      'SELECT id FROM yshopadmins WHERE email = ?',
      ['mohamed@yshop.com']
    );

    if (existing.length > 0) {
      console.log('❌ Admin already exists');
      await connection.end();
      process.exit(0);
    }

    await connection.execute(
      `INSERT INTO yshopadmins (email, password_hash, first_name, last_name, role, status, is_banned)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      ['mohamed@yshop.com', passwordHash, 'Mohammed', 'Alansi', 'superadmin', 'active', 0]
    );

    console.log('\n Admin added successfully!\n');
    console.log('📧 Email: mohamed@yshop.com');
    console.log('🔑 Password: Alansi77');
    console.log('👤 Name: Mohammed Alansi');
    console.log('⭐ Role: superadmin\n');

    await connection.end();
    process.exit(0);
  } catch (error) {
    console.error('❌ Error:', error.message);
    await connection.end();
    process.exit(1);
  }
}

addAdmin();
