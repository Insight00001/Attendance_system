import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/leave_model.dart';
import '../../services/leave_service.dart';
import '../../services/api_service.dart';
import '../../themes/app_theme.dart';

const _leaveTypeOptions = [
  ('annual',    'Annual Leave'),
  ('sick',      'Sick Leave'),
  ('emergency', 'Emergency'),
  ('unpaid',    'Unpaid Leave'),
  ('absence',   'Absence'),
  ('other',     'Other'),
];

class MyLeaveScreen extends StatefulWidget {
  const MyLeaveScreen({super.key});
  @override
  State<MyLeaveScreen> createState() => _MyLeaveScreenState();
}

class _MyLeaveScreenState extends State<MyLeaveScreen> {
  final _service    = LeaveService(ApiService());
  List<LeaveRequest> _leaves = [];
  bool _loading              = false;
  DateTime? _startDate;
  DateTime? _endDate;
  String _leaveType          = 'annual';
  final _reasonCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLeaves();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLeaves() async {
    setState(() => _loading = true);
    try {
      final leaves = await _service.getMyLeaves();
      if (mounted) setState(() => _leaves = leaves);
    } catch (e) {
      _showError(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(String? d) {
    if (d == null) return '-';
    try { return DateFormat('d MMM yyyy').format(DateTime.parse(d)); }
    catch (_) { return d; }
  }

  Color _statusColor(String s) => switch (s) {
    'approved'  => AppTheme.accentGreen,
    'rejected'  => AppTheme.accentRed,
    'cancelled' => Colors.grey,
    _           => AppTheme.accentOrange,
  };

  void _showApplySheet() {
    _startDate = null;
    _endDate   = null;
    _leaveType = 'annual';
    _reasonCtrl.clear();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardTheme.color ?? Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSS) => Padding(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              )),
              const SizedBox(height: 20),
              const Text('Apply for Leave',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),

              // Leave type
              const Text('Leave Type',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _leaveType,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.category_outlined),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                items: _leaveTypeOptions.map((t) => DropdownMenuItem(
                  value: t.$1,
                  child: Text(t.$2),
                )).toList(),
                onChanged: (v) => setSS(() => _leaveType = v ?? 'annual'),
              ),
              const SizedBox(height: 16),

              // Start date
              _DateTile(
                label: 'Start Date',
                value: _startDate,
                onTap: () async {
                  final p = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now().add(const Duration(days: 1)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (p != null) setSS(() {
                    _startDate = p;
                    if (_endDate != null && _endDate!.isBefore(p)) _endDate = p;
                  });
                },
              ),
              const SizedBox(height: 12),

              // End date
              _DateTile(
                label: 'End Date',
                value: _endDate,
                onTap: () async {
                  final p = await showDatePicker(
                    context: ctx,
                    initialDate: _startDate ?? DateTime.now().add(const Duration(days: 1)),
                    firstDate: _startDate ?? DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (p != null) setSS(() => _endDate = p);
                },
              ),

              // Duration
              if (_startDate != null && _endDate != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    const Icon(Icons.info_outline, size: 16, color: AppTheme.primaryBlue),
                    const SizedBox(width: 8),
                    Text(
                      '${_endDate!.difference(_startDate!).inDays + 1} day(s) selected',
                      style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.w600),
                    ),
                  ]),
                ),
              ],
              const SizedBox(height: 16),

              // Reason
              TextField(
                controller: _reasonCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Reason (optional)',
                  hintText: 'e.g. Medical appointment, family event...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 20),

              // Submit
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () async {
                    if (_startDate == null || _endDate == null) {
                      _showError('Please select start and end dates');
                      return;
                    }
                    try {
                      await _service.applyLeave(
                        startDate: DateFormat('yyyy-MM-dd').format(_startDate!),
                        endDate:   DateFormat('yyyy-MM-dd').format(_endDate!),
                        reason:    _reasonCtrl.text.trim(),
                        leaveType: _leaveType,
                      );
                      Navigator.of(sheetCtx).pop();
                      _showSuccess('Leave request submitted');
                      _loadLeaves();
                    } catch (e) {
                      _showError(apiErrorMessage(e));
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Submit Leave Request',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _cancelLeave(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Cancel Leave'),
        content: const Text('Cancel this leave request?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('No')),
          ElevatedButton(
            onPressed: () => Navigator.of(d).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentRed),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.cancelLeave(id);
      _showSuccess('Leave cancelled');
      _loadLeaves();
    } catch (e) {
      _showError(apiErrorMessage(e));
    }
  }

  void _showSuccess(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: AppTheme.accentGreen));
  }

  void _showError(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: AppTheme.accentRed));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Leave'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadLeaves),
        ],
      ),
      body: Column(children: [
        // ── Stats bar ─────────────────────────────────────────
        if (_leaves.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(children: [
              _StatChip(
                label: 'Pending',
                count: _leaves.where((l) => l.status == 'pending').length,
                color: AppTheme.accentOrange,
              ),
              const SizedBox(width: 8),
              _StatChip(
                label: 'Approved',
                count: _leaves.where((l) => l.status == 'approved').length,
                color: AppTheme.accentGreen,
              ),
              const SizedBox(width: 8),
              _StatChip(
                label: 'Days taken',
                count: _leaves
                    .where((l) => l.status == 'approved')
                    .fold(0, (sum, l) => sum + l.daysCount),
                color: AppTheme.primaryBlue,
              ),
            ]),
          ),

        // ── Apply button — always visible ─────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _showApplySheet,
              icon: const Icon(Icons.add),
              label: const Text('Apply for Leave'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ),

        // ── Leave history ─────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadLeaves,
                  child: _leaves.isEmpty
                      ? ListView(children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.4,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.event_available_outlined,
                                    size: 64, color: Colors.grey[300]),
                                const SizedBox(height: 16),
                                Text('No leave requests yet',
                                    style: TextStyle(color: Colors.grey[500])),
                                const SizedBox(height: 8),
                                Text(
                                  'Tap "Apply for Leave" above to get started',
                                  style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ])
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: _leaves.length,
                          itemBuilder: (_, i) {
                            final l     = _leaves[i];
                            final color = _statusColor(l.status);
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: color.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(l.status.toUpperCase(),
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: color)),
                                      ),
                                      const Spacer(),
                                      Text(
                                        '${l.daysCount} day${l.daysCount > 1 ? "s" : ""}',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.primaryBlue,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ]),
                                    const SizedBox(height: 10),
                                    Row(children: [
                                      const Icon(Icons.calendar_today_outlined,
                                          size: 16, color: Color(0xFF94A3B8)),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${_fmt(l.startDate)}  →  ${_fmt(l.endDate)}',
                                        style: const TextStyle(
                                            fontSize: 14, fontWeight: FontWeight.w500),
                                      ),
                                    ]),
                                    if (l.reason != null && l.reason!.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(l.reason!,
                                          style: const TextStyle(
                                              fontSize: 13, color: Color(0xFF64748B))),
                                    ],
                                    const SizedBox(height: 6),
                                    Text('Applied: ${_fmt(l.createdAt)}',
                                        style: const TextStyle(
                                            fontSize: 11, color: Color(0xFF94A3B8))),
                                    const SizedBox(height: 4),
                                    // Leave type badge
                                    Row(children: [
                                      const Icon(Icons.category_outlined,
                                          size: 14, color: Color(0xFF94A3B8)),
                                      const SizedBox(width: 4),
                                      Text(l.leaveTypeLabel,
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF64748B))),
                                    ]),
                                    if (l.status == 'pending') ...[
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        width: double.infinity,
                                        child: OutlinedButton.icon(
                                          onPressed: () => _cancelLeave(l.id),
                                          icon: const Icon(Icons.close, size: 16),
                                          label: const Text('Cancel Request'),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: AppTheme.accentRed,
                                            side: const BorderSide(color: AppTheme.accentRed),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
        ),
      ]),
    );
  }
}

// ── Stat Chip ──────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _StatChip({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(children: [
          Text('$count',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: 11, color: color.withOpacity(0.8))),
        ]),
      ),
    );
  }
}

// ── Date Picker Tile ───────────────────────────────────────────

class _DateTile extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  const _DateTile({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(
              color: value != null ? AppTheme.primaryBlue : Colors.grey[400]!),
          borderRadius: BorderRadius.circular(10),
          color: value != null ? AppTheme.primaryBlue.withOpacity(0.05) : null,
        ),
        child: Row(children: [
          Icon(Icons.calendar_today_outlined, size: 18,
              color: value != null ? AppTheme.primaryBlue : Colors.grey[500]),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: value != null ? AppTheme.primaryBlue : Colors.grey[500])),
            Text(
              value != null
                  ? DateFormat('EEEE, d MMMM yyyy').format(value!)
                  : 'Tap to select',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: value != null ? FontWeight.w600 : FontWeight.normal,
                  color: value != null ? null : Colors.grey[500]),
            ),
          ]),
          const Spacer(),
          Icon(Icons.arrow_drop_down,
              color: value != null ? AppTheme.primaryBlue : Colors.grey[400]),
        ]),
      ),
    );
  }
}