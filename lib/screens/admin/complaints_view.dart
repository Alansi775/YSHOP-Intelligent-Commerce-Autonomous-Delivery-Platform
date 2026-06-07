// lib/screens/admin/complaints_view.dart
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../config/api_config.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  Constants
// ═══════════════════════════════════════════════════════════════════════════════

const _kBg = Color(0xFF0A0A0A);
const _kCard = Color(0xFF141414);
const _kBorder = Color(0x10FFFFFF);

const _responsibilityOptions = [
  _Responsibility('platform',        'YShop Platform',      Icons.shield_outlined,           Color(0xFF6C63FF)),
  _Responsibility('store',           'Store Owner',          Icons.storefront_outlined,        Color(0xFFF59E0B)),
  _Responsibility('driver',          'Driver',               Icons.delivery_dining_outlined,   Color(0xFF3B82F6)),
  _Responsibility('platform_store',  'Platform + Store',     Icons.handshake_outlined,         Color(0xFFEC4899)),
  _Responsibility('platform_driver', 'Platform + Driver',    Icons.compare_arrows_outlined,    Color(0xFF14B8A6)),
  _Responsibility('store_driver',    'Store + Driver',       Icons.people_outline,             Color(0xFFFF6B6B)),
];

class _Responsibility {
  final String value, label;
  final IconData icon;
  final Color color;
  const _Responsibility(this.value, this.label, this.icon, this.color);
}

// ═══════════════════════════════════════════════════════════════════════════════
//  List View
// ═══════════════════════════════════════════════════════════════════════════════

class ComplaintsManagementView extends StatefulWidget {
  const ComplaintsManagementView({Key? key}) : super(key: key);

  @override
  State<ComplaintsManagementView> createState() => _ComplaintsManagementViewState();
}

class _ComplaintsManagementViewState extends State<ComplaintsManagementView> {
  List<Map<String, dynamic>> _complaints = [];
  bool _isLoading = true;
  String? _filterStatus;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      _complaints = await ApiService.getComplaints(status: _filterStatus);
    } catch (e) {
      if (mounted) _snack('Error: $e', error: true);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Colors.red : Colors.green.withOpacity(0.9)),
    );
  }

  void _openDetail(Map<String, dynamic> summary) async {
    final refresh = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ComplaintDetailView(complaintId: summary['id'] as int)),
    );
    if (refresh == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 900;
    return Scaffold(
      backgroundColor: _kBg,
      body: RefreshIndicator(
        onRefresh: _load,
        color: Colors.white,
        backgroundColor: _kBg,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54))
            : _complaints.isEmpty
                ? _empty()
                : _list(isDesktop),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.sentiment_satisfied_alt_outlined, size: 80, color: Colors.white.withOpacity(0.1)),
        const SizedBox(height: 24),
        const Text('No Complaints', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w300, color: Colors.white)),
        const SizedBox(height: 8),
        Text('All clear', style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.4))),
      ]),
    );
  }

  Widget _list(bool isDesktop) {
    final hPad = isDesktop ? 80.0 : 24.0;
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(hPad, 48, hPad, 48),
          sliver: SliverList(delegate: SliverChildListDelegate([
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Complaints', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w300, color: Colors.white, letterSpacing: -0.5)),
              Text('${_complaints.length}', style: TextStyle(fontSize: 18, color: Colors.white.withOpacity(0.4))),
            ]),
            const SizedBox(height: 20),
            _filterBar(),
            const SizedBox(height: 32),
            ..._complaints.map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _SummaryCard(data: c, onTap: () => _openDetail(c)),
            )),
          ])),
        ),
      ],
    );
  }

  Widget _filterBar() {
    const statuses = [null, 'PENDING', 'UNDER_REVIEW', 'APPROVED', 'REJECTED'];
    const labels   = ['All', 'Pending', 'Under Review', 'Approved', 'Rejected'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: List.generate(statuses.length, (i) {
        final sel = _filterStatus == statuses[i];
        return Padding(
          padding: const EdgeInsets.only(right: 10),
          child: GestureDetector(
            onTap: () { setState(() => _filterStatus = statuses[i]); _load(); },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: sel ? Colors.white : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(labels[i], style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: sel ? Colors.black : Colors.white.withOpacity(0.6))),
            ),
          ),
        );
      })),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Summary Card (list item)
// ═══════════════════════════════════════════════════════════════════════════════

class _SummaryCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  const _SummaryCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status       = data['status']?.toString() ?? 'PENDING';
    final orderId      = data['order_id']?.toString() ?? '—';
    final type         = _fmtType(data['complaint_type']?.toString() ?? '');
    final customerName = data['customer_name']?.toString() ?? '—';
    final storeName    = data['store_name']?.toString() ?? '—';
    final driverName   = data['driver_name']?.toString() ?? '—';
    final createdAt    = _fmtDate(data['created_at']?.toString() ?? '');
    final sc           = _statusColor(status);
    final responsible  = data['responsible_party']?.toString();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kBorder),
        ),
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          // Status bar
          Container(width: 4, height: 60, decoration: BoxDecoration(color: sc, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: sc.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                child: Text(status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: sc)),
              ),
              const SizedBox(width: 10),
              Text('Order #$orderId', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
              if (responsible != null && responsible.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.purple.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                  child: Text(_fmtParty(responsible), style: const TextStyle(fontSize: 10, color: Colors.purpleAccent)),
                ),
              ],
              const Spacer(),
              Text(createdAt, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.35))),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 16, children: [
              _micro('Issue', type),
              _micro('Customer', customerName),
              _micro('Store', storeName),
              if (driverName != '—') _micro('Driver', driverName),
            ]),
          ])),
          const SizedBox(width: 12),
          Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.3)),
        ]),
      ),
    );
  }

  Widget _micro(String label, String value) => Row(mainAxisSize: MainAxisSize.min, children: [
    Text('$label: ', style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.35))),
    Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
  ]);
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Detail View
// ═══════════════════════════════════════════════════════════════════════════════

class ComplaintDetailView extends StatefulWidget {
  final int complaintId;
  const ComplaintDetailView({Key? key, required this.complaintId}) : super(key: key);

  @override
  State<ComplaintDetailView> createState() => _ComplaintDetailViewState();
}

class _ComplaintDetailViewState extends State<ComplaintDetailView> {
  Map<String, dynamic>? _data;
  bool _isLoading = true;
  bool _isSaving = false;
  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      _data = await ApiService.getComplaintDetail(widget.complaintId);
      _notesCtrl.text = _data?['admin_notes']?.toString() ?? '';
    } catch (e) {
      if (mounted) _snack('Error loading: $e', error: true);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Colors.red : Colors.green.withOpacity(0.9)),
    );
  }

  Future<void> _reject() async {
    if (_notesCtrl.text.trim().isEmpty) {
      _snack('Please write a note explaining the rejection', error: true);
      return;
    }
    setState(() => _isSaving = true);
    try {
      await ApiService.updateComplaintStatus(
        widget.complaintId, 'REJECTED',
        adminNotes: _notesCtrl.text.trim(),
      );
      _snack('Complaint rejected');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _snack('Failed: $e', error: true);
    }
    if (mounted) setState(() => _isSaving = false);
  }

  Future<void> _startReview() async {
    setState(() => _isSaving = true);
    try {
      await ApiService.updateComplaintStatus(widget.complaintId, 'UNDER_REVIEW');
      _snack('Moved to Under Review');
      await _load();
    } catch (e) {
      _snack('Failed: $e', error: true);
    }
    if (mounted) setState(() => _isSaving = false);
  }

  void _showResponsibilityDialog() {
    if (_notesCtrl.text.trim().isEmpty) {
      _snack('Write a response note before approving', error: true);
      return;
    }
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.8),
      builder: (_) => _ResponsibilityDialog(
        adminNotes: _notesCtrl.text.trim(),
        complaintId: widget.complaintId,
        onDone: () {
          _snack('Complaint approved & parties notified');
          Navigator.pop(context, true);
        },
      ),
    );
  }

  void _showAddNoteDialog() {
    final noteCtrl = TextEditingController(text: _data?['admin_notes']?.toString() ?? '');
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.8),
      builder: (_) => Dialog(
        backgroundColor: _kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Add Note', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 6),
            Text(
              'Log what happened or add context for this complaint.',
              style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.5), height: 1.5),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: noteCtrl,
              maxLines: 5,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Write your note here...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
                filled: true,
                fillColor: Colors.white.withOpacity(0.04),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  borderSide: BorderSide(color: Color(0xFF6C63FF)),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    final note = noteCtrl.text.trim();
                    Navigator.pop(context);
                    if (note.isEmpty) return;
                    setState(() => _isSaving = true);
                    try {
                      final currentStatus = _data?['status']?.toString() ?? 'APPROVED';
                      await ApiService.updateComplaintStatus(widget.complaintId, currentStatus, adminNotes: note);
                      _snack('Note saved');
                      await _load();
                    } catch (e) {
                      _snack('Failed: $e', error: true);
                    }
                    if (mounted) setState(() => _isSaving = false);
                  },
                  child: const Text('Save Note', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _data != null ? 'Complaint #${_data!['id']} — Order #${_data!['order_id']}' : 'Complaint Detail',
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54))
          : _data == null
              ? const Center(child: Text('Not found', style: TextStyle(color: Colors.white54)))
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final d = _data!;
    final status = d['status']?.toString() ?? 'PENDING';
    final isActionable = status == 'PENDING' || status == 'UNDER_REVIEW';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Status badge + complaint type
            _StatusBanner(data: d),
            const SizedBox(height: 24),

            // 3-column info row
            Wrap(spacing: 16, runSpacing: 16, children: [
              _InfoCard(
                icon: Icons.person_outline_rounded,
                color: const Color(0xFF3B82F6),
                title: 'Customer',
                rows: [
                  ('Name',    d['customer_name']?.toString()    ?? '—'),
                  ('Email',   d['customer_email']?.toString()   ?? '—'),
                  ('Phone',   d['customer_phone']?.toString()   ?? '—'),
                  ('Address', d['customer_address']?.toString() ?? '—'),
                ],
              ),
              _InfoCard(
                icon: Icons.storefront_outlined,
                color: const Color(0xFFF59E0B),
                title: 'Store',
                rows: [
                  ('Name',    d['store_name']?.toString()    ?? '—'),
                  ('Email',   d['store_email']?.toString()   ?? '—'),
                  ('Phone',   d['store_phone']?.toString()   ?? '—'),
                  ('Address', d['store_address']?.toString() ?? '—'),
                ],
              ),
              if ((d['driver_name']?.toString() ?? '').isNotEmpty &&
                  d['driver_name']?.toString() != 'null')
                _InfoCard(
                  icon: Icons.delivery_dining_outlined,
                  color: const Color(0xFF22C55E),
                  title: 'Driver',
                  rows: [
                    ('Name',  d['driver_name']?.toString()  ?? '—'),
                    ('Email', d['driver_email']?.toString() ?? '—'),
                    ('Phone', d['driver_phone']?.toString() ?? '—'),
                  ],
                ),
            ]),
            const SizedBox(height: 24),

            // Order items
            _OrderItemsSection(
              items: List<Map<String, dynamic>>.from(d['order_items'] ?? []),
              currency: d['currency']?.toString() ?? 'SAR',
            ),
            const SizedBox(height: 24),

            // Complaint detail
            _ComplaintSection(data: d),
            const SizedBox(height: 24),

            // Admin notes + actions
            if (isActionable) ...[
              _SectionTitle('Admin Response'),
              const SizedBox(height: 12),
              TextField(
                controller: _notesCtrl,
                maxLines: 4,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Write your response to the customer and parties...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.04),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF6C63FF)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Wrap(spacing: 12, runSpacing: 12, children: [
                if (status == 'PENDING')
                  _Btn(
                    label: 'Start Review',
                    color: const Color(0xFF3B82F6),
                    icon: Icons.rate_review_outlined,
                    loading: _isSaving,
                    onTap: _startReview,
                  ),
                _Btn(
                  label: 'Send & Approve',
                  color: const Color(0xFF22C55E),
                  icon: Icons.check_circle_outline_rounded,
                  loading: _isSaving,
                  onTap: _showResponsibilityDialog,
                ),
                _Btn(
                  label: 'Reject',
                  color: const Color(0xFFEF4444),
                  icon: Icons.cancel_outlined,
                  loading: _isSaving,
                  onTap: _reject,
                ),
              ]),
            ] else ...[
              // Read-only admin notes for closed complaints
              if ((d['admin_notes']?.toString() ?? '').isNotEmpty) ...[
                _SectionTitle('Admin Response'),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.withOpacity(0.2)),
                  ),
                  child: Text(d['admin_notes'].toString(), style: TextStyle(color: Colors.amber.withOpacity(0.9), height: 1.5)),
                ),
                if ((d['responsible_party']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _ResponsibleBadge(party: d['responsible_party'].toString()),
                ],
              ],
              const SizedBox(height: 20),
              _Btn(
                label: 'Add Note',
                color: const Color(0xFF6C63FF),
                icon: Icons.note_add_outlined,
                loading: _isSaving,
                onTap: _showAddNoteDialog,
              ),
            ],
            const SizedBox(height: 40),
          ]),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Responsibility Dialog
// ═══════════════════════════════════════════════════════════════════════════════

class _ResponsibilityDialog extends StatefulWidget {
  final String adminNotes;
  final int complaintId;
  final VoidCallback onDone;
  const _ResponsibilityDialog({required this.adminNotes, required this.complaintId, required this.onDone});

  @override
  State<_ResponsibilityDialog> createState() => _ResponsibilityDialogState();
}

class _ResponsibilityDialogState extends State<_ResponsibilityDialog> {
  String? _selected;
  bool _saving = false;

  Future<void> _confirm() async {
    if (_selected == null) return;
    setState(() => _saving = true);
    try {
      await ApiService.updateComplaintStatus(
        widget.complaintId, 'APPROVED',
        adminNotes: widget.adminNotes,
        responsibleParty: _selected,
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onDone();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Who is responsible?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 6),
          Text(
            'Choose who caused this issue. The relevant party will be notified.',
            style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.5), height: 1.5),
          ),
          const SizedBox(height: 24),
          ..._responsibilityOptions.map((r) => _OptionTile(
            r: r, selected: _selected == r.value,
            onTap: () => setState(() => _selected = r.value),
          )),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: AnimatedOpacity(
                opacity: _selected != null ? 1.0 : 0.4,
                duration: const Duration(milliseconds: 200),
                child: ElevatedButton(
                  onPressed: _selected != null && !_saving ? _confirm : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22C55E),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Confirm & Send', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final _Responsibility r;
  final bool selected;
  final VoidCallback onTap;
  const _OptionTile({required this.r, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? r.color.withOpacity(0.12) : Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? r.color.withOpacity(0.5) : Colors.white.withOpacity(0.08)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: r.color.withOpacity(0.15), shape: BoxShape.circle),
              child: Icon(r.icon, size: 18, color: r.color),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(r.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white))),
            if (selected)
              Icon(Icons.check_circle_rounded, color: r.color, size: 22),
          ]),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Reusable widgets
// ═══════════════════════════════════════════════════════════════════════════════

class _StatusBanner extends StatelessWidget {
  final Map<String, dynamic> data;
  const _StatusBanner({required this.data});

  @override
  Widget build(BuildContext context) {
    final status = data['status']?.toString() ?? 'PENDING';
    final sc = _statusColor(status);
    final type = _fmtType(data['complaint_type']?.toString() ?? '');
    final subType = data['sub_type']?.toString() ?? '';
    final responsible = data['responsible_party']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: sc.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: sc.withOpacity(0.25)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(color: sc.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
          child: Text(status, style: TextStyle(fontWeight: FontWeight.bold, color: sc, fontSize: 13)),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(type, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          if (subType.isNotEmpty) Text(subType, style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.55))),
        ])),
        if (responsible.isNotEmpty)
          _ResponsibleBadge(party: responsible),
      ]),
    );
  }
}

class _ResponsibleBadge extends StatelessWidget {
  final String party;
  const _ResponsibleBadge({required this.party});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: Colors.purple.withOpacity(0.15), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.purpleAccent.withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.gavel_rounded, size: 13, color: Colors.purpleAccent),
        const SizedBox(width: 6),
        Text(_fmtParty(party), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.purpleAccent)),
      ]),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final List<(String, String)> rows;
  const _InfoCard({required this.icon, required this.color, required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)), child: Icon(icon, size: 16, color: color)),
          const SizedBox(width: 10),
          Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        ]),
        const SizedBox(height: 14),
        ...rows.map(((String, String) r) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 60, child: Text(r.$1, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.4)))),
            const SizedBox(width: 8),
            Expanded(child: Text(r.$2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white))),
          ]),
        )),
      ]),
    );
  }
}

class _OrderItemsSection extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final String currency;
  const _OrderItemsSection({required this.items, this.currency = 'SAR'});

  String _fullImg(String raw) {
    if (raw.isEmpty) return '';
    if (raw.startsWith('http')) return raw;
    return '${ApiConfig.baseHost}$raw';
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionTitle('Order Items'),
      const SizedBox(height: 12),
      Container(
        decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: _kBorder)),
        child: Column(children: items.asMap().entries.map((e) {
          final i = e.key; final item = e.value;
          final name  = item['product_name']?.toString() ?? 'Product';
          final desc  = item['product_description']?.toString() ?? '';
          final img   = _fullImg(item['product_image']?.toString() ?? '');
          final price = item['price']?.toString() ?? '—';
          final qty   = item['quantity']?.toString() ?? '1';
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: i < items.length - 1 ? Border(bottom: BorderSide(color: Colors.white.withOpacity(0.06))) : null,
            ),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: img.isNotEmpty
                    ? Image.network(img, width: 56, height: 56, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _imgPlaceholder())
                    : _imgPlaceholder(),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                if (desc.isNotEmpty) Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.45))),
              ])),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('$price $currency', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                Text('×$qty', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.4))),
              ]),
            ]),
          );
        }).toList()),
      ),
    ]);
  }

  Widget _imgPlaceholder() => Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(10)), child: Icon(Icons.image_outlined, size: 24, color: Colors.white.withOpacity(0.2)));
}

class _ComplaintSection extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ComplaintSection({required this.data});

  @override
  Widget build(BuildContext context) {
    final desc = data['description']?.toString() ?? '';
    final total = data['total_price']?.toString() ?? '—';
    final currency = data['currency']?.toString() ?? 'SAR';
    final payment = data['payment_method']?.toString() ?? '—';
    final shipping = data['shipping_address']?.toString() ?? '—';
    final createdAt = _fmtDate(data['created_at']?.toString() ?? '');

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionTitle('Complaint Details'),
      const SizedBox(height: 12),
      Container(
        decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: _kBorder)),
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 24, runSpacing: 12, children: [
            _kv('Total',        '$total $currency'),
            _kv('Payment',      payment),
            _kv('Submitted',    createdAt),
            _kv('Ship Address', shipping),
          ]),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Customer Description', style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.4), letterSpacing: 0.5)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(10)),
              child: Text(desc, style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.8), height: 1.5)),
            ),
          ],
        ]),
      ),
    ]);
  }

  Widget _kv(String k, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(k, style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.35), letterSpacing: 0.5)),
    const SizedBox(height: 2),
    Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
  ]);
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.4), letterSpacing: 1.2),
  );
}

class _Btn extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final bool loading;
  final VoidCallback onTap;
  const _Btn({required this.label, required this.color, required this.icon, required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: loading ? null : onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (loading)
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: color))
        else
          Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
      ]),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Store Complaints View (for store panel)
// ═══════════════════════════════════════════════════════════════════════════════

class StoreComplaintsView extends StatefulWidget {
  final int storeId;
  const StoreComplaintsView({Key? key, required this.storeId}) : super(key: key);

  @override
  State<StoreComplaintsView> createState() => _StoreComplaintsViewState();
}

class _StoreComplaintsViewState extends State<StoreComplaintsView> {
  List<Map<String, dynamic>> _complaints = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      _complaints = await ApiService.getStoreComplaints(widget.storeId);
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        title: const Text('Customer Complaints', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: Colors.white,
        backgroundColor: _kBg,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54))
            : _complaints.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.sentiment_satisfied_alt_outlined, size: 64, color: Colors.white.withOpacity(0.1)),
                      const SizedBox(height: 16),
                      const Text('No complaints', style: TextStyle(color: Colors.white54, fontSize: 18)),
                    ]),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: _complaints.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _StoreComplaintCard(data: _complaints[i]),
                    ),
                  ),
      ),
    );
  }
}

class _StoreComplaintCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _StoreComplaintCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final status      = data['status']?.toString() ?? 'PENDING';
    final orderId     = data['order_id']?.toString() ?? '—';
    final type        = _fmtType(data['complaint_type']?.toString() ?? '');
    final description = data['description']?.toString() ?? '';
    final adminNotes  = data['admin_notes']?.toString() ?? '';
    final customerName = data['customer_name']?.toString() ?? '—';
    final createdAt   = _fmtDate(data['created_at']?.toString() ?? '');
    final items       = List<Map<String, dynamic>>.from(data['order_items'] ?? []);
    final currency    = data['currency']?.toString() ?? 'SAR';
    final sc          = _statusColor(status);

    return Container(
      decoration: BoxDecoration(
        color: _kCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: _kBorder),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: sc.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
            child: Text(status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: sc)),
          ),
          const SizedBox(width: 10),
          Text('Order #$orderId', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
          const Spacer(),
          Text(createdAt, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.35))),
        ]),
        const SizedBox(height: 12),
        // Product list (compact)
        if (items.isNotEmpty) ...[
          ...items.take(2).map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: () {
                  final raw = item['product_image']?.toString() ?? '';
                  final url = raw.isEmpty ? '' : (raw.startsWith('http') ? raw : '${ApiConfig.baseHost}$raw');
                  return url.isNotEmpty
                      ? Image.network(url, width: 36, height: 36, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _miniPlaceholder())
                      : _miniPlaceholder();
                }(),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(item['product_name']?.toString() ?? 'Product', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white))),
              Text('${item['price'] ?? '—'} $currency ×${item['quantity'] ?? 1}', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5))),
            ]),
          )),
          if (items.length > 2) Text('+${items.length - 2} more', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.3))),
          const SizedBox(height: 8),
        ],
        // Customer name
        Row(children: [
          Icon(Icons.person_outline_rounded, size: 13, color: Colors.white.withOpacity(0.4)),
          const SizedBox(width: 4),
          Text('Customer: $customerName — Issue: $type', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6))),
        ]),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(description, style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.75), height: 1.4)),
        ],
        // Admin response
        if (adminNotes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.amber.withOpacity(0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.amber.withOpacity(0.2))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.shield_outlined, size: 14, color: Colors.amber),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('YShop Admin Response', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber)),
                const SizedBox(height: 4),
                Text(adminNotes, style: TextStyle(fontSize: 12, color: Colors.amber.withOpacity(0.8), height: 1.4)),
              ])),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _miniPlaceholder() => Container(width: 36, height: 36, decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(6)));
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Shared helpers
// ═══════════════════════════════════════════════════════════════════════════════

Color _statusColor(String s) {
  switch (s) {
    case 'APPROVED':     return Colors.green;
    case 'REJECTED':     return const Color(0xFFEF4444);
    case 'UNDER_REVIEW': return const Color(0xFF3B82F6);
    default:             return Colors.orange;
  }
}

String _fmtType(String raw) => raw.replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

String _fmtDate(String raw) {
  if (raw.isEmpty) return '—';
  try {
    final dt = DateTime.parse(raw).toLocal();
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  } catch (_) { return raw; }
}

String _fmtParty(String raw) {
  switch (raw) {
    case 'platform':        return 'YShop';
    case 'store':           return 'Store';
    case 'driver':          return 'Driver';
    case 'platform_store':  return 'YShop + Store';
    case 'platform_driver': return 'YShop + Driver';
    case 'store_driver':    return 'Store + Driver';
    default:                return raw;
  }
}
