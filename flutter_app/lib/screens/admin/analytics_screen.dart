import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/attendance/attendance_bloc.dart';
import '../../services/attendance_service.dart';
import '../../services/api_service.dart';
import '../../themes/app_theme.dart';
import '../../utils/file_saver/file_saver.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<AttendanceBloc>().add(AttendanceLoadTrend(days: 30));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Analytics & Reports', style: AppTextStyles.heading2),
            const SizedBox(height: 24),

            // ── Monthly Late Summary ───────────────────────────
            const _MonthlyLateSummary(),
            const SizedBox(height: 24),

            // ── 30-day Trend ───────────────────────────────────
            Text('Daily Trend (last 14 days)', style: AppTextStyles.heading3),
            const SizedBox(height: 12),
            BlocBuilder<AttendanceBloc, AttendanceState>(
              buildWhen: (prev, curr) =>
                  curr is AttendanceLoading ||
                  curr is AttendanceTrendLoaded,
              builder: (context, state) {
                if (state is AttendanceLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is AttendanceTrendLoaded) {
                  return _TrendTable(trend: state.trend);
                }
                return const Center(
                    child: Text('No analytics data available'));
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Monthly Late Summary ───────────────────────────────────────
// Self-contained: fetches via AttendanceService so its state never
// collides with the shared AttendanceBloc trend/summary states.

class _MonthlyLateSummary extends StatefulWidget {
  const _MonthlyLateSummary();
  @override
  State<_MonthlyLateSummary> createState() => _MonthlyLateSummaryState();
}

class _MonthlyLateSummaryState extends State<_MonthlyLateSummary> {
  final _service = AttendanceService(ApiService());

  late int _year;
  late int _month;
  List<Map<String, dynamic>> _summary = [];
  bool _loading = true;
  bool _exporting = false;
  String? _error;

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary =
          await _service.getMonthlyLateSummary(year: _year, month: _month);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load late summary';
        _loading = false;
      });
    }
  }

  void _changeMonth(int delta) {
    final now = DateTime.now();
    var y = _year;
    var m = _month + delta;
    if (m < 1) {
      m = 12;
      y--;
    } else if (m > 12) {
      m = 1;
      y++;
    }
    // Don't navigate into the future
    if (y > now.year || (y == now.year && m > now.month)) return;
    setState(() {
      _year = y;
      _month = m;
    });
    _load();
  }

  // ── Export ───────────────────────────────────────────────

  Future<void> _export(String format) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await _service.exportLateSummary(
          year: _year, month: _month, format: format);
      if (bytes.isEmpty) throw Exception('Empty file');

      final filename =
          'late_summary_${_year}_${_month.toString().padLeft(2, '0')}.$format';
      final path = await saveReportFile(filename, bytes);

      messenger.showSnackBar(SnackBar(
        content: Text(path == null
            ? 'Report downloaded: $filename'
            : 'Report saved to $path'),
        duration: const Duration(seconds: 6),
        action: (path != null && canOpenSavedFile)
            ? SnackBarAction(
                label: 'OPEN', onPressed: () => openSavedFile(path))
            : null,
      ));
    } catch (e) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Export failed. Please try again.'),
        backgroundColor: AppTheme.accentRed,
      ));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrentMonth = _year == now.year && _month == now.month;
    final lateStaff =
        _summary.where((s) => (s['late_count'] as int? ?? 0) > 0).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header with month picker ─────────────────────
            Text('Monthly Late Summary', style: AppTextStyles.heading3),
            const SizedBox(height: 6),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Previous month',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _changeMonth(-1),
                ),
                const SizedBox(width: 4),
                Text(
                  '${_monthNames[_month - 1]} $_year',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Next month',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: isCurrentMonth ? null : () => _changeMonth(1),
                ),
                const Spacer(),
                if (_exporting)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else ...[
                  IconButton(
                    icon: const Icon(Icons.picture_as_pdf_outlined,
                        color: AppTheme.accentRed),
                    tooltip: 'Export as PDF',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed:
                        _summary.isEmpty ? null : () => _export('pdf'),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.table_view_outlined,
                        color: Colors.green),
                    tooltip: 'Export as Excel',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed:
                        _summary.isEmpty ? null : () => _export('xlsx'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$lateStaff of ${_summary.length} staff were late this month',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),

            // ── Body ─────────────────────────────────────────
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Text(_error!,
                          style: const TextStyle(color: AppTheme.accentRed)),
                      const SizedBox(height: 8),
                      TextButton(
                          onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                ),
              )
            else if (_summary.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No staff records for this month'),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Staff')),
                      DataColumn(label: Text('Department')),
                      DataColumn(label: Text('Times Late'), numeric: true),
                      DataColumn(
                          label: Text('Total Late (mins)'), numeric: true),
                      DataColumn(label: Text('Days Present'), numeric: true),
                    ],
                    rows: _summary.map((s) {
                      final lateCount = s['late_count'] as int? ?? 0;
                      return DataRow(cells: [
                        DataCell(Text(s['name'] as String? ?? '')),
                        DataCell(Text(s['department'] as String? ?? '—')),
                        DataCell(_LateCountBadge(count: lateCount)),
                        DataCell(Text('${s['total_late_minutes'] ?? 0}')),
                        DataCell(Text('${s['days_present'] ?? 0}')),
                      ]);
                    }).toList(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LateCountBadge extends StatelessWidget {
  final int count;
  const _LateCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final Color color;
    if (count == 0) {
      color = Colors.green;
    } else if (count <= 3) {
      color = Colors.orange;
    } else {
      color = AppTheme.accentRed;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count',
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ── 30-day Trend Table ─────────────────────────────────────────

class _TrendTable extends StatelessWidget {
  final List<Map<String, dynamic>> trend;
  const _TrendTable({required this.trend});

  @override
  Widget build(BuildContext context) {
    final rows = trend.reversed.take(14).toList();
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Present')),
            DataColumn(label: Text('Absent')),
            DataColumn(label: Text('Late')),
            DataColumn(label: Text('Rate %')),
          ],
          rows: rows
              .map((row) => DataRow(cells: [
                    DataCell(Text(row['date'] as String? ?? '')),
                    DataCell(
                        Text('${row['present'] ?? 0}')),
                    DataCell(Text('${row['absent'] ?? 0}')),
                    DataCell(Text('${row['late'] ?? 0}')),
                    DataCell(Text(
                        '${row['attendance_rate'] ?? 0}%')),
                  ]))
              .toList(),
        ),
      ),
    );
  }
}
