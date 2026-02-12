import pool from '../src/config/database.js';

async function addAdminAcceptedColumn() {
  let connection;
  try {
    connection = await pool.getConnection();
    
    // Check if column already exists
    const [columns] = await connection.execute(`
      SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS 
      WHERE TABLE_NAME = 'returned_products' AND COLUMN_NAME = 'admin_accepted'
    `);
    
    if (columns.length > 0) {
      console.log('✅ admin_accepted column already exists');
      connection.release();
      process.exit(0);
    }
    
    // Add the column
    await connection.execute(`
      ALTER TABLE returned_products 
      ADD COLUMN admin_accepted BOOLEAN DEFAULT FALSE
    `);
    
    console.log('✅ admin_accepted column added successfully');
    
    connection.release();
  } catch (error) {
    console.error('❌ Error:', error.message);
    if (connection) connection.release();
    process.exit(1);
  }
}

addAdminAcceptedColumn().then(() => process.exit(0));
