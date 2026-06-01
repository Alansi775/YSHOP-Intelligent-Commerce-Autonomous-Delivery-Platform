#!/usr/bin/env node

/**
 * Firebase to MySQL Migration using Firebase REST API
 */

import pool from '../../src/config/database.js';
import logger from '../../src/config/logger.js';
import fetch from 'node-fetch';

const PROJECT_ID = 'home-720ef';
const FIRESTORE_URL = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

// Get Firebase token from CLI
import { execSync } from 'child_process';

function getFirebaseToken() {
  try {
    const token = execSync('firebase auth:login --no-192.168.1.59 --only-show-token 2>/dev/null || echo ""', {
      encoding: 'utf-8',
    }).trim();
    return token;
  } catch (error) {
    return null;
  }
}

// Get ID token using gcloud
function getIdToken() {
  try {
    const token = execSync('gcloud auth print-identity-token', {
      encoding: 'utf-8',
    }).trim();
    return token;
  } catch (error) {
    logger.error('Error getting ID token:', error.message);
    return null;
  }
}

async function fetchFirestoreCollection(collectionName) {
  const token = getIdToken();
  if (!token) {
    throw new Error('Could not get authentication token. Run: gcloud auth login');
  }

  const url = `${FIRESTORE_URL}/${collectionName}`;
  logger.info(`  📡 Fetching from: ${collectionName}`);

  try {
    const response = await fetch(url, {
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
    });

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`API Error: ${response.status} - ${error}`);
    }

    const data = await response.json();
    return data.documents || [];
  } catch (error) {
    logger.error(`Error fetching ${collectionName}:`, error.message);
    throw error;
  }
}

function parseFirestoreDocument(doc) {
  const result = {};
  if (doc.fields) {
    Object.entries(doc.fields).forEach(([key, value]) => {
      if (value.stringValue) result[key] = value.stringValue;
      else if (value.integerValue) result[key] = parseInt(value.integerValue);
      else if (value.doubleValue) result[key] = parseFloat(value.doubleValue);
      else if (value.booleanValue) result[key] = value.booleanValue;
      else if (value.timestampValue) result[key] = new Date(value.timestampValue);
      else if (value.arrayValue) result[key] = value.arrayValue.values || [];
      else result[key] = value;
    });
  }
  return result;
}

async function migrateUsers(users) {
  logger.info('\n Migrating users...');
  let migratedCount = 0;
  let skippedCount = 0;

  for (const doc of users) {
    const userData = parseFirestoreDocument(doc);
    const uid = doc.name.split('/').pop();

    try {
      const connection = await pool.getConnection();

      const [existing] = await connection.execute(
        'SELECT id FROM users WHERE uid = ?',
        [uid]
      );

      if (existing.length === 0) {
        await connection.execute(
          `INSERT INTO users (uid, email, display_name, phone, created_at, updated_at)
           VALUES (?, ?, ?, ?, NOW(), NOW())`,
          [uid, userData.email || '', userData.displayName || '', userData.phone || '']
        );
        migratedCount++;
        logger.info(`   ${userData.email}`);
      } else {
        skippedCount++;
      }

      connection.release();
    } catch (err) {
      logger.error(`  ❌ Error:`, err.message);
    }
  }

  logger.info(` Users: ${migratedCount} added, ${skippedCount} skipped\n`);
  return { migratedCount, skippedCount };
}

async function migrateStores(stores) {
  logger.info('\n Migrating stores...');
  let migratedCount = 0;
  let skippedCount = 0;

  for (const doc of stores) {
    const storeData = parseFirestoreDocument(doc);
    const uid = doc.name.split('/').pop();

    try {
      const connection = await pool.getConnection();

      const [existing] = await connection.execute(
        'SELECT id FROM stores WHERE owner_uid = ?',
        [uid]
      );

      if (existing.length === 0) {
        const [user] = await connection.execute(
          'SELECT id FROM users WHERE uid = ?',
          [uid]
        );

        if (user.length > 0) {
          await connection.execute(
            `INSERT INTO stores (name, description, phone, address, latitude, longitude, icon_url, owner_uid, is_active, created_at, updated_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, true, NOW(), NOW())`,
            [
              storeData.storeName || 'متجر',
              storeData.description || '',
              storeData.phoneNumber || '',
              storeData.address || '',
              parseFloat(storeData.latitude) || 0,
              parseFloat(storeData.longitude) || 0,
              storeData.storeIconUrl || '',
              uid,
            ]
          );
          migratedCount++;
          logger.info(`   ${storeData.storeName}`);
        }
      } else {
        skippedCount++;
      }

      connection.release();
    } catch (err) {
      logger.error(`  ❌ Error:`, err.message);
    }
  }

  logger.info(` Stores: ${migratedCount} added, ${skippedCount} skipped\n`);
  return { migratedCount, skippedCount };
}

async function migrateProducts(products) {
  logger.info('\n Migrating products...');
  let migratedCount = 0;
  let skippedCount = 0;

  for (const doc of products) {
    const productData = parseFirestoreDocument(doc);

    try {
      const connection = await pool.getConnection();

      const storeEmail = productData.storeOwnerEmail || '';
      const [storeResult] = await connection.execute(
        `SELECT stores.id FROM stores
         JOIN users ON stores.owner_uid = users.uid
         WHERE users.email = ?`,
        [storeEmail]
      );

      if (storeResult.length > 0) {
        const storeId = storeResult[0].id;

        const [existing] = await connection.execute(
          'SELECT id FROM products WHERE name = ? AND store_id = ?',
          [productData.name || '', storeId]
        );

        if (existing.length === 0) {
          await connection.execute(
            `INSERT INTO products (name, description, price, store_id, image_url, is_active, created_at, updated_at)
             VALUES (?, ?, ?, ?, ?, ?, NOW(), NOW())`,
            [
              productData.name || 'منتج',
              productData.description || '',
              parseFloat(productData.price) || 0,
              storeId,
              productData.imageUrl || '',
              productData.approved !== false,
            ]
          );
          migratedCount++;
          logger.info(`   ${productData.name}`);
        } else {
          skippedCount++;
        }
      }

      connection.release();
    } catch (err) {
      logger.error(`  ❌ Error:`, err.message);
    }
  }

  logger.info(` Products: ${migratedCount} added, ${skippedCount} skipped\n`);
  return { migratedCount, skippedCount };
}

async function runMigration() {
  try {
    logger.info('\nFirebase → MySQL Migration (REST API)\n');
    logger.info('=====================================\n');

    logger.info('📡 Fetching data from Firebase...\n');
    const users = await fetchFirestoreCollection('users');
    const stores = await fetchFirestoreCollection('storeRequests');
    const products = await fetchFirestoreCollection('products');

    logger.info(`\n  Found: ${users.length} users, ${stores.length} stores, ${products.length} products\n`);

    const results = {
      users: await migrateUsers(users),
      stores: await migrateStores(stores),
      products: await migrateProducts(products),
    };

    logger.info('=====================================');
    logger.info(' MIGRATION COMPLETE!\n');
    logger.info('Summary:');
    logger.info(`  👥 Users: ${results.users.migratedCount} added`);
    logger.info(`   Stores: ${results.stores.migratedCount} added`);
    logger.info(`   Products: ${results.products.migratedCount} added`);
    logger.info('=====================================\n');

    process.exit(0);
  } catch (error) {
    logger.error('\n❌ Migration failed:', error.message);
    logger.info('\nTroubleshooting:');
    logger.info('1. Make sure gcloud is authenticated:');
    logger.info('   gcloud auth login');
    logger.info('2. Set the correct project:');
    logger.info('   gcloud config set project home-720ef');
    logger.info('3. Run migration again');
    process.exit(1);
  }
}

// Run
runMigration();
