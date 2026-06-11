import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/leave_model.dart';
import '../../models/models.dart';
import '../../services/leave_service.dart';
import '../../services/api_service.dart';
import '../../themes/app_theme.dart';
import '../../widgets/common/loading_overlay.dart';

const _adminLeaveTypeOptions = [
  ('annual',    'Annual Leave'),
  ('sick',      'Sick Leave'),
  ('emergency', 'Emergency'),
  ('unpaid',    'Unpaid Leave'),
  ('absence',   'Absence'),
  ('other',     'Other'),
];

class LeaveManagementScreen extends StatefulWidget {
  const LeaveManagementScreen({super.key});
  @override
  State<LeaveManagementScreen> createState() => _LeaveManagementScreenState();
}

class _LeaveManagementScreenState extends State<LeaveManagementScreen> {
  late final LeaveService _service = LeaveService(ApiService());
  final ApiService _api = ApiService();

  List<LeaveRequest> _all      = [];
  List<EmployeeModel> _employees = [];
  bool _loading = false;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<LeaveRequest> get _filtered {
    if (_searchQuery.isEmpty) return _all;
    final q = _searchQuery.toLowerCase();
    return _all.where((l) =>
      (l.employeeName?.toLowerCase().contains(q) ?? false) ||
      (l.empCode?.toLowerCase().contains(q) ?? false) ||
      (l.department?.toLowerCase().contains(q) ?? false)
    ).toList();
  }

  int get _pendingCount => _all.where((l) => l.status == 'pending').length;

  Future<void> _load() async {
    setState(() => _loading = true);
    _loadEmployees();
    try {
      final result = await _service.getAllLeaves();   // no status filter → all
      if (mounted) {
        setState(() {
          _all = (result['leaves'] as List<LeaveRequest>);
        });
      }
    } catch (e) {
      _showError(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadEmployees() async {
    try {
      final resp = await _api.get(
          '/employees', params: {'status': 'active', 'per_page': '200'});
      if (!mounted) return;
      final empData = (resp.data as Map<String, dynamic>);
      setState(() {
        _employees = ((empData['employees'] ?? empData['data']) as List)
            .map((e) => EmployeeModel.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    } catch (e) {
      // Non-fatal — admin can retry with the refresh button
      if (mounted) _showError('Could not load employee list: ${apiErrorMessage(e)}');
    }
  }

  Future<void> _review(LeaveRequest leave, String status) async {
    final action = status == 'approved' ? 'Approve' : 'Reject';
    final color  = status == 'approved' ? AppTheme.accentGreen : AppTheme.accentRed;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('$action Leave?'),
        content: Text(
          '$action leave for ${leave.employeeName ?? "this employee"} '
          '(${leave.startDate} → ${leave.endDate})?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(d).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: color),
            child: Text(action),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.reviewLeave(leave.id, status);
      _showSuccess('Leave request $status');
      _load();
    } catch (e) {
      _showError(apiErrorMessage(e));
    }
  }

  // ── Admin submit leave on behalf of employee ───────────────

  void _showAddLeaveSheet() {
    String? selectedEmployeeId;
    DateTime? startDate;
    DateTime? endDate;
    String selectedLeaveType = 'annual';
    final reasonCtrl = TextEditingController();

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
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                )),
                const SizedBox(height: 20),

                const Text('Submit Leave Request',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('Enter leave on behalf of an employee',
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                const SizedBox(height: 20),

                // ── Leave type ─────────────────────────────
                const Text('Leave Type',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedLeaveType,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.category_outlined),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  items: _adminLeaveTypeOptions.map((t) => DropdownMenuItem(
                    value: t.$1,
                    child: Text(t.$2),
                  )).toList(),
                  onChanged: (v) => setSS(() => selectedLeaveType = v ?? 'annual'),
                ),
                const SizedBox(height: 16),

                // ── Employee selector ──────────────────────
                const Text('Employee',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (_employees.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.withOpacity(0.4)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.orange, size: 18),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text('Employee list not loaded yet.',
                            style: TextStyle(fontSize: 13)),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _loadEmployees().then((_) => _showAddLeaveSheet());
                        },
                        child: const Text('Retry'),
                      ),
                    ]),
                  )
                else
                  DropdownButtonFormField<String>(
                    value: selectedEmployeeId,
                    hint: const Text('Select employee'),
                    isExpanded: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    items: _employees.map((e) => DropdownMenuItem(
                      value: e.id,
                      child: Text(
                        '${e.fullName}  (${e.employeeId})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    )).toList(),
                    onChanged: (v) => setSS(() => selectedEmployeeId = v),
                  ),
                const SizedBox(height: 16),

                // ── Start date ─────────────────────────────
                const Text('Start Date',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                _AdminDateTile(
                  value: startDate,
                  hint: 'Select start date',
                  onTap: () async {
                    final p = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (p != null) {
                      setSS(() {
                      startDate = p;
                      if (endDate != null && endDate!.isBefore(p)) {
                        endDate = p;
                      }
                    });
                    }
                  },
                ),
                const SizedBox(height: 16),

                // ── End date ───────────────────────────────
                const Text('End Date',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                _AdminDateTile(
                  value: endDate,
                  hint: 'Select end date',
                  onTap: () async {
                    final p = await showDatePicker(
                      context: ctx,
                      initialDate: startDate ?? DateTime.now(),
                      firstDate: startDate ?? DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (p != null) setSS(() => endDate = p);
                  },
                ),

                // Duration badge
                if (startDate != null && endDate != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      const Icon(Icons.info_outline,
                          size: 16, color: AppTheme.primaryBlue),
                      const SizedBox(width: 8),
                      Text(
                        '${endDate!.difference(startDate!).inDays + 1} day(s)',
                        style: const TextStyle(
                            color: AppTheme.primaryBlue,
                            fontWeight: FontWeight.w600),
                      ),
                    ]),
                  ),
                ],
                const SizedBox(height: 16),

                // ── Reason ─────────────────────────────────
                const Text('Reason',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: reasonCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'e.g. Annual leave, medical, family event...',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 24),

                // ── Submit ─────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Submit & Auto-Approve',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    onPressed: () async {
                      if (selectedEmployeeId == null) {
                        _showError('Please select an employee');
                        return;
                      }
                      if (startDate == null || endDate == null) {
                        _showError('Please select start and end dates');
                        return;
                      }
                      Navigator.of(sheetCtx).pop();
                      await _adminSubmitLeave(
                        employeeId: selectedEmployeeId!,
                        startDate:  startDate!,
                        endDate:    endDate!,
                        reason:     reasonCtrl.text.trim(),
                        leaveType:  selectedLeaveType,
                      );
                      reasonCtrl.dispose();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentGreen,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _adminSubmitLeave({
    required String employeeId,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
    required String leaveType,
  }) async {
    try {
      // Submit via backend admin endpoint
      final resp = await _api.post('/leave/admin-submit', data: {
        'employee_id': employeeId,
        'start_date':  DateFormat('yyyy-MM-dd').format(startDate),
        'end_date':    DateFormat('yyyy-MM-dd').format(endDate),
        'reason':      reason,
        'leave_type':  leaveType,
      });
      _showSuccess('Leave submitted and approved for employee');
      _load();
    } catch (e) {
      _showError(apiErrorMessage(e));
    }
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), backgroundColor: AppTheme.accentGreen));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), backgroundColor: AppTheme.accentRed));
  }

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: _loading,
      child: Scaffold(
        // ── AppBar ──────────────────────────────────────────
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Leave Requests',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              Text(
                '$_pendingCount pending approval',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: _load,
            ),
          ],
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search by name, ID or department...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => setState(
                              () { _searchCtrl.clear(); _searchQuery = ''; }),
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
              ),
            ),
          ),
        ),

        // ── FAB ───────────────────────────────────────────────
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showAddLeaveSheet,
          icon: const Icon(Icons.add),
          label: const Text('Add Leave'),
          backgroundColor: AppTheme.primaryBlue,
        ),

        body: _LeaveList(
          leaves: _filtered,
          showActions: true,
          onApprove: (l) => _review(l, 'approved'),
          onReject:  (l) => _review(l, 'rejected'),
        ),
      ),
    );
  }
}

// ── Leave List ─────────────────────────────────────────────────

class _LeaveList extends StatelessWidget {
  final List<LeaveRequest> leaves;
  final bool showActions;
  final void Function(LeaveRequest)? onApprove;
  final void Function(LeaveRequest)? onReject;

  const _LeaveList({
    required this.leaves,
    this.showActions = false,
    this.onApprove,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    if (leaves.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.event_available_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('No leave requests',
              style: TextStyle(color: Colors.grey[500])),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: leaves.length,
      itemBuilder: (_, i) => _LeaveCard(
        leave: leaves[i],
        showActions: showActions,
        onApprove: onApprove,
        onReject: onReject,
      ),
    );
  }
}

// ── Leave Card ─────────────────────────────────────────────────

class _LeaveCard extends StatelessWidget {
  final LeaveRequest leave;
  final bool showActions;
  final void Function(LeaveRequest)? onApprove;
  final void Function(LeaveRequest)? onReject;

  const _LeaveCard({
    required this.leave,
    this.showActions = false,
    this.onApprove,
    this.onReject,
  });

  Color get _statusColor => switch (leave.status) {
    'approved'  => AppTheme.accentGreen,
    'rejected'  => AppTheme.accentRed,
    'cancelled' => Colors.grey,
    _           => AppTheme.accentOrange,
  };

  String _fmt(String dateStr) {
    try { return DateFormat('d MMM yyyy').format(DateTime.parse(dateStr)); }
    catch (_) { return dateStr; }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Employee + status
          Row(children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppTheme.primaryBlue.withOpacity(0.1),
              child: Text(
                (leave.employeeName ?? '?')[0].toUpperCase(),
                style: const TextStyle(
                    color: AppTheme.primaryBlue, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(leave.employeeName ?? 'Unknown',
                    style: AppTextStyles.bodyMed),
                Text(
                  [
                    if (leave.department != null && leave.department!.isNotEmpty)
                      leave.department!,
                    leave.leaveTypeLabel,
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                ),
              ],
            )),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(leave.status.toUpperCase(),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _statusColor)),
            ),
          ]),
          const Divider(height: 20),

          // Dates + duration
          Row(children: [
            const Icon(Icons.calendar_today_outlined,
                size: 16, color: Color(0xFF94A3B8)),
            const SizedBox(width: 6),
            Text('${_fmt(leave.startDate)}  →  ${_fmt(leave.endDate)}',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${leave.daysCount} day${leave.daysCount > 1 ? "s" : ""}',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.primaryBlue,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ]),

          // Reason
          if (leave.reason != null && leave.reason!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.notes_outlined,
                  size: 16, color: Color(0xFF94A3B8)),
              const SizedBox(width: 6),
              Expanded(child: Text(leave.reason!,
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF64748B)))),
            ]),
          ],

          const SizedBox(height: 6),
          Text('Applied: ${_fmt(leave.createdAt)}',
              style: const TextStyle(
                  fontSize: 11, color: Color(0xFF94A3B8))),

          // Approve / Reject — only shown on pending cards
          if (showActions && leave.status == 'pending') ...[
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => onReject?.call(leave),
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Reject'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accentRed,
                    side: const BorderSide(color: AppTheme.accentRed),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => onApprove?.call(leave),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Approve'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentGreen),
                ),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}

// ── Upcoming Leave List ────────────────────────────────────────

class _UpcomingLeaveList extends StatelessWidget {
  final List<LeaveRequest> leaves;
  const _UpcomingLeaveList({required this.leaves});

  String _fmt(String dateStr) {
    try { return DateFormat('d MMM yyyy').format(DateTime.parse(dateStr)); }
    catch (_) { return dateStr; }
  }

  String _daysUntil(String startStr) {
    try {
      final start = DateTime.parse(startStr);
      final today = DateTime.now();
      final diff  = start.difference(DateTime(today.year, today.month, today.day)).inDays;
      if (diff == 0) return 'Today';
      if (diff == 1) return 'Tomorrow';
      return 'In $diff days';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (leaves.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.event_available_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('No upcoming leaves in the next 7 days',
              style: TextStyle(color: Colors.grey[500])),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: leaves.length,
      itemBuilder: (_, i) {
        final l     = leaves[i];
        final until = _daysUntil(l.startDate);
        final isToday    = until == 'Today';
        final isTomorrow = until == 'Tomorrow';
        final urgency    = isToday
            ? AppTheme.accentRed
            : isTomorrow
                ? AppTheme.accentOrange
                : AppTheme.primaryBlue;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: urgency.withOpacity(0.3), width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              // Countdown badge
              Container(
                width: 60,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: urgency.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(children: [
                  Text(until.split(' ').first,
                      style: TextStyle(
                          fontSize: isToday || isTomorrow ? 11 : 18,
                          fontWeight: FontWeight.w700,
                          color: urgency)),
                  if (!isToday && !isTomorrow)
                    Text('days',
                        style: TextStyle(fontSize: 10, color: urgency)),
                  if (isTomorrow)
                    Text('morrow',
                        style: TextStyle(fontSize: 9, color: urgency)),
                ]),
              ),
              const SizedBox(width: 14),

              // Details
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.employeeName ?? 'Unknown',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (l.department != null && l.department!.isNotEmpty) l.department!,
                      l.leaveTypeLabel,
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 14, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 4),
                    Text('${_fmt(l.startDate)} → ${_fmt(l.endDate)}',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w500)),
                    const SizedBox(width: 8),
                    Text('${l.daysCount}d',
                        style: TextStyle(
                            fontSize: 12,
                            color: urgency,
                            fontWeight: FontWeight.w600)),
                  ]),
                  if (l.reason != null && l.reason!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(l.reason!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF64748B))),
                  ],
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }
}

// ── Admin Date Tile ────────────────────────────────────────────

class _AdminDateTile extends StatelessWidget {
  final DateTime? value;
  final String hint;
  final VoidCallback onTap;

  const _AdminDateTile({
    required this.value,
    required this.hint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(
              color: value != null
                  ? AppTheme.primaryBlue
                  : Colors.grey[400]!),
          borderRadius: BorderRadius.circular(10),
          color: value != null
              ? AppTheme.primaryBlue.withOpacity(0.05)
              : null,
        ),
        child: Row(children: [
          Icon(Icons.calendar_today_outlined,
              size: 18,
              color: value != null
                  ? AppTheme.primaryBlue
                  : Colors.grey[500]),
          const SizedBox(width: 12),
          Text(
            value != null
                ? DateFormat('EEEE, d MMMM yyyy').format(value!)
                : hint,
            style: TextStyle(
                fontSize: 14,
                fontWeight: value != null ? FontWeight.w600 : FontWeight.normal,
                color: value != null ? null : Colors.grey[500]),
          ),
          const Spacer(),
          Icon(Icons.arrow_drop_down,
              color: value != null
                  ? AppTheme.primaryBlue
                  : Colors.grey[400]),
        ]),
      ),
    );
  }
}
