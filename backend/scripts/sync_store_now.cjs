// One-off script: read a storeRequests doc from Firestore and upsert into MySQL
// Usage: node backend/scripts/sync_store_now.cjs <docId>

const admin = require('firebase-admin');
const mysql = require('mysql2/promise');
const path = require('path');
require('dotenv').config();

const serviceAccountPath = path.resolve(__dirname, '../home-720ef-firebase-adminsdk-8yjvx-4619a2dce7.json');
const serviceAccount = require(serviceAccountPath);

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const firestore = admin.firestore();

async function main() {
  const docId = process.argv[2];
  if (!docId) {
    console.error('Usage: node sync_store_now.cjs <docId>');
    process.exit(1);
  }

  const pool = mysql.createPool({
    host: process.env.DB_HOST || '192.168.1.59',
    user: process.env.DB_USER || 'root',
    password: process.env.DB_PASSWORD || '',
    database: process.env.DB_NAME || 'yshop_db',
    waitForConnections: true,
    connectionLimit: 5,
  });

  try {
    const docRef = firestore.collection('storeRequests').doc(docId);
    const snap = await docRef.get();
    if (!snap.exists) {
      console.error('No such storeRequests doc:', docId);
      process.exit(1);
    }
    const data = snap.data();
    const ownerUid = data.ownerUid || docId;

    let emailVerified = false;
    try {
      const fbUser = await admin.auth().getUser(ownerUid);
      emailVerified = !!(fbUser && fbUser.emailVerified);
      console.log('Firebase user emailVerified =', emailVerified);
    } catch (e) {
      console.warn('Could not fetch Firebase user:', e.message);
    }

    const isActive = data.status === 'Approved' && emailVerified ? 1 : 0;

    const [res] = await pool.query(
      `INSERT INTO stores (owner_uid, name, store_type, phone, address, status, icon_url, description, email)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         name = VALUES(name),
         store_type = VALUES(store_type),
         phone = VALUES(phone),
         address = VALUES(address),
         status = VALUES(status),
         icon_url = VALUES(icon_url),
         description = VALUES(description),
         email = VALUES(email)`,
      [
        ownerUid,
        data.storeName || '',
        data.storeType || '',
        data.phone || '',
        data.address || '',
        data.status || 'Pending',
        data.iconUrl || '',
        data.description || '',
        data.email || '',
      ]
    );

    console.log('Upsert result:', res && res.affectedRows);
    try { await docRef.update({ syncedToMySQL: true }); } catch(e) {}
    console.log('Done');
    process.exit(0);
  } catch (err) {
    console.error('Error:', err.message);
    process.exit(2);
  }
}

main();
