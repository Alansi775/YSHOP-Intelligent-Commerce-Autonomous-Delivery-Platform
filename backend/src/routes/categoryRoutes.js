import express from 'express';
import pool from '../config/database.js';

const router = express.Router();
let categorySchemaReadyPromise = null;

async function ensureCategorySchema() {
  if (categorySchemaReadyPromise) return categorySchemaReadyPromise;

  categorySchemaReadyPromise = (async () => {
    const [columnRows] = await pool.query(
      `SELECT COLUMN_NAME
       FROM INFORMATION_SCHEMA.COLUMNS
       WHERE TABLE_SCHEMA = DATABASE()
         AND TABLE_NAME = 'categories'`
    );

    const columns = new Set(columnRows.map((r) => r.COLUMN_NAME));
    const alterStatements = [];

    if (!columns.has('store_id')) {
      alterStatements.push('ALTER TABLE categories ADD COLUMN store_id INT NULL');
      alterStatements.push('ALTER TABLE categories ADD INDEX idx_store_id (store_id)');
    }
    if (!columns.has('display_name')) {
      alterStatements.push('ALTER TABLE categories ADD COLUMN display_name VARCHAR(255) NULL');
    }
    if (!columns.has('icon')) {
      alterStatements.push('ALTER TABLE categories ADD COLUMN icon VARCHAR(255) NULL');
    }
    if (!columns.has('display_order')) {
      alterStatements.push('ALTER TABLE categories ADD COLUMN display_order INT NOT NULL DEFAULT 0');
    }
    if (!columns.has('updated_at')) {
      alterStatements.push(
        'ALTER TABLE categories ADD COLUMN updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP'
      );
    }

    for (const sql of alterStatements) {
      await pool.query(sql);
    }

    await pool.query(
      'UPDATE categories SET display_name = name WHERE display_name IS NULL OR display_name = ""'
    );
  })().catch((error) => {
    categorySchemaReadyPromise = null;
    throw error;
  });

  return categorySchemaReadyPromise;
}

/**
 * Helper function to get display name from category name
 */
function getDisplayName(categoryName) {
  const categoryMap = {
    fruits: 'Fruits 🍎',
    vegetables: 'Vegetables 🥕',
    beverages: 'Beverages 🥤',
    meat: 'Meat 🥩',
    chicken: 'Chicken 🍗',
    bakery: 'Bakery 🍞',
    canned_goods: 'Canned Goods 🥫',
    cleaning: 'Cleaning Supplies 🧹',
    dairy: 'Dairy 🧀',
    frozen: 'Frozen Foods ❄️',
    snacks: 'Snacks 🍿',
    condiments: 'Condiments 🧂',
  };

  return categoryMap[categoryName?.toLowerCase()] || categoryName;
}

// ============================================
// GET /stores/:storeId/categories
// Get all categories for a store (مرتبة حسب display_order)
// ============================================
router.get('/:storeId/categories', async (req, res) => {
  const { storeId } = req.params;

  try {
    await ensureCategorySchema();

    const query = `
      SELECT 
        id,
        store_id,
        name,
        display_name,
        icon,
        display_order,
        created_at,
        updated_at
      FROM categories
      WHERE store_id = ?
      ORDER BY display_order ASC, created_at ASC
    `;

    const [categories] = await pool.query(query, [storeId]);

    // Count products in each category
    const result = await Promise.all(
      categories.map(async (cat) => {
        const [products] = await pool.query(
          'SELECT name FROM products WHERE category_id = ? ORDER BY updated_at DESC LIMIT 1',
          [cat.id]
        );
        return {
          ...cat,
          productCount: (await pool.query('SELECT COUNT(*) as count FROM products WHERE category_id = ?', [cat.id]))[0][0]?.count || 0,
          lastProductName: products.length > 0 ? products[0].name : '',
        };
      })
    );

    res.json({ data: result });
  } catch (error) {
    console.error('❌ Error fetching categories:', error);
    res.status(500).json({ error: 'Failed to fetch categories' });
  }
});

// ============================================
// POST /stores/:storeId/categories
// Create a new category
// ============================================
router.post('/:storeId/categories', async (req, res) => {
  const { storeId } = req.params;
  const { name } = req.body;

  // Validation
  if (!name || name.trim() === '') {
    return res.status(400).json({ error: 'Category name is required' });
  }

  const connection = await pool.getConnection();
  
  try {
    await ensureCategorySchema();

    const displayName = getDisplayName(name);

    // احصل على أعلى display_order للمتجر
    const [maxOrderResult] = await connection.query(
      'SELECT MAX(display_order) as max_order FROM categories WHERE store_id = ?',
      [storeId]
    );
    
    const newDisplayOrder = (maxOrderResult[0]?.max_order || 0) + 1;

    const query = `
      INSERT INTO categories (store_id, name, display_name, display_order, created_at, updated_at)
      VALUES (?, ?, ?, ?, NOW(), NOW())
    `;

    const [result] = await connection.query(query, [storeId, name, displayName, newDisplayOrder]);

    res.json({
      data: {
        id: result.insertId,
        store_id: parseInt(storeId),
        name,
        display_name: displayName,
        display_order: newDisplayOrder,
        created_at: new Date(),
        updated_at: new Date(),
      },
    });
  } catch (error) {
    console.error('❌ Error creating category:', error);
    if (error.code === 'ER_DUP_ENTRY') {
      return res.status(400).json({ error: 'Category already exists' });
    }
    res.status(500).json({ error: 'Failed to create category' });
  } finally {
    connection.release();
  }
});

// ============================================
// DELETE /stores/:storeId/categories/:categoryId
// Delete a category (move products out)
// ============================================
router.delete('/:storeId/categories/:categoryId', async (req, res) => {
  const { storeId, categoryId } = req.params;

  const connection = await pool.getConnection();
  try {
    await ensureCategorySchema();
    await connection.beginTransaction();

    // Remove category_id from all products
    await connection.query(
      'UPDATE products SET category_id = NULL WHERE category_id = ?',
      [categoryId]
    );

    // Delete the category
    await connection.query(
      'DELETE FROM categories WHERE id = ? AND store_id = ?',
      [categoryId, storeId]
    );

    await connection.commit();
    res.json({ success: true });
  } catch (error) {
    await connection.rollback();
    console.error('❌ Error deleting category:', error);
    res.status(500).json({ error: 'Failed to delete category' });
  } finally {
    connection.release();
  }
});

// ============================================
// GET /categories/:categoryId/products
// Get all products in a category
// ============================================
router.get('/categories/:categoryId/products', async (req, res) => {
  const { categoryId } = req.params;

  try {
    const query = `
      SELECT 
        id,
        name,
        price,
        currency,
        description,
        image_url,
        status,
        stock,
        category_id
      FROM products
      WHERE category_id = ?
      ORDER BY updated_at DESC
    `;

    const [products] = await pool.query(query, [categoryId]);
    res.json({ data: products });
  } catch (error) {
    console.error('❌ Error fetching category products:', error);
    res.status(500).json({ error: 'Failed to fetch products' });
  }
});

// ============================================
// PUT /products/:productId/category
// Assign or remove product from category
// ============================================
router.put('/products/:productId/category', async (req, res) => {
  const { productId } = req.params;
  const { category_id } = req.body;

  try {
    if (category_id === null) {
      // Remove from category
      await pool.query(
        'UPDATE products SET category_id = NULL WHERE id = ?',
        [productId]
      );
    } else {
      // Assign to category
      await pool.query(
        'UPDATE products SET category_id = ? WHERE id = ?',
        [category_id, productId]
      );
    }

    res.json({ success: true });
  } catch (error) {
    console.error('❌ Error updating product category:', error);
    res.status(500).json({ error: 'Failed to update category' });
  }
});

// ============================================
// PUT /stores/:storeId/categories/reorder
// إعادة ترتيب الفئات
// Body: { categories: [{ id: 1, display_order: 1 }, ...] }
// ============================================
router.put('/:storeId/categories/reorder', async (req, res) => {
  const { storeId } = req.params;
  const { categories } = req.body;

  // التحقق من البيانات
  if (!Array.isArray(categories) || categories.length === 0) {
    return res.status(400).json({ error: 'Categories array is required' });
  }

  const connection = await pool.getConnection();
  
  try {
    await ensureCategorySchema();
    await connection.beginTransaction();

    // تحديث ترتيب كل فئة
    for (const cat of categories) {
      if (!cat.id || cat.display_order === undefined) {
        throw new Error('Category id and display_order are required');
      }

      await connection.query(
        'UPDATE categories SET display_order = ?, updated_at = NOW() WHERE id = ? AND store_id = ?',
        [cat.display_order, cat.id, storeId]
      );
    }

    await connection.commit();
    
    res.json({ 
      success: true, 
      message: 'Categories reordered successfully' 
    });
  } catch (error) {
    await connection.rollback();
    console.error('❌ Error reordering categories:', error);
    res.status(500).json({ error: error.message || 'Failed to reorder categories' });
  } finally {
    connection.release();
  }
});

export default router;
