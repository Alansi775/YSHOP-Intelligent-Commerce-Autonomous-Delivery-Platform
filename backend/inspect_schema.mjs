import pool from './src/config/database.js';

(async () => {
  try {
    const connection = await pool.getConnection();
    console.log('\n=== USERS TABLE COLUMNS ===');
    const [columns] = await connection.query('DESCRIBE users');
    console.table(columns);
    connection.release();
    process.exit(0);
  } catch (error) {
    console.error('ERROR:', error.message);
    process.exit(1);
  }
})();
