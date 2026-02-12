import { Router } from 'express';
import ReturnController from '../controllers/ReturnController.js';
import { verifyFirebaseToken, verifyAdminToken } from '../middleware/auth.js';
import multer from 'multer';
import path from 'path';
import { fileURLToPath } from 'url';
import fs from 'fs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Ensure uploads/returns directory exists
const uploadsDir = path.join(__dirname, '../../uploads/returns');
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir, { recursive: true });
}

// Configure multer for file uploads
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, uploadsDir);
  },
  filename: (req, file, cb) => {
    cb(null, `${Date.now()}-${Math.random().toString(36).substr(2, 9)}.jpg`);
  },
});

const upload = multer({
  storage,
  fileFilter: (req, file, cb) => {
    const allowedMimes = ['image/jpeg', 'image/png', 'image/webp'];
    if (allowedMimes.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error('Invalid file type. Only JPEG, PNG, and WebP are allowed.'));
    }
  },
  limits: {
    fileSize: 5 * 1024 * 1024, // 5MB per file
  },
});

// Error handler middleware for multer
const handleMulterErrors = (err, req, res, next) => {
  if (err instanceof multer.MulterError) {
    if (err.code === 'LIMIT_FILE_SIZE') {
      return res.status(400).json({ success: false, message: 'File too large. Max 5MB.' });
    }
    if (err.code === 'LIMIT_FILE_COUNT') {
      return res.status(400).json({ success: false, message: 'Max 6 files allowed.' });
    }
    return res.status(400).json({ success: false, message: err.message });
  } else if (err) {
    return res.status(400).json({ success: false, message: err.message });
  }
  next();
};

const router = Router();

// Admin route - get all returned products
router.get('/list', verifyAdminToken, ReturnController.getReturnedProducts);

// All other return routes require firebase authentication
router.use(verifyFirebaseToken);

// Customer submit return with photos
router.post(
  '/submit',
  upload.array('photos', 6),
  handleMulterErrors,
  ReturnController.submitReturn
);

// Get returns for specific store (store owner only)
router.get('/store/:storeId', ReturnController.getReturnsByStore);

// Admin approve/reject returns (these routes take precedence)
router.use(verifyAdminToken);
router.post('/:returnId/approve', ReturnController.approveReturn);
router.post('/:returnId/reject', ReturnController.rejectReturn);

export default router;
