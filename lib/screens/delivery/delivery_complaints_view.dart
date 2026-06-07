import 'package:flutter/material.dart';
import '../../services/api_service.dart';

const Color _kDark = Color(0xFF121212);
const Color _kCard = Color(0xFF1E1E1E);
const Color _kBlue = Color(0xFF2979FF);
const Color _kText = Color(0xFFEEEEEE);
const Color _kSub = Color(0xFFB0B0B0);
const Color _kGreen = Color(0xFF00E676);
const Color _kRed = Color(0xFFFF5252);
const Color _kOrange = Color(0xFFFF9800);

class DeliveryComplaintsView extends StatefulWidget {
  final Future<void> Function(List<Map<String, dynamic>> complaints)? onComplaintsViewed;
  const DeliveryComplaintsView({super.key, this.onComplaintsViewed});

  @override
  State<DeliveryComplaintsView> createState() => _DeliveryComplaintsViewState();
}

class _DeliveryComplaintsViewState extends State<DeliveryComplaintsView> {
  List<Map<String, dynamic>> _complaints = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.getDriverComplaints();
      if (mounted) {
        setState(() { _complaints = data; _isLoading = false; });
        // Mark all loaded complaints as seen
        widget.onComplaintsViewed?.call(data);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kDark,
      appBar: AppBar(
        title: const Text('Complaints About Me', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _kDark,
        foregroundColor: _kText,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _kBlue))
          : _complaints.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  color: _kBlue,
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _complaints.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _ComplaintCard(complaint: _complaints[i]),
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _kBlue.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.shield_outlined, color: _kBlue, size: 48),
            ),
            const SizedBox(height: 24),
            const Text('No Complaints', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _kText)),
            const SizedBox(height: 8),
            const Text('You have no complaints assigned to you.', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: _kSub)),
          ],
        ),
      ),
    );
  }
}

class _ComplaintCard extends StatelessWidget {
  final Map<String, dynamic> complaint;
  const _ComplaintCard({required this.complaint});

  String get _status => (complaint['status'] as String? ?? '').toUpperCase();
  String get _orderId => complaint['order_id']?.toString() ?? '';
  String get _type => (complaint['complaint_type'] as String? ?? '').replaceAll('_', ' ');
  String? get _subType => complaint['sub_type'] as String?;
  String? get _description => complaint['description'] as String?;
  String? get _adminNotes => complaint['admin_notes'] as String?;
  String? get _responsibleParty => complaint['responsible_party'] as String?;
  String? get _customerName => complaint['customer_name'] as String?;
  String? get _storeName => complaint['store_name'] as String?;
  String? get _currency => complaint['currency'] as String?;

  bool get _isDriverResponsible {
    final p = _responsibleParty ?? '';
    return p.contains('driver');
  }

  Color get _statusColor {
    switch (_status) {
      case 'APPROVED': return _kGreen;
      case 'REJECTED': return _kRed;
      case 'UNDER_REVIEW': return _kBlue;
      default: return _kOrange;
    }
  }

  String get _statusLabel {
    switch (_status) {
      case 'APPROVED': return 'Approved';
      case 'REJECTED': return 'Rejected';
      case 'UNDER_REVIEW': return 'Under Review';
      default: return 'Pending';
    }
  }

  String get _totalFormatted {
    final raw = complaint['total_price'];
    if (raw == null) return '';
    final val = raw is num ? (raw as num).toDouble() : double.tryParse(raw.toString()) ?? 0.0;
    return '${val.toStringAsFixed(2)} ${_currency ?? 'SAR'}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isDriverResponsible ? _kOrange.withOpacity(0.3) : Colors.white.withOpacity(0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: status + order
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 7, height: 7, decoration: BoxDecoration(color: _statusColor, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(_statusLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _statusColor)),
                  ],
                ),
              ),
              const Spacer(),
              Text('Order #$_orderId', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _kText)),
            ],
          ),

          // Responsibility warning
          if (_isDriverResponsible) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _kOrange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kOrange.withOpacity(0.25)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: _kOrange, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('You have been identified as responsible for this complaint.',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _kOrange)),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Info rows
          _row('Issue', _type.isNotEmpty ? _type : '—'),
          if (_subType?.isNotEmpty == true) _row('Detail', _subType!),
          if (_customerName?.isNotEmpty == true) _row('Customer', _customerName!),
          if (_storeName?.isNotEmpty == true) _row('Store', _storeName!),
          if (_totalFormatted.isNotEmpty) _row('Order Total', _totalFormatted),

          // Description
          if (_description?.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Text("Customer's Statement", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _kSub)),
            const SizedBox(height: 4),
            Text(_description!, style: const TextStyle(fontSize: 13, color: _kText)),
          ],

          // Admin notes
          if (_adminNotes?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.yellow.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.yellow.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.verified_user_outlined, color: Colors.yellow, size: 14),
                      SizedBox(width: 6),
                      Text('YShop Decision', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.yellow)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(_adminNotes!, style: const TextStyle(fontSize: 12, color: Colors.yellow)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: Text(label, style: const TextStyle(fontSize: 12, color: _kSub))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kText))),
        ],
      ),
    );
  }
}
