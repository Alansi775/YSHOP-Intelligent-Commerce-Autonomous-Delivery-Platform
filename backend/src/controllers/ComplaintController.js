import Complaint from '../models/Complaint.js';
import Order from '../models/Order.js';
import logger from '../config/logger.js';

export class ComplaintController {
  // POST /api/v1/complaints  — customer submits complaint (within 30-min window)
  static async create(req, res, next) {
    try {
      const uid = req.user?.id || req.user?.uid;
      if (!uid) return res.status(401).json({ success: false, message: 'Unauthorized' });

      const { orderId, complaintType, subType, description, photos } = req.body;
      if (!orderId || !complaintType) {
        return res.status(400).json({ success: false, message: 'orderId and complaintType are required' });
      }

      const order = await Order.findById(orderId);
      if (!order) return res.status(404).json({ success: false, message: 'Order not found' });
      if (order.user_id !== uid) return res.status(403).json({ success: false, message: 'Forbidden' });
      if (order.status.toLowerCase() !== 'delivered') {
        return res.status(400).json({ success: false, message: 'Order must be delivered before filing a complaint' });
      }

      if (order.delivered_at) {
        const deliveredMs = new Date(order.delivered_at).getTime();
        if (Date.now() - deliveredMs > 30 * 60 * 1000) {
          return res.status(400).json({ success: false, message: 'Complaint window has expired (30 minutes after delivery)' });
        }
      }

      const id = await Complaint.create({
        orderId,
        customerId: uid,
        driverId: order.driver_id || null,
        storeId: order.store_id || null,
        complaintType,
        subType,
        description,
        photos,
      });

      logger.info(`Complaint #${id} created for order ${orderId} by customer ${uid}`);
      res.status(201).json({ success: true, data: { id } });
    } catch (error) {
      logger.error('Error creating complaint:', error);
      next(error);
    }
  }

  // GET /api/v1/complaints/my  — customer views their own complaints
  static async getMine(req, res, next) {
    try {
      const uid = req.user?.id || req.user?.uid;
      if (!uid) return res.status(401).json({ success: false, message: 'Unauthorized' });
      const { page = 1, limit = 20 } = req.query;
      const complaints = await Complaint.findByCustomer(uid, { page: +page, limit: +limit });
      res.json({ success: true, data: complaints });
    } catch (error) {
      logger.error('Error fetching customer complaints:', error);
      next(error);
    }
  }

  // GET /api/v1/complaints/store  — store owner sees complaints assigned to their store
  static async getForStore(req, res, next) {
    try {
      const storeId = req.store?.id || req.query.storeId;
      if (!storeId) return res.status(400).json({ success: false, message: 'storeId required' });
      const { page = 1, limit = 50 } = req.query;
      const complaints = await Complaint.findByStore(storeId, { page: +page, limit: +limit });
      res.json({ success: true, data: complaints });
    } catch (error) {
      logger.error('Error fetching store complaints:', error);
      next(error);
    }
  }

  // GET /api/v1/complaints/driver  — driver sees complaints assigned to them
  static async getForDriver(req, res, next) {
    try {
      const uid = req.driver?.uid || req.user?.uid || req.user?.id;
      if (!uid) return res.status(401).json({ success: false, message: 'Unauthorized' });
      const { page = 1, limit = 50 } = req.query;
      const complaints = await Complaint.findByDriver(uid, { page: +page, limit: +limit });
      res.json({ success: true, data: complaints });
    } catch (error) {
      logger.error('Error fetching driver complaints:', error);
      next(error);
    }
  }

  // GET /api/v1/complaints  — admin lists all complaints
  static async getAll(req, res, next) {
    try {
      const { page = 1, limit = 50, status } = req.query;
      const complaints = await Complaint.findAll({ page: +page, limit: +limit, status });
      res.json({ success: true, data: complaints });
    } catch (error) {
      logger.error('Error fetching complaints:', error);
      next(error);
    }
  }

  // GET /api/v1/complaints/:id  — get single complaint with full details
  static async getById(req, res, next) {
    try {
      const uid = req.user?.id || req.user?.uid;
      const isAdmin = !!(req.admin);
      const complaint = await Complaint.findById(req.params.id);
      if (!complaint) return res.status(404).json({ success: false, message: 'Complaint not found' });
      if (!isAdmin && complaint.customer_id !== uid) {
        return res.status(403).json({ success: false, message: 'Forbidden' });
      }
      res.json({ success: true, data: complaint });
    } catch (error) {
      logger.error('Error fetching complaint:', error);
      next(error);
    }
  }

  // PATCH /api/v1/complaints/:id/status  — admin updates status + responsible party
  static async updateStatus(req, res, next) {
    try {
      const { status, adminNotes, resolutionType, responsibleParty } = req.body;
      const validStatuses = ['PENDING', 'UNDER_REVIEW', 'APPROVED', 'REJECTED'];
      const validParties = ['platform', 'store', 'driver', 'platform_store', 'platform_driver', 'store_driver'];
      if (!validStatuses.includes(status)) {
        return res.status(400).json({ success: false, message: 'Invalid status' });
      }
      if (responsibleParty && !validParties.includes(responsibleParty)) {
        return res.status(400).json({ success: false, message: 'Invalid responsible party' });
      }
      const complaint = await Complaint.findById(req.params.id);
      if (!complaint) return res.status(404).json({ success: false, message: 'Complaint not found' });
      await Complaint.updateStatus(req.params.id, status, adminNotes, resolutionType, responsibleParty);
      logger.info(`Complaint #${req.params.id} → ${status}${responsibleParty ? ` (responsible: ${responsibleParty})` : ''}`);
      res.json({ success: true });
    } catch (error) {
      logger.error('Error updating complaint status:', error);
      next(error);
    }
  }
}

export default ComplaintController;
