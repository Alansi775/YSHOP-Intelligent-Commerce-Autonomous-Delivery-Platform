import { Router } from 'express';
import multer from 'multer';
import path from 'path';
import { v4 as uuidv4 } from 'uuid';
import ProductController from '../controllers/ProductController.js';
import { validateProduct, handleValidationErrors } from '../middleware/validation.js';
import { verifyFirebaseToken, verifyAdminToken, verifyAdminRole } from '../middleware/auth.js';

const router = Router();

// Configure multer for product images
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, './uploads/products');
  },
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname);
    cb(null, `${uuidv4()}${ext}`);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 104857600 }, // 100MB — covers a ~40s product video, not just a photo
  fileFilter: (req, file, cb) => {
    // Product media now accepts several images plus one optional video in
    // the same 'media' field (see ProductController.create/update, which
    // sorts req.files by mimetype rather than trusting field name).
    const allowedMimes = [
      'image/jpeg', 'image/jpg', 'image/png', 'image/gif', 'image/webp', 'image/x-png',
      'video/mp4', 'video/quicktime', 'video/webm', 'video/x-m4v',
    ];
    const allowedExts = /\.(jpeg|jpg|png|gif|webp|mp4|mov|webm|m4v)$/i;
    const mimeMatches = allowedMimes.includes(file.mimetype);
    const extMatches = allowedExts.test(file.originalname.toLowerCase());

    if (mimeMatches || extMatches) {
      return cb(null, true);
    }

    console.log('Invalid file rejected:', {
      originalname: file.originalname,
      mimetype: file.mimetype
    });
    cb(new Error('Invalid file type'));
  },
});

// ==================== PUBLIC ROUTES ====================
// NOTE: Admin routes must be declared before parameterized routes like '/:id'
// to avoid '/admin/...' being captured by '/:id'.

// ==================== ADMIN ROUTES (must come first) ====================
router.get('/admin/pending', verifyAdminToken, verifyAdminRole, ProductController.getPendingProducts);
router.get('/admin/approved', verifyAdminToken, verifyAdminRole, ProductController.getApprovedProducts);
router.get('/admin/by-email', verifyAdminToken, verifyAdminRole, ProductController.getProductsByEmail);
router.get('/admin/store/:storeId', verifyAdminToken, verifyAdminRole, ProductController.getStoreProductsAdmin);
router.put('/admin/:id/status', verifyAdminToken, verifyAdminRole, ProductController.updateProductStatus);
router.put('/admin/:id/approve', verifyAdminToken, verifyAdminRole, ProductController.approveProduct);
router.put('/admin/:id/reject', verifyAdminToken, verifyAdminRole, ProductController.rejectProduct);
router.put('/admin/:id/toggle-status', verifyAdminToken, verifyAdminRole, ProductController.toggleProductStatus);

// Public product listing and details
router.get('/', ProductController.getAll);
router.get('/:id', ProductController.getById);

// ==================== AUTHENTICATED ROUTES ====================
router.post('/', verifyFirebaseToken, upload.array('media', 10), validateProduct, ProductController.create);
router.put('/:id', verifyFirebaseToken, upload.array('media', 10), ProductController.update);
router.delete('/:id', verifyFirebaseToken, ProductController.delete);


export default router;