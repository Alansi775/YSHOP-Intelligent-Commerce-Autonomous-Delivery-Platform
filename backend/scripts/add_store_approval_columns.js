/**
 * Migration Script: Add store approval system columns
 * This script adds the necessary columns to the stores table for the approval system
 */

import mysql2 from 'mysql2/promise';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

dotenv.config({ path: path.join(__dirname, '../.env') });

async function main() {
  const connection = await mysql2.createConnection({
    host: process.env.DB_HOST || '192.168.1.59',
    user: process.env.DB_USER || 'root',
    password: process.env.DB_PASSWORD || '',
    database: process.env.DB_NAME || 'yshop',
    port: process.env.DB_PORT || 3306,
  });

  try {
    console.log(' Checking stores table structure...\n');

    // Check if columns exist
    const [columns] = await connection.execute(
      `SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS 
       WHERE TABLE_SCHEMA = ? AND TABLE_NAME = 'stores'`,
      [process.env.DB_NAME || 'yshop']
    );

    const columnNames = columns.map(col => col.COLUMN_NAME);
    console.log('📋 Existing columns in stores table:', columnNames);

    // Add status column if not exists
    if (!columnNames.includes('status')) {
      console.log('\n➕ Adding status column...');
      await connection.execute(
        `ALTER TABLE stores ADD COLUMN status VARCHAR(20) DEFAULT 'pending' 
         COMMENT 'pending, approved, rejected, banned'`
      );
      console.log(' status column added');
    } else {
      console.log('\n✓ status column already exists');
    }

    // Add email_verified column if not exists
    if (!columnNames.includes('email_verified')) {
      console.log('➕ Adding email_verified column...');
      await connection.execute(
        `ALTER TABLE stores ADD COLUMN email_verified TINYINT DEFAULT 0`
      );
      console.log(' email_verified column added');
    } else {
      console.log('✓ email_verified column already exists');
    }

    // Add verification_token column if not exists
    if (!columnNames.includes('verification_token')) {
      console.log('➕ Adding verification_token column...');
      await connection.execute(
        `ALTER TABLE stores ADD COLUMN verification_token VARCHAR(255) NULL`
      );
      console.log(' verification_token column added');
    } else {
      console.log('✓ verification_token column already exists');
    }

    // Add verification_token_expires column if not exists
    if (!columnNames.includes('verification_token_expires')) {
      console.log('➕ Adding verification_token_expires column...');
      await connection.execute(
        `ALTER TABLE stores ADD COLUMN verification_token_expires DATETIME NULL`
      );
      console.log(' verification_token_expires column added');
    } else {
      console.log('✓ verification_token_expires column already exists');
    }

    // Add password_hash column if not exists
    if (!columnNames.includes('password_hash')) {
      console.log('➕ Adding password_hash column...');
      await connection.execute(
        `ALTER TABLE stores ADD COLUMN password_hash VARCHAR(255) NULL`
      );
      console.log(' password_hash column added');
    } else {
      console.log('✓ password_hash column already exists');
    }

    // Add owner_name column if not exists (for merchant name)
    if (!columnNames.includes('owner_name')) {
      console.log('➕ Adding owner_name column...');
      await connection.execute(
        `ALTER TABLE stores ADD COLUMN owner_name VARCHAR(255) NULL`
      );
      console.log(' owner_name column added');
    } else {
      console.log('✓ owner_name column already exists');
    }

    // Add uid column if not exists
    if (!columnNames.includes('uid')) {
      console.log('➕ Adding uid column...');
      await connection.execute(
        `ALTER TABLE stores ADD COLUMN uid VARCHAR(255) UNIQUE NULL`
      );
      console.log(' uid column added');
    } else {
      console.log('✓ uid column already exists');
    }

    console.log('\n All store approval columns are in place!');
    process.exit(0);
  } catch (error) {
    console.error('❌ Error during migration:', error);
    process.exit(1);
  } finally {
    await connection.end();
  }
}

main();
