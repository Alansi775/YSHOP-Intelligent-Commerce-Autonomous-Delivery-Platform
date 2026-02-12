import pool from '../../src/config/database.js';
import logger from '../../src/config/logger.js';

/**
 * Database Initialization Script
 * This script creates all necessary tables with proper indexes
 */

async function initDatabase() {
  let connection;
  try {
    connection = await pool.getConnection();

    logger.info('Starting database initialization...');

    // Create users table
    await connection.execute(`
      CREATE TABLE IF NOT EXISTS users (
        id INT AUTO_INCREMENT PRIMARY KEY,
        uid VARCHAR(255) UNIQUE NOT NULL,
        email VARCHAR(255) UNIQUE NOT NULL,
        display_name VARCHAR(255),
        phone VARCHAR(20),
        address TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_uid (uid),
        INDEX idx_email (email),
        INDEX idx_created_at (created_at)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    `);

    // Create stores table
    await connection.execute(`
      CREATE TABLE IF NOT EXISTS stores (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        description TEXT,
        phone VARCHAR(20),
        address TEXT NOT NULL,
        latitude DECIMAL(10, 8),
        longitude DECIMAL(11, 8),
        icon_url VARCHAR(255),
        owner_uid VARCHAR(255),
        is_active BOOLEAN DEFAULT true,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_name (name),
        INDEX idx_owner_uid (owner_uid),
        INDEX idx_is_active (is_active),
        INDEX idx_created_at (created_at),
        INDEX idx_coordinates (latitude, longitude),
        FOREIGN KEY (owner_uid) REFERENCES users(uid) ON DELETE SET NULL
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    `);

    // Create products table
    await connection.execute(`
      CREATE TABLE IF NOT EXISTS products (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        description TEXT,
        price DECIMAL(10, 2) NOT NULL,
        store_id INT NOT NULL,
        category_id INT,
        stock INT DEFAULT 0,
        image_url VARCHAR(255),
        is_active BOOLEAN DEFAULT true,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE,
        INDEX idx_store_id (store_id),
        INDEX idx_category_id (category_id),
        INDEX idx_name (name),
        INDEX idx_is_active (is_active),
        INDEX idx_price (price),
        INDEX idx_created_at (created_at),
        FULLTEXT INDEX ft_name_desc (name, description)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    `);

    // Create orders table
    await connection.execute(`
      CREATE TABLE IF NOT EXISTS orders (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id VARCHAR(255) NOT NULL,
        store_id INT NOT NULL,
        total_price DECIMAL(10, 2) NOT NULL,
        status ENUM('pending', 'confirmed', 'shipped', 'delivered', 'cancelled', 'return') DEFAULT 'pending',
        shipping_address TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users(uid) ON DELETE CASCADE,
        FOREIGN KEY (store_id) REFERENCES stores(id),
        INDEX idx_user_id (user_id),
        INDEX idx_store_id (store_id),
        INDEX idx_status (status),
        INDEX idx_created_at (created_at)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    `);

    // Create order_items table
    await connection.execute(`
      CREATE TABLE IF NOT EXISTS order_items (
        id INT AUTO_INCREMENT PRIMARY KEY,
        order_id INT NOT NULL,
        product_id INT NOT NULL,
        quantity INT NOT NULL,
        price DECIMAL(10, 2) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products(id),
        INDEX idx_order_id (order_id),
        INDEX idx_product_id (product_id)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    `);

    // Create categories table
    await connection.execute(`
      CREATE TABLE IF NOT EXISTS categories (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        description TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_name (name)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    `);

    // Create cart_items table
    await connection.execute(`
      CREATE TABLE IF NOT EXISTS cart_items (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id VARCHAR(255) NOT NULL,
        product_id INT NOT NULL,
        quantity INT NOT NULL DEFAULT 1,
        added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        deleted_at TIMESTAMP NULL,
        FOREIGN KEY (user_id) REFERENCES users(uid) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
        INDEX idx_user_id (user_id),
        INDEX idx_product_id (product_id),
        INDEX idx_deleted_at (deleted_at)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    `);

    // Create returned_products table
    await connection.execute(`
      CREATE TABLE IF NOT EXISTS returned_products (
        id INT AUTO_INCREMENT PRIMARY KEY,
        order_id INT NOT NULL,
        product_id INT NOT NULL,
        order_item_id INT NOT NULL,
        user_id VARCHAR(255) NOT NULL,
        store_id INT NOT NULL,
        driver_id VARCHAR(255),
        
        product_name VARCHAR(255) NOT NULL,
        product_description TEXT,
        product_price DECIMAL(10, 2) NOT NULL,
        product_currency VARCHAR(10),
        product_image_url VARCHAR(255),
        
        store_name VARCHAR(255),
        store_phone VARCHAR(20),
        store_address TEXT,
        store_icon_url VARCHAR(255),
        store_owner_uid VARCHAR(255),
        
        driver_name VARCHAR(255),
        driver_phone VARCHAR(20),
        driver_email VARCHAR(255),
        driver_national_id VARCHAR(50),
        
        quantity INT DEFAULT 1,
        return_reason TEXT NOT NULL,
        
        photo_top VARCHAR(255),
        photo_bottom VARCHAR(255),
        photo_right VARCHAR(255),
        photo_left VARCHAR(255),
        photo_front VARCHAR(255),
        photo_back VARCHAR(255),
        
        admin_accepted BOOLEAN DEFAULT FALSE,
        delivered_at DATETIME,
        return_requested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        
        FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products(id),
        FOREIGN KEY (order_item_id) REFERENCES order_items(id) ON DELETE CASCADE,
        FOREIGN KEY (user_id) REFERENCES users(uid) ON DELETE CASCADE,
        FOREIGN KEY (store_id) REFERENCES stores(id),
        
        INDEX idx_order_id (order_id),
        INDEX idx_product_id (product_id),
        INDEX idx_user_id (user_id),
        INDEX idx_store_id (store_id),
        INDEX idx_driver_id (driver_id),
        INDEX idx_return_requested_at (return_requested_at),
        INDEX idx_created_at (created_at)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    `);

    logger.info(' Database tables created successfully');
    connection.release();
  } catch (error) {
    logger.error('❌ Error initializing database:', error);
    if (connection) connection.release();
    throw error;
  }
}

// Run initialization
initDatabase()
  .then(() => {
    logger.info('Database initialization completed');
    process.exit(0);
  })
  .catch((error) => {
    logger.error('Database initialization failed:', error);
    process.exit(1);
  });
