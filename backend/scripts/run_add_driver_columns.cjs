const mysql = require('mysql2/promise');
require('dotenv').config();

(async function main(){
  const pool = mysql.createPool({
    host: process.env.DB_HOST || '192.168.1.94',
    user: process.env.DB_USER || 'root',
    password: process.env.DB_PASSWORD || '',
    database: process.env.DB_NAME || 'yshop_db',
    port: process.env.DB_PORT ? parseInt(process.env.DB_PORT) : 3306,
    waitForConnections: true,
    connectionLimit: 5,
  });

  const connection = await pool.getConnection();
  try {
    const [driverIdRows] = await connection.execute(
      `SELECT COUNT(*) as cnt FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orders' AND COLUMN_NAME = 'driver_id'`
    );
    const driverIdExists = driverIdRows[0] && driverIdRows[0].cnt > 0;

    if (!driverIdExists) {
      console.log('Adding column orders.driver_id');
      await connection.execute(`ALTER TABLE orders ADD COLUMN driver_id VARCHAR(255) NULL`);
    } else {
      console.log('orders.driver_id already exists');
    }

    const [driverLocRows] = await connection.execute(
      `SELECT COUNT(*) as cnt FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orders' AND COLUMN_NAME = 'driver_location'`
    );
    const driverLocExists = driverLocRows[0] && driverLocRows[0].cnt > 0;

    if (!driverLocExists) {
      console.log('Adding column orders.driver_location');
      await connection.execute(`ALTER TABLE orders ADD COLUMN driver_location TEXT NULL`);
    } else {
      console.log('orders.driver_location already exists');
    }

    console.log('Migration completed');
    await connection.release();
    await pool.end();
    process.exit(0);
  } catch (err) {
    console.error('Migration failed:', err);
    try { await connection.release(); } catch(e){}
    try { await pool.end(); } catch(e){}
    process.exit(2);
  }
})();
