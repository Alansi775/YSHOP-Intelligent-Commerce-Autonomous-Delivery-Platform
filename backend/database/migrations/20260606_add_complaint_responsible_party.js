import pool from '../../src/config/database.js';

async function up() {
  const [cols] = await pool.execute(`SHOW COLUMNS FROM order_complaints LIKE 'responsible_party'`);
  if (cols.length === 0) {
    await pool.execute(`ALTER TABLE order_complaints ADD COLUMN responsible_party VARCHAR(50) DEFAULT NULL`);
  }
  console.log('✅ Added responsible_party to order_complaints');
}

async function down() {
  await pool.execute(`ALTER TABLE order_complaints DROP COLUMN IF EXISTS responsible_party`);
}

up().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
