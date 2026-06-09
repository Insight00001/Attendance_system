import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/attendance_service.dart';
import '../../services/api_service.dart';
import '../../themes/app_theme.dart';
import '../../widgets/attendance/attendance_calendar.dart';
import '../../widgets/attendance/attendance_row.dart';

class AttendanceLogsScreen extends StatefulWidget {
  const AttendanceLogsScreen({super.key});
  @override
  State<AttendanceLogsScreen> createState() => _AttendanceLogsScreenState();
}

class _AttendanceLogsScreenState extends State<AttendanceLogsScreen> {
  final AttendanceService _service = AttendanceService(ApiService());
  final ApiService _api = ApiService();

  // ── Employees ───────────────────────────────────────────────
  List<EmployeeModel> _employees = [];
  EmployeeModel? _selected;

  // ── Calendar state ───────────────────────────────────────────
  int _year  = DateTime.now().year;
  int _month = DateTime.now().month;
  Map<String, dynamic> _calendarDays = {};

  // ── Log list state ───────────────────────────────────────────
  List<AttendanceLog> _logs = [];
  String? _statusFilter;

  bool _empLoading = false;
  bool _calLoading = false;
  bool _logLoading = false;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  // ── Data fetchers ────────────────────────────────────────────

  Future<void> _loadEmployees() async {
    setState(() => _empLoading = true);
    try {
      final resp = await _api.get(
          '/employees', params: {'status': 'active', 'per_page': '200'});
      if (!mounted) return;
      final data = resp.data as Map<String, dynamic>;
      final list = ((data['employees'] ?? data['data']) as List)
          .map((e) => EmployeeModel.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() {
        _employees = list;
        if (list.isNotEmpty) {
          _selected = list.first;
          _fetchCalendar();
          _fetchLogs();
        }
      });
    } catch (e) {
      _showError(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _empLoading = false);
    }
  }

  Future<void> _fetchCalendar() async {
    if (_selected == null) return;
    setState(() => _calLoading = true);
    try {
      final data = await _service.getCalendar(
        year:       _year,
        month:      _month,
        employeeId: _selected!.id,
      );
      if (mounted) {
        setState(() =>
            _calendarDays = (data['days'] as Map<String, dynamic>?) ?? {});
      }
    } catch (_) {
      // Show empty calendar rather than a red snackbar
      if (mounted) setState(() => _calendarDays = {});
    } finally {
      if (mounted) setState(() => _calLoading = false);
    }
  }

  Future<void> _fetchLogs() async {
    if (_selected == null) return;
    setState(() => _logLoading = true);
    try {
      final daysInMonth = DateTimeRange(
        start: DateTime(_year, _month, 1),
        end:   DateTime(_year, _month + 1, 1),
      ).duration.inDays;
      final result = await _service.getLogs(
        employeeId: _selected!.id,
        startDate:  '$_year-${_month.toString().padLeft(2, '0')}-01',
        endDate:    '$_year-${_month.toString().padLeft(2, '0')}-'
                    '${daysInMonth.toString().padLeft(2, '0')}',
        status:     _statusFilter,
        page:       1,
      );
      if (mounted) setState(() => _logs = result.items);
    } catch (_) {
      // Non-fatal
    } finally {
      if (mounted) setState(() => _logLoading = false);
    }
  }

  void _onEmployeeChanged(EmployeeModel? emp) {
    if (emp == null) return;
    setState(() {
      _selected     = emp;
      _calendarDays = {};
      _logs         = [];
    });
    _fetchCalendar();
    _fetchLogs();
  }

  void _onMonthChanged(int y, int m) {
    setState(() { _year = y; _month = m; });
    _fetchCalendar();
    _fetchLogs();
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppTheme.accentRed));
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Logs',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () { _fetchCalendar(); _fetchLogs(); },
          ),
        ],
      ),
      body: _empLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              // ── Employee picker ────────────────────────────
              _EmployeePicker(
                employees: _employees,
                selected:  _selected,
                onChanged: _onEmployeeChanged,
              ),

              // ── Calendar + logs ────────────────────────────
              Expanded(
                child: _selected == null
                    ? Center(
                        child: Text('No employees found',
                            style: TextStyle(color: Colors.grey[500])))
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          // Calendar card
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: _calLoading
                                  ? const SizedBox(
                                      height: 200,
                                      child: Center(
                                          child: CircularProgressIndicator()))
                                  : AttendanceCalendarWidget(
                                      year:           _year,
                                      month:          _month,
                                      dayData:        _calendarDays,
                                      onMonthChanged: _onMonthChanged,
                                    ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Log list header + filter
                          Row(children: [
                            Text('Daily Logs', style: AppTextStyles.heading3),
                            const Spacer(),
                            DropdownButton<String?>(
                              value: _statusFilter,
                              underline: const SizedBox.shrink(),
                              hint: const Text('All',
                                  style: TextStyle(fontSize: 13)),
                              items: const [
                                DropdownMenuItem(
                                    value: null, child: Text('All')),
                                DropdownMenuItem(
                                    value: 'present',
                                    child: Text('Present')),
                                DropdownMenuItem(
                                    value: 'late', child: Text('Late')),
                                DropdownMenuItem(
                                    value: 'absent',
                                    child: Text('Absent')),
                              ],
                              onChanged: (v) {
                                setState(() => _statusFilter = v);
                                _fetchLogs();
                              },
                            ),
                          ]),
                          const SizedBox(height: 8),

                          // Logs
                          if (_logLoading)
                            const Center(
                                child: Padding(
                              padding: EdgeInsets.all(24),
                              child: CircularProgressIndicator(),
                            ))
                          else if (_logs.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(24),
                              child: Center(
                                  child: Text('No logs for this period',
                                      style: TextStyle(
                                          color: Colors.grey[500]))),
                            )
                          else
                            Card(
                              child: Column(
                                children:
                                    _logs.asMap().entries.map((entry) {
                                  final i   = entry.key;
                                  final log = entry.value;
                                  return Column(children: [
                                    AttendanceRow(log: log),
                                    if (i < _logs.length - 1)
                                      const Divider(
                                          height: 1, indent: 16),
                                  ]);
                                }).toList(),
                              ),
                            ),
                        ],
                      ),
              ),
            ]),
    );
  }
}

// ── Employee picker strip ──────────────────────────────────────

class _EmployeePicker extends StatelessWidget {
  final List<EmployeeModel> employees;
  final EmployeeModel? selected;
  final void Function(EmployeeModel?) onChanged;

  const _EmployeePicker({
    required this.employees,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: DropdownButtonFormField<EmployeeModel>(
        value: selected,
        isExpanded: true,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.person_search_outlined, size: 20),
          hintText: 'Select employee',
          isDense: true,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
        items: employees
            .map((e) => DropdownMenuItem(
                  value: e,
                  child: Text(
                    '${e.fullName}  (${e.employeeId})',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                ))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}
