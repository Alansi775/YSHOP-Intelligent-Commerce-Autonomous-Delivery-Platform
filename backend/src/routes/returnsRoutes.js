import { Router } from 'express';
import ReturnController from '../controllers/ReturnController.js';
import { verifyFirebaseToken, verifyAdminToken, verifyJWTToken } from '../middleware/auth.js';
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

// /list: accessible by admin OR delivery driver
const verifyAdminOrDriver = (req, res, next) => {
  verifyJWTToken(req, res, (err) => {
    if (err) return next(err);
    const role = req.user?.role;
    if (role === 'admin' || role === 'deliveryDriver') return next();
    // fallback: try admin token path
    verifyAdminToken(req, res, next);
  });
};
router.get('/list', verifyAdminOrDriver, ReturnController.getReturnedProducts);

// Driver: pending return pickups (admin_accepted=1, store_received=0)
router.get('/driver/pending', verifyJWTToken, ReturnController.getDriverReturnPickups);

// Driver: confirm picked up from customer
router.put('/:returnId/driver-picked-up', verifyJWTToken, ReturnController.driverPickedUp);

// All other return routes require firebase authentication
router.use(verifyFirebaseToken);

// Debug middleware for returns routes - log BEFORE auth check
router.use((req, res, next) => {
  console.log(`\n🔍 [RETURNS ROUTE] ${req.method} ${req.path}`, {
    fullUrl: req.url,
    storeId: req.params.storeId,
    returnId: req.params.returnId,
    hasUser: !!req.user,
    userId: req.user?.id,
  });
  next();
});

// Customer submit return with photos
router.post(
  '/submit',
  upload.array('photos', 6),
  handleMulterErrors,
  ReturnController.submitReturn
);

// Get returns for specific store (store owner only)
router.get('/store/:storeId', ReturnController.getReturnsByStore);

// Store owner receive return (requires authentication)
router.put('/:returnId/store-received', ReturnController.receiveReturn);

// Admin approve/reject returns (these routes take precedence)
router.use(verifyAdminToken);
router.post('/:returnId/approve', ReturnController.approveReturn);
router.post('/:returnId/reject', ReturnController.rejectReturn);

export default router;
