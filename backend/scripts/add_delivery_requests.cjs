const mysql = require('mysql2/promise');
require('dotenv').config();

(async function main(){
  const pool = mysql.createPool({
    host: process.env.DB_HOST || '192.168.1.94',
    user: process.env.DB_USER || 'root',
    password: process.env.DB_PASSWORD || '',
    database: process.env.DB_NAME || 'yshop_db',
    port: process.env.DB_PORT ? parseInt(process.env.DB_PORT) : 3306,
  });

  try {
    const sql = `CREATE TABLE IF NOT EXISTS delivery_requests (
      id BIGINT AUTO_INCREMENT PRIMARY KEY,
      uid VARCHAR(128) NOT NULL,
      email VARCHAR(255),
      name VARCHAR(255),
      phone VARCHAR(64),
      national_id VARCHAR(64),
      address TEXT,
      status ENUM('Pending','Approved','Rejected') NOT NULL DEFAULT 'Pending',
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      UNIQUE KEY (uid)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;`;

    const [res] = await pool.query(sql);
    console.log('Migration result:', res);
    await pool.end();
    process.exit(0);
  } catch (err) {
    console.error(err);
    try { await pool.end(); } catch(e){}
    process.exit(2);
  }
})();
