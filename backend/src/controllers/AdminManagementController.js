import pool from '../config/database.js';
import bcrypt from 'bcryptjs';

export async function listAdmins(req, res, next) {
  try {
    const [rows] = await pool.execute('SELECT id, email, first_name, last_name, role, created_at FROM yshopadmins ORDER BY id DESC');
    return res.json({ success: true, data: rows });
  } catch (err) {
    next(err);
  }
}

export async function createAdmin(req, res, next) {
  const { email, password, first_name, last_name, role } = req.body || {};
  if (!email || !password || !role) return res.status(400).json({ success: false, message: 'Missing fields' });
  try {
    const hash = await bcrypt.hash(password, 10);
    const [result] = await pool.execute('INSERT INTO yshopadmins (email, password_hash, first_name, last_name, role) VALUES (?, ?, ?, ?, ?)', [email, hash, first_name || null, last_name || null, role]);
    const id = result.insertId;
    return res.json({ success: true, data: { id, email, first_name, last_name, role } });
  } catch (err) {
    if (err && err.code === 'ER_DUP_ENTRY') return res.status(409).json({ success: false, message: 'Admin already exists' });
    next(err);
  }
}

export async function listUsersForAdmin(req, res, next) {
  const adminId = req.params.adminId;
  try {
    const [rows] = await pool.execute('SELECT id, email, first_name, last_name, role, created_at FROM yshopusers WHERE admin_id = ?', [adminId]);
    return res.json({ success: true, data: rows });
  } catch (err) { next(err); }
}

export async function createUserUnderAdmin(req, res, next) {
  const adminId = req.params.adminId;
  const { first_name, last_name, password } = req.body || {};
  if (!first_name || !last_name || !password) return res.status(400).json({ success: false, message: 'Missing fields' });
  try {
    // generate email first.last@yshop.com (lowercase, dots)
    const local = `${first_name.trim().toLowerCase()}.${last_name.trim().toLowerCase()}`.replace(/\s+/g, '.');
    let email = `${local}@yshop.com`;
    // ensure uniqueness
    let suffix = 1;
    while (true) {
      const [rows] = await pool.execute('SELECT id FROM yshopusers WHERE email = ?', [email]);
      if (rows.length === 0) break;
      email = `${local}${suffix}@yshop.com`;
      suffix++;
    }

    const hash = await bcrypt.hash(password, 10);
    const [result] = await pool.execute('INSERT INTO yshopusers (email, password_hash, first_name, last_name, admin_id, role) VALUES (?, ?, ?, ?, ?, ?)', [email, hash, first_name, last_name, adminId, 'user']);
    const id = result.insertId;
    return res.json({ success: true, data: { id, email, first_name, last_name } });
  } catch (err) { next(err); }
}

export async function updateAdminStatus(req, res, next) {
  try {
    const targetId = req.params.adminId;
    const { status, is_banned } = req.body || {};

    const caller = req.admin;
    if (!caller || caller.role !== 'superadmin') return res.status(403).json({ success: false, message: 'Forbidden: superadmin required' });

    const [rows] = await pool.execute('SELECT id, role FROM yshopadmins WHERE id = ?', [targetId]);
    if (!rows || rows.length === 0) return res.status(404).json({ success: false, message: 'Admin not found' });

    if (status !== undefined) {
      await pool.execute('UPDATE yshopadmins SET status = ? WHERE id = ?', [status, targetId]);
    } else if (is_banned !== undefined) {
      const v = is_banned ? 1 : 0;
      await pool.execute('UPDATE yshopadmins SET is_banned = ? WHERE id = ?', [v, targetId]);
    } else {
      return res.status(400).json({ success: false, message: 'Missing status or is_banned in body' });
    }

    return res.json({ success: true, data: { id: targetId } });
  } catch (err) { next(err); }
}

export async function deleteAdmin(req, res, next) {
  try {
    const targetId = req.params.adminId;
    const caller = req.admin;
    if (!caller || caller.role !== 'superadmin') return res.status(403).json({ success: false, message: 'Forbidden: superadmin required' });
    if (String(caller.id) === String(targetId)) return res.status(400).json({ success: false, message: 'Cannot delete yourself' });

    const [rows] = await pool.execute('SELECT id FROM yshopadmins WHERE id = ?', [targetId]);
    if (!rows || rows.length === 0) return res.status(404).json({ success: false, message: 'Admin not found' });

    await pool.execute('DELETE FROM yshopadmins WHERE id = ?', [targetId]);
    return res.json({ success: true, data: { id: targetId } });
  } catch (err) { next(err); }
}

// ============================================
// STORE APPROVAL MANAGEMENT
// ============================================

export async function getPendingStores(req, res, next) {
  try {
    const connection = await pool.getConnection();
    const [stores] = await connection.execute(
      `SELECT id, uid, email, name, owner_name, phone, address, status, email_verified, created_at 
       FROM stores 
       WHERE status = 'pending' OR status = 'rejected'
       ORDER BY created_at DESC`
    );
    connection.release();

    return res.json({ success: true, data: stores });
  } catch (err) {
    next(err);
  }
}

export async function approveStore(req, res, next) {
  try {
    const { storeId } = req.params;
    console.log(`🟢 [approveStore] Admin is approving store ID: ${storeId}`);
    
    // Verify admin authorization
    if (!req.admin || req.admin.role !== 'superadmin') {
      console.log(`❌ [approveStore] Unauthorized - role: ${req.admin?.role}`);
      return res.status(403).json({ success: false, message: 'Unauthorized: Admin access required' });
    }

    const connection = await pool.getConnection();

    // Check store exists BEFORE update
    const [storesBefore] = await connection.execute(
      'SELECT id, email, name, status FROM stores WHERE id = ?',
      [storeId]
    );

    if (storesBefore.length === 0) {
      connection.release();
      console.log(`❌ [approveStore] Store not found: ${storeId}`);
      return res.status(404).json({ success: false, message: 'Store not found' });
    }

    const storeBefore = storesBefore[0];
    console.log(`  Before: status="${storeBefore.status}"`);

    // Update store status to approved
    const [updateResult] = await connection.execute(
      'UPDATE stores SET status = ? WHERE id = ?',
      ['approved', storeId]
    );
    console.log(`  Update affected rows: ${updateResult.affectedRows}`);

    // Check status AFTER update
    const [storesAfter] = await connection.execute(
      'SELECT id, email, name, status FROM stores WHERE id = ?',
      [storeId]
    );
    
    if (storesAfter.length > 0) {
      console.log(`  After: status="${storesAfter[0].status}"`);
    }

    connection.release();

    console.log(` [approveStore] Store ${storeBefore.name} (${storeBefore.email}) approved`);

    return res.json({
      success: true,
      message: `Store "${storeBefore.name}" has been approved`,
      data: { id: storeId, status: 'approved' },
    });
  } catch (err) {
    console.error(`❌ [approveStore] Error:`, err);
    next(err);
  }
}

export async function rejectStore(req, res, next) {
  try {
    const { storeId } = req.params;
    const { reason } = req.body || {};
    console.log(` [rejectStore] Admin is rejecting store ID: ${storeId}, reason: ${reason || 'Not specified'}`);

    // Verify admin authorization
    if (!req.admin || req.admin.role !== 'superadmin') {
      console.log(`❌ [rejectStore] Unauthorized - role: ${req.admin?.role}`);
      return res.status(403).json({ success: false, message: 'Unauthorized: Admin access required' });
    }

    const connection = await pool.getConnection();

    // Check store exists BEFORE update
    const [storesBefore] = await connection.execute(
      'SELECT id, email, name, status FROM stores WHERE id = ?',
      [storeId]
    );

    if (storesBefore.length === 0) {
      connection.release();
      console.log(`❌ [rejectStore] Store not found: ${storeId}`);
      return res.status(404).json({ success: false, message: 'Store not found' });
    }

    const storeBefore = storesBefore[0];
    console.log(`  Before: status="${storeBefore.status}"`);

    // Update store status to rejected
    const [updateResult] = await connection.execute(
      'UPDATE stores SET status = ? WHERE id = ?',
      ['rejected', storeId]
    );
    console.log(`  Update affected rows: ${updateResult.affectedRows}`);

    // Check status AFTER update
    const [storesAfter] = await connection.execute(
      'SELECT id, email, name, status FROM stores WHERE id = ?',
      [storeId]
    );
    
    if (storesAfter.length > 0) {
      console.log(`  After: status="${storesAfter[0].status}"`);
    }

    connection.release();

    console.log(` [rejectStore] Store ${storeBefore.name} (${storeBefore.email}) rejected`);

    return res.json({
      success: true,
      message: `Store "${storeBefore.name}" has been rejected`,
      data: { id: storeId, status: 'rejected' },
    });
  } catch (err) {
    console.error(`❌ [rejectStore] Error:`, err);
    next(err);
  }
}

export async function banStore(req, res, next) {
  try {
    const { storeId } = req.params;
    const { reason } = req.body || {};

    // Verify admin authorization
    if (!req.admin || req.admin.role !== 'superadmin') {
      return res.status(403).json({ success: false, message: 'Unauthorized: Admin access required' });
    }

    const connection = await pool.getConnection();

    // Check store exists
    const [stores] = await connection.execute(
      'SELECT id, email, name FROM stores WHERE id = ?',
      [storeId]
    );

    if (stores.length === 0) {
      connection.release();
      return res.status(404).json({ success: false, message: 'Store not found' });
    }

    const store = stores[0];

    // Update store status to banned
    await connection.execute(
      'UPDATE stores SET status = ? WHERE id = ?',
      ['banned', storeId]
    );

    connection.release();

    // TODO: Send ban notification email
    console.log(`🚫 Store ${store.name} (${store.email}) banned. Reason: ${reason || 'Not specified'}`);

    return res.json({
      success: true,
      message: `Store "${store.name}" has been banned`,
      data: { id: storeId, status: 'banned' },
    });
  } catch (err) {
    next(err);
  }
}

export async function getApprovedStores(req, res, next) {
  try {
    const connection = await pool.getConnection();
    const [stores] = await connection.execute(
      `SELECT id, uid, email, name, owner_name, phone, address, status, latitude, longitude, created_at 
       FROM stores 
       WHERE status = 'approved'
       ORDER BY created_at DESC`
    );
    connection.release();

    return res.json({ success: true, data: stores });
  } catch (err) {
    next(err);
  }
}

// 🔥 NEW: Get ALL stores with REAL status from database (critical fix)
// This correctly reads the status column, not approval timestamps
export async function getAllStoresAdmin(req, res, next) {
  try {
    console.log('🔍 [getAllStoresAdmin] Fetching all stores from database...');
    
    // 🔥 CRITICAL: Prevent all caching levels
    res.set('Cache-Control', 'no-cache, no-store, must-revalidate, max-age=0');
    res.set('Pragma', 'no-cache');
    res.set('Expires', '0');
    
    const connection = await pool.getConnection();
    const [stores] = await connection.execute(
      `SELECT SQL_NO_CACHE
        id, 
        uid, 
        email, 
        name, 
        owner_name, 
        phone, 
        address, 
        status,
        latitude, 
        longitude, 
        created_at 
       FROM stores 
       ORDER BY created_at DESC`
    );
    connection.release();

    console.log(`🔍 [getAllStoresAdmin] Found ${stores.length} stores:`);
    for (const store of stores) {
      console.log(`  - ${store.name}: status="${store.status}"`);
    }

    return res.json({ success: true, data: stores });
  } catch (err) {
    console.error('❌ [getAllStoresAdmin] Error:', err);
    next(err);
  }
}

export default { 
  listAdmins, 
  createAdmin, 
  listUsersForAdmin, 
  createUserUnderAdmin,
  getPendingStores,
  approveStore,
  rejectStore,
  banStore,
  getApprovedStores,
  getAllStoresAdmin,
  getPendingDrivers,
  approveDriver,
  rejectDriver,
  banDriver,
  getApprovedDrivers,
};

// ============================================
// DELIVERY DRIVER APPROVAL MANAGEMENT
// ============================================

export async function getPendingDrivers(req, res, next) {
  try {
    console.log('[getPendingDrivers] req.admin:', req.admin);
    const connection = await pool.getConnection();
    const [drivers] = await connection.execute(
      `SELECT id, uid, email, name, phone, national_id, address, status, latitude, longitude, created_at 
       FROM delivery_requests 
       WHERE status = 'Pending' OR status = 'Rejected'
       ORDER BY created_at DESC`
    );
    connection.release();
    console.log(`[getPendingDrivers] Found ${drivers.length} drivers`);

    res.set('Cache-Control', 'no-cache, no-store, must-revalidate, max-age=0');
    res.set('Pragma', 'no-cache');
    res.set('Expires', '0');
    return res.json({ success: true, data: drivers });
  } catch (err) {
    next(err);
  }
}

export async function approveDriver(req, res, next) {
  try {
    const { driverId } = req.params;
    
    // Verify admin authorization
    if (!req.admin || req.admin.role !== 'superadmin') {
      return res.status(403).json({ success: false, message: 'Unauthorized: Admin access required' });
    }

    const connection = await pool.getConnection();

    // Check driver exists
    const [drivers] = await connection.execute(
      'SELECT id, email, name, status FROM delivery_requests WHERE id = ?',
      [driverId]
    );

    if (drivers.length === 0) {
      connection.release();
      return res.status(404).json({ success: false, message: 'Driver not found' });
    }

    const driver = drivers[0];

    // Update driver status to approved
    await connection.execute(
      'UPDATE delivery_requests SET status = ? WHERE id = ?',
      ['Approved', driverId]
    );

    connection.release();

    // TODO: Send approval email to driver
    console.log(` Driver ${driver.name} (${driver.email}) approved by admin`);

    return res.json({
      success: true,
      message: `Driver "${driver.name}" has been approved`,
      data: { id: driverId, status: 'Approved' },
    });
  } catch (err) {
    next(err);
  }
}

export async function rejectDriver(req, res, next) {
  try {
    const { driverId } = req.params;
    const { reason } = req.body || {};

    // Verify admin authorization
    if (!req.admin || req.admin.role !== 'superadmin') {
      return res.status(403).json({ success: false, message: 'Unauthorized: Admin access required' });
    }

    const connection = await pool.getConnection();

    // Check driver exists
    const [drivers] = await connection.execute(
      'SELECT id, email, name, status FROM delivery_requests WHERE id = ?',
      [driverId]
    );

    if (drivers.length === 0) {
      connection.release();
      return res.status(404).json({ success: false, message: 'Driver not found' });
    }

    const driver = drivers[0];

    // Update driver status to rejected
    await connection.execute(
      'UPDATE delivery_requests SET status = ? WHERE id = ?',
      ['Rejected', driverId]
    );

    connection.release();

    // TODO: Send rejection email to driver with reason
    console.log(`❌ Driver ${driver.name} (${driver.email}) rejected. Reason: ${reason || 'Not specified'}`);

    return res.json({
      success: true,
      message: `Driver "${driver.name}" has been rejected`,
      data: { id: driverId, status: 'Rejected' },
    });
  } catch (err) {
    next(err);
  }
}

export async function banDriver(req, res, next) {
  try {
    const { driverId } = req.params;
    const { reason } = req.body || {};

    // Verify admin authorization
    if (!req.admin || req.admin.role !== 'superadmin') {
      return res.status(403).json({ success: false, message: 'Unauthorized: Admin access required' });
    }

    const connection = await pool.getConnection();

    // Check driver exists
    const [drivers] = await connection.execute(
      'SELECT id, email, name FROM delivery_requests WHERE id = ?',
      [driverId]
    );

    if (drivers.length === 0) {
      connection.release();
      return res.status(404).json({ success: false, message: 'Driver not found' });
    }

    const driver = drivers[0];

    // Update driver status to banned
    await connection.execute(
      'UPDATE delivery_requests SET status = ? WHERE id = ?',
      ['banned', driverId]
    );

    connection.release();

    // TODO: Send ban notification email
    console.log(`🚫 Driver ${driver.name} (${driver.email}) banned. Reason: ${reason || 'Not specified'}`);

    return res.json({
      success: true,
      message: `Driver "${driver.name}" has been banned`,
      data: { id: driverId, status: 'banned' },
    });
  } catch (err) {
    next(err);
  }
}

export async function getApprovedDrivers(req, res, next) {
  try {
    const connection = await pool.getConnection();
    const [drivers] = await connection.execute(
      `SELECT id, uid, email, name, phone, national_id, address, latitude, longitude, created_at 
       FROM delivery_requests 
       WHERE status = 'Approved'
       ORDER BY created_at DESC`
    );
    connection.release();

    return res.json({ success: true, data: drivers });
  } catch (err) {
    next(err);
  }
}

export async function getActiveDrivers(req, res, next) {
  try {
    console.log('[getActiveDrivers] req.admin:', req.admin);
    const connection = await pool.getConnection();
    const [drivers] = await connection.execute(
      `SELECT id, uid, email, name, phone, national_id, address, latitude, longitude, is_working, created_at 
       FROM delivery_requests 
       WHERE status = 'Approved' AND is_working = 1
       ORDER BY updated_at DESC`
    );
    connection.release();
    console.log(`[getActiveDrivers] Found ${drivers.length} active drivers`);

    res.set('Cache-Control', 'no-cache, no-store, must-revalidate, max-age=0');
    res.set('Pragma', 'no-cache');
    res.set('Expires', '0');
    return res.json({ success: true, data: drivers });
  } catch (err) {
    next(err);
  }
}
