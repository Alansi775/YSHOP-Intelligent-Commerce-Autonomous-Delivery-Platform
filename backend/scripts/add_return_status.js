import pool from '../src/config/database.js';
import logger from '../src/config/logger.js';

/**
 * Migration: Add 'return' status to orders table ENUM
 * This script adds the 'return' status to the ENUM field
 */

async function addReturnStatus() {
  let connection;
  try {
    connection = await pool.getConnection();
    
    logger.info('Adding "return" status to orders table...');
    
    // Alter the orders table to add 'return' to the status ENUM
    await connection.execute(`
      ALTER TABLE orders 
      MODIFY COLUMN status ENUM('pending', 'confirmed', 'shipped', 'delivered', 'cancelled', 'return') DEFAULT 'pending'
    `);
    
    logger.info('✅ Successfully added "return" status to orders table');
    connection.release();
    process.exit(0);
    
  } catch (error) {
    logger.error('Error adding return status:', error);
    if (connection) connection.release();
    process.exit(1);
  }
}

addReturnStatus();
