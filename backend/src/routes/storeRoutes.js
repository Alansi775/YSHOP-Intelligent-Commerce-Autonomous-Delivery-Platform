import { Router } from 'express';
import multer from 'multer';
import path from 'path';
import { v4 as uuidv4 } from 'uuid';
import StoreController from '../controllers/StoreController.js';
import { validateStore, handleValidationErrors } from '../middleware/validation.js';
import { verifyFirebaseToken, verifyAdminToken, verifyAdminRole } from '../middleware/auth.js';

const router = Router();

// Public route: جلب المتاجر حسب النوع للمستخدمين العاديين
router.get('/public', StoreController.getPublicStores);

// Configure multer for store icons
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, './uploads/stores');
  },
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname);
    cb(null, `${uuidv4()}${ext}`);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 52428800 }, // 50MB
  fileFilter: (req, file, cb) => {
    console.log('File upload:', file.originalname, file.mimetype); // Debug print
    const allowedTypes = /jpeg|jpg|png|gif|webp/;
    const extname = allowedTypes.test(path.extname(file.originalname).toLowerCase());
    // قبول الصور حتى لو كان mimetype application/octet-stream (بعض تطبيقات Flutter)
    if (extname) {
      return cb(null, true);
    }
    console.log('❌ Rejected file:', file.originalname, 'mimetype:', file.mimetype, 'ext:', path.extname(file.originalname));
    cb(new Error('Invalid file type'));
  },
});

// Admin routes for Dashboard - must come before generic routes
//  NEW: Single endpoint for all dashboard store data (solves the 6-request problem!)
router.get('/admin/dashboard-stats', verifyAdminToken, verifyAdminRole, StoreController.getDashboardStats);

router.get('/admin/pending', verifyAdminToken, verifyAdminRole, StoreController.getPendingStores);
router.get('/admin/approved', verifyAdminToken, verifyAdminRole, StoreController.getApprovedStores);
router.put('/admin/:id/approve', verifyAdminToken, verifyAdminRole, StoreController.approveStore);
router.put('/admin/:id/reject', verifyAdminToken, verifyAdminRole, StoreController.rejectStore);
router.put('/admin/:id/suspend', verifyAdminToken, verifyAdminRole, StoreController.suspendStore);
router.delete('/admin/:id/delete', verifyAdminToken, verifyAdminRole, StoreController.deleteStoreWithProducts);

// Real-time updates endpoint - lightweight, for smart polling
router.get('/updates-since/:timestamp', StoreController.getUpdatedStores);

// Generic Routes
router.get('/', StoreController.getAll);
router.post('/', verifyFirebaseToken, upload.single('icon'), validateStore, StoreController.create);
router.get('/:id', StoreController.getById);
router.put('/:id', verifyFirebaseToken, upload.single('icon'), StoreController.update);
router.delete('/:id', verifyFirebaseToken, StoreController.delete);

export default router;
