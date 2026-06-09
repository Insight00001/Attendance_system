import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/attendance_service.dart';
import '../../services/api_service.dart';
import '../../themes/app_theme.dart';
import '../../widgets/attendance/attendance_calendar.dart';
import '../../widgets/attendance/attendance_row.dart';
import '../../models/models.dart';

class MyAttendanceScreen extends StatefulWidget {
  const MyAttendanceScreen({super.key});
  @override
  State<MyAttendanceScreen> createState() => _MyAttendanceScreenState();
}

class _MyAttendanceScreenState extends State<MyAttendanceScreen> {
  late final AttendanceService _service =
      AttendanceService(ApiService());

  int _year  = DateTime.now().year;
  int _month = DateTime.now().month;

  Map<String, dynamic> _calendarDays = {};
  List<AttendanceLog>  _logs         = [];
  bool _calLoading  = false;
  bool _logsLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchCalendar();
    _fetchLogs();
  }

  Future<void> _fetchCalendar() async {
    setState(() => _calLoading = true);
    try {
      final data = await _service.getCalendar(year: _year, month: _month);
      if (mounted) {
        setState(() =>
            _calendarDays = (data['days'] as Map<String, dynamic>?) ?? {});
      }
    } catch (_) {
      if (mounted) setState(() => _calendarDays = {});
    } finally {
      if (mounted) setState(() => _calLoading = false);
    }
  }

  Future<void> _fetchLogs() async {
    setState(() => _logsLoading = true);
    try {
      final pad = (int n) => n.toString().padLeft(2, '0');
      final result = await _service.getMyLogs(
        startDate: '$_year-${pad(_month)}-01',
        endDate:   '$_year-${pad(_month)}-${pad(_daysInMonth(_year, _month))}',
      );
      if (mounted) setState(() => _logs = result.items);
    } catch (_) {
      // Non-fatal — calendar is the primary view
    } finally {
      if (mounted) setState(() => _logsLoading = false);
    }
  }

  void _changeMonth(int year, int month) {
    setState(() { _year = year; _month = month; });
    _fetchCalendar();
    _fetchLogs();
  }

  int _daysInMonth(int y, int m) =>
      DateTimeRange(start: DateTime(y, m, 1), end: DateTime(y, m + 1, 1))
          .duration.inDays;

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppTheme.accentRed));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Attendance'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () { _fetchCalendar(); _fetchLogs(); },
          ),
        ],
      ),
      body: _calLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async { _fetchCalendar(); _fetchLogs(); },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Calendar ──────────────────────────────────
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: AttendanceCalendarWidget(
                        year:           _year,
                        month:          _month,
                        dayData:        _calendarDays,
                        onMonthChanged: _changeMonth,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Log list ──────────────────────────────────
                  Text('Daily Logs',
                      style: AppTextStyles.heading3),
                  const SizedBox(height: 8),

                  if (_logsLoading)
                    const Center(
                        child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ))
                  else if (_logs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                          child: Text('No logs for this month',
                              style:
                                  TextStyle(color: Colors.grey[500]))),
                    )
                  else
                    Card(
                      child: Column(
                        children: _logs.asMap().entries.map((entry) {
                          final i   = entry.key;
                          final log = entry.value;
                          return Column(children: [
                            AttendanceRow(log: log),
                            if (i < _logs.length - 1)
                              const Divider(height: 1, indent: 16),
                          ]);
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
