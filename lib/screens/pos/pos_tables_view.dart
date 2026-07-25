// pos_tables_view.dart — Table management + QR code generation
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/pos_models.dart';
import '../../services/pos_service.dart';

class POSTablesView extends StatefulWidget {
  final int storeId;
  const POSTablesView({super.key, required this.storeId});

  @override
  State<POSTablesView> createState() => _POSTablesViewState();
}

class _POSTablesViewState extends State<POSTablesView> {
  final _pos = POSService();
  List<POSTable> _tables = [];
  bool _loading = true;
  StreamSubscription? _tableSub;

  @override
  void initState() {
    super.initState();
    _pos.joinStoreRoom(widget.storeId);
    _tableSub = _pos.tableStream.listen(_onTableEvent);
    _load();
  }

  @override
  void dispose() {
    _tableSub?.cancel();
    super.dispose();
  }

  void _onTableEvent(Map<String, dynamic> data) {
    final action = data['action'] as String?;
    final tableData = data['table'];
    final tableId = data['tableId'];
    if (!mounted) return;

    setState(() {
      if (action == 'deleted' && tableId != null) {
        _tables.removeWhere((t) => t.id == tableId);
      } else if (tableData != null) {
        final updated = POSTable.fromJson(Map<String, dynamic>.from(tableData));
        final idx = _tables.indexWhere((t) => t.id == updated.id);
        if (idx >= 0) {
          _tables[idx] = updated;
        } else if (action == 'created') {
          _tables.add(updated);
          _tables.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        }
      }
    });
  }

  Future<void> _load() async {
    try {
      final tables = await _pos.getTables(widget.storeId);
      if (mounted) setState(() { _tables = tables; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addTable() async {
    final nameCtrl = TextEditingController();
    final capCtrl = TextEditingController(text: '4');
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Table'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Table Name', hintText: 'e.g. Table 1')),
          const SizedBox(height: 12),
          TextField(controller: capCtrl, decoration: const InputDecoration(labelText: 'Capacity'), keyboardType: TextInputType.number),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (res == true && nameCtrl.text.trim().isNotEmpty) {
      try {
        await _pos.createTable(widget.storeId, nameCtrl.text.trim(),
            capacity: int.tryParse(capCtrl.text) ?? 4);
      } catch (e) {
        if (mounted) _showError(e.toString());
      }
    }
  }

  Future<void> _editTable(POSTable table) async {
    final nameCtrl = TextEditingController(text: table.name);
    final capCtrl = TextEditingController(text: table.capacity.toString());
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Edit ${table.name}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Table Name')),
          const SizedBox(height: 12),
          TextField(controller: capCtrl, decoration: const InputDecoration(labelText: 'Capacity'), keyboardType: TextInputType.number),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (res == true) {
      try {
        await _pos.updateTable(table.id,
          name: nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : null,
          capacity: int.tryParse(capCtrl.text));
      } catch (e) {
        if (mounted) _showError(e.toString());
      }
    }
  }

  Future<void> _deleteTable(POSTable table) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete ${table.name}?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _pos.deleteTable(table.id);
      } catch (e) {
        if (mounted) _showError(e.toString());
      }
    }
  }

  void _showQR(POSTable table) {
    final url = _pos.tableQrUrl(table);
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(table.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Scan to track order', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            const SizedBox(height: 16),
            QrImageView(data: url, version: QrVersions.auto, size: 200),
            const SizedBox(height: 12),
            Text(url, style: TextStyle(fontSize: 11, color: Colors.grey[500]), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.open_in_browser, size: 16),
                label: const Text('Open'),
                onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'available': return Colors.green;
      case 'occupied': return Colors.blue;
      case 'preparing': return Colors.orange;
      case 'waiting_payment': return Colors.purple;
      case 'disabled': return Colors.grey;
      default: return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'available': return 'Available';
      case 'occupied': return 'Occupied';
      case 'preparing': return 'Preparing';
      case 'waiting_payment': return 'Bill Ready';
      case 'disabled': return 'Disabled';
      default: return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Tables'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addTable,
        icon: const Icon(Icons.add),
        label: const Text('Add Table'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tables.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.table_restaurant, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    Text('No tables yet', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                    const SizedBox(height: 8),
                    Text('Tap + to add your first table', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                  ]),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisExtent: 160,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: _tables.length,
                  itemBuilder: (_, i) => _TableCard(
                    table: _tables[i],
                    statusColor: _statusColor(_tables[i].status),
                    statusLabel: _statusLabel(_tables[i].status),
                    onEdit: () => _editTable(_tables[i]),
                    onDelete: () => _deleteTable(_tables[i]),
                    onQR: () => _showQR(_tables[i]),
                  ),
                ),
    );
  }
}

class _TableCard extends StatelessWidget {
  final POSTable table;
  final Color statusColor;
  final String statusLabel;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onQR;

  const _TableCard({
    required this.table,
    required this.statusColor,
    required this.statusLabel,
    required this.onEdit,
    required this.onDelete,
    required this.onQR,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withAlpha(80), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(12), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Stack(children: [
        // Status dot
        Positioned(top: 10, right: 10,
          child: Container(width: 10, height: 10,
            decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
        ),
        Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.table_restaurant, size: 36),
          const SizedBox(height: 8),
          Text(table.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: statusColor.withAlpha(25), borderRadius: BorderRadius.circular(20)),
            child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _IconBtn(icon: Icons.edit_outlined, onTap: onEdit),
            _IconBtn(icon: Icons.qr_code, onTap: onQR),
            _IconBtn(icon: Icons.delete_outline, onTap: onDelete, color: Colors.red),
          ]),
        ]),
      ]),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  const _IconBtn({required this.icon, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Icon(icon, size: 18, color: color ?? Colors.grey[600]),
    ),
  );
}
