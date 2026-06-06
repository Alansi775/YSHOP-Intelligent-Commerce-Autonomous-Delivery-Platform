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

  try {
    const [p] = await pool.query("SHOW COLUMNS FROM `orders` LIKE 'payment_method'");
    const [d] = await pool.query("SHOW COLUMNS FROM `orders` LIKE 'delivery_option'");
    console.log('payment_method exists:', p.length>0);
    console.log('delivery_option exists:', d.length>0);

    if (p.length === 0 || d.length === 0) {
      const alters = [];
      if (p.length === 0) alters.push("ADD COLUMN `payment_method` VARCHAR(128) DEFAULT NULL");
      if (d.length === 0) alters.push("ADD COLUMN `delivery_option` VARCHAR(128) DEFAULT NULL");

      const sql = 'ALTER TABLE `orders` ' + alters.join(', ');
      console.log('Running:', sql);
      const [res] = await pool.query(sql);
      console.log('Alter result:', res);
    } else {
      console.log('No changes required.');
    }

    await pool.end();
    process.exit(0);
  } catch (err) {
    console.error(err);
    try { await pool.end(); } catch(e){}
    process.exit(2);
  }
})();
