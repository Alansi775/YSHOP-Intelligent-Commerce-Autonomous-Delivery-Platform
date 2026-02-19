import pool from '../src/config/database.js';

/**
 * ✅ Migration: Add display_order column to categories table
 * 
 * هذا السكريبت يضيف حقل display_order إلى جدول categories
 * الحقل سيحتفظ برقم ترتيب الفئة (1, 2, 3, إلخ)
 */

async function addDisplayOrderColumn() {
  const connection = await pool.getConnection();
  
  try {
    console.log(' جاري إضافة حقل display_order إلى جدول categories...');
    
    // تحقق من وجود الحقل
    const [columns] = await connection.query(`
      SELECT COLUMN_NAME 
      FROM INFORMATION_SCHEMA.COLUMNS 
      WHERE TABLE_NAME = 'categories' AND COLUMN_NAME = 'display_order'
    `);
    
    if (columns.length > 0) {
      console.log('⚠️  الحقل display_order موجود بالفعل');
      return;
    }
    
    // أضف الحقل
    await connection.query(`
      ALTER TABLE categories 
      ADD COLUMN display_order INT DEFAULT 0 AFTER icon
    `);
    
    console.log('✅ تم إضافة حقل display_order بنجاح');
    
    // تحديث الترتيب لكل فئة بناءً على وقت الإنشاء
    const [categories] = await connection.query(`
      SELECT id, store_id FROM categories ORDER BY created_at ASC
    `);
    
    // للمتجر الواحد، سيتم ترقيم الفئات من 1 إلى n
    const storeOrders = {};
    
    for (const category of categories) {
      const storeId = category.store_id;
      if (!storeOrders[storeId]) {
        storeOrders[storeId] = 0;
      }
      storeOrders[storeId]++;
      
      await connection.query(
        'UPDATE categories SET display_order = ? WHERE id = ?',
        [storeOrders[storeId], category.id]
      );
    }
    
    console.log('✅ تم تحديث ترتيب جميع الفئات بنجاح');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    throw error;
  } finally {
    connection.release();
    await pool.end();
  }
}

addDisplayOrderColumn()
  .then(() => {
    console.log('✅ Migration completed successfully');
    process.exit(0);
  })
  .catch((error) => {
    console.error('❌ Migration failed:', error);
    process.exit(1);
  });
