// lib/screens/delivery_requests_view.dart

import 'package:flutter/material.dart';
import 'admin/common.dart';
import 'admin/widgets.dart' as admin_widgets;
import '../../services/api_service.dart';
import '../../services/reactive_sync_mixin.dart';
import 'dart:async';

// --------------------------------------------------
// MARK: - Delivery Requests View
// --------------------------------------------------

class DeliveryRequestsView extends StatefulWidget {
  const DeliveryRequestsView({super.key});

  @override
  State<DeliveryRequestsView> createState() => _DeliveryRequestsViewState();
}

class _DeliveryRequestsViewState extends State<DeliveryRequestsView> with ReactiveSyncMixin {
  // مفتاح لتحديث محتوى StreamBuilder
  Key _deliveryRequestKey = UniqueKey();
  bool _loading = true;
  List<DeliveryRequest> _requests = [];
  Timer? _pollTimer;

  @override
  String get reactiveChannel => 'admin:delivery:requests';

  @override
  void onReactiveUpdate(Map<String, dynamic> update) {
    final newData = (update['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    
    if (mounted) {
      setState(() {
        _requests = newData.map<DeliveryRequest>((d) => DeliveryRequest.fromMap(d)).toList();
      });
    }
  }

  void _refreshData() {
    _loadRequests();
  }

  // --------------------------------------------------
  // MARK: - Actions (قبول، رفض، تعليق)
  // --------------------------------------------------

  //  تحديث حالة طلب الموصل
  void _updateDriverStatus(DeliveryRequest request, String status) async {
    try {
      if (status == 'Rejected') {
        await ApiService.rejectDeliveryRequest(request.id);
      } else if (status == 'Approved') {
        await ApiService.approveDeliveryRequest(request.id);
      } else {
        // No server endpoint for revert-to-pending; refresh list instead
      }
      _loadRequests();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update status: $e')),
      );
    }
  }

  Future<void> _loadRequests() async {
    setState(() {
      _loading = true;
    });
    try {
      final data = await ApiService.getPendingDeliveryRequests();
      // data is list of maps from backend; convert to DeliveryRequest
      _requests = data.map<DeliveryRequest>((d) => DeliveryRequest.fromMap(d)).toList();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load: $e')));
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadRequests();
    // 🔥 Reactive Sync via Mixin - no polling needed!
  }

  @override
  void dispose() {
    // Polling timer cancelled by Mixin
    super.dispose();
  }

  // --------------------------------------------------
  // MARK: - Build Method
  // --------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDarkBackground,
      appBar: AppBar(
        title: const Text('Manage Driver Requests', style: TextStyle(color: kPrimaryTextColor)),
        backgroundColor: kAppBarBackground,
        foregroundColor: kPrimaryTextColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white), 
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _refreshData,
          ),
        ],
      ),
      body: _buildRequestStream(context),
    );
  }
  
  // --------------------------------------------------
  // MARK: - Firebase Stream
  // --------------------------------------------------

  Widget _buildRequestStream(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kAccentBlue));
    }

    if (_requests.isEmpty) {
      return Center(
        child: admin_widgets.EmptyStateView(
          icon: Icons.motorcycle,
          title: "No Driver Requests",
          message: "There are no pending or active driver requests.",
        ),
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      final crossAxis = constraints.maxWidth > 900 ? 3 : (constraints.maxWidth > 600 ? 2 : 1);
      return GridView.count(
        padding: const EdgeInsets.all(16.0),
        crossAxisCount: crossAxis,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.25,
        children: _requests.map((request) {
          return _DriverRequestCard(
            request: request,
            onApprove: () async {
              try {
                await ApiService.approveDeliveryRequest(request.id);
                await _loadRequests();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Approve failed: $e')));
              }
            },
            onReject: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Delete driver?'),
                  content: Text('Are you sure you want to delete ${request.name}?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes, delete')),
                  ],
                ),
              );
              if (ok == true) {
                try {
                  await ApiService.deleteDeliveryRequest(request.id);
                  await _loadRequests();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
                }
              }
            },
            onRevert: () async {
              try {
                await ApiService.setDeliveryRequestPending(request.id);
                await _loadRequests();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Set pending failed: $e')));
              }
            },
          );
        }).toList(),
      );
    });
  }
}

// --------------------------------------------------
// MARK: - Nested Component: Driver Card
// --------------------------------------------------

class _DriverRequestCard extends StatelessWidget {
  final DeliveryRequest request;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onRevert;

  const _DriverRequestCard({
    required this.request,
    required this.onApprove,
    required this.onReject,
    required this.onRevert,
  });

  @override
  Widget build(BuildContext context) {
    final isApproved = request.status == "Approved";
    
    return Card(
      color: kCardBackground,
      elevation: 5,
      margin: const EdgeInsets.only(bottom: 16.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. العنوان والحالة
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  request.name,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold, color: kPrimaryTextColor),
                ),
                admin_widgets.StatusBadgeView(status: request.status),
              ],
            ),
            const Divider(color: kSeparatorColor, height: 20),

            // 2. التفاصيل الأساسية
            _DetailRow(label: "Email", value: request.email),
            _DetailRow(label: "Phone", value: request.phoneNumber),
            _DetailRow(label: "National ID", value: request.nationalID),
            _DetailRow(label: "Address", value: request.address, isMultiline: true),

            const Divider(color: kSeparatorColor, height: 20),

            // 3. أزرار الإجراءات
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // زر الرفض (Reject)
                _ActionButton(
                  label: "Reject",
                  color: Colors.red,
                  onPressed: onReject,
                ),
                const SizedBox(width: 8),
                
                // زر إعادة التعليق/القبول
                if (isApproved)
                  _ActionButton(
                    label: "Pending",
                    color: Colors.orange,
                    onPressed: onRevert,
                  )
                else
                  _ActionButton(
                    label: "Approve",
                    color: Colors.green,
                    onPressed: onApprove,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------
// MARK: - Shared Utility Widgets (Add these if missing)
// --------------------------------------------------

// يجب إضافة هذه الودجتس في admin_home_view.dart إذا لم تكن موجودة بعد
// وإلا، يجب استيرادها من ملف آخر مشترك. سنضيفها هنا للتوثيق.

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isMultiline;
  final TextAlign valueAlignment;

  const _DetailRow({
    required this.label,
    required this.value,
    this.isMultiline = false,
    this.valueAlignment = TextAlign.left,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: isMultiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              "$label:",
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: kSecondaryTextColor, fontSize: 14),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: valueAlignment,
              style: const TextStyle(color: kPrimaryTextColor, fontSize: 14),
              maxLines: isMultiline ? 10 : 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        backgroundColor: color.withOpacity(0.1),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }
}
