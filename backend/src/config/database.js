import mysql from 'mysql2/promise';
import dotenv from 'dotenv';

dotenv.config();

// Connection Pool للأداء العالي
const pool = mysql.createPool({
  host: process.env.DB_HOST || 'localhost',
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'yshop_db',
  waitForConnections: true,
  connectionLimit: 20, // عدد الـ connections المتزامنة
  queueLimit: 0,
  enableKeepAlive: true,
  keepAliveInitialDelayMs: 0,
  port: process.env.DB_PORT || 3306
});

export default pool;
