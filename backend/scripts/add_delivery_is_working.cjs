#!/usr/bin/env node
// Adds is_working column to delivery_requests if missing
const mysql = require('mysql2/promise');

(async function(){
  try {
    const host = process.env.DB_HOST || '192.168.1.94';
    const user = process.env.DB_USER || 'root';
    const password = process.env.DB_PASSWORD || '';
    const database = process.env.DB_NAME || 'yshop_db';

    const conn = await mysql.createConnection({ host, user, password, database });
    console.log('Connected, checking column...');
    const [rows] = await conn.execute(
      `SELECT COUNT(*) as cnt FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = ? AND TABLE_NAME = 'delivery_requests' AND COLUMN_NAME = 'is_working'`,
      [database]
    );
    const exists = rows && rows[0] && (rows[0].cnt || rows[0].CNT || rows[0].Cnt);
    if (!exists) {
      await conn.execute(`ALTER TABLE delivery_requests ADD COLUMN is_working TINYINT(1) DEFAULT 0`);
      console.log('Column is_working added.');
    } else {
      console.log('Column is_working already exists.');
    }
    await conn.end();
    process.exit(0);
  } catch (e) {
    console.error('Migration failed', e);
    process.exit(1);
  }
})();
