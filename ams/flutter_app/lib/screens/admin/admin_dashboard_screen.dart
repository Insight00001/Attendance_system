import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../bloc/attendance/attendance_bloc.dart';
import '../../config/routes.dart';
import '../../models/models.dart';
import '../../services/leave_service.dart';
import '../../services/api_service.dart';
import '../../themes/app_theme.dart';
import '../../widgets/dashboard/summary_card.dart';
import '../../widgets/attendance/attendance_row.dart';
import '../../widgets/common/section_header.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _leaveService = LeaveService(ApiService());

  // Persist state independently — bloc events don't wipe each other
  DashboardSummary? _summary;
  List<AttendanceLog> _logs    = [];
  List<Map<String, dynamic>> _trend = [];
  List<AttendanceLog> _liveUpdates  = [];
  int  _pendingLeaves = 0;
  bool _loadingToday  = true;
  bool _loadingTrend  = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    setState(() {
      _loadingToday = true;
      _loadingTrend = true;
    });
    context.read<AttendanceBloc>()
      ..add(AttendanceLoadToday())
      ..add(AttendanceLoadTrend());
    _loadPendingLeaves();
  }

  Future<void> _loadPendingLeaves() async {
    try {
      final count = await _leaveService.getPendingCount();
      if (mounted) setState(() => _pendingLeaves = count);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now   = DateFormat('EEEE, d MMMM yyyy').format(DateTime.now());

    return BlocListener<AttendanceBloc, AttendanceState>(
      listener: (context, state) {
        // Store each state type independently — no wiping
        if (state is AttendanceTodayLoaded) {
          setState(() {
            _summary      = state.summary;
            _logs         = state.logs;
            _loadingToday = false;
          });
        } else if (state is AttendanceTrendLoaded) {
          setState(() {
            _trend        = state.trend;
            _loadingTrend = false;
          });
        }
      },
      child: RefreshIndicator(
        onRefresh: () async => _loadData(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────
              Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Dashboard',
                          style: AppTextStyles.heading2.copyWith(
                              color: theme.colorScheme.onSurface)),
                      Text(now,
                          style: AppTextStyles.caption
                              .copyWith(color: const Color(0xFF64748B))),
                    ],
                  ),
                ),
                const _LiveIndicator(),
              ]),
              const SizedBox(height: 24),

              // ── Summary Cards ────────────────────────────────
              _SummaryGrid(
                summary: _summary,
                loading: _loadingToday,
                pendingLeaves: _pendingLeaves,
                onLeaveTap: () => context.go(AppRoutes.adminLeave),
              ),
              const SizedBox(height: 32),

              // ── Charts ───────────────────────────────────────
              LayoutBuilder(builder: (context, constraints) {
                final isWide = constraints.maxWidth > 700;
                final trendChart = _AttendanceTrendChart(
                    trend: _trend, loading: _loadingTrend);
                final donutChart =
                    _StatusDonutChart(summary: _summary);
                return isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: trendChart),
                          const SizedBox(width: 16),
                          Expanded(flex: 2, child: donutChart),
                        ],
                      )
                    : Column(children: [
                        trendChart,
                        const SizedBox(height: 16),
                        donutChart,
                      ]);
              }),
              const SizedBox(height: 32),

              // ── Live Feed ────────────────────────────────────
              const SectionHeader(
                  title: "Today's Attendance", showViewAll: false),
              const SizedBox(height: 12),
              _AttendanceTable(
                  logs: _liveUpdates.isNotEmpty ? _liveUpdates : _logs),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Summary Grid ───────────────────────────────────────────────

class _SummaryGrid extends StatelessWidget {
  final DashboardSummary? summary;
  final bool loading;
  final int pendingLeaves;
  final VoidCallback? onLeaveTap;

  const _SummaryGrid({
    required this.summary,
    this.loading = false,
    this.pendingLeaves = 0,
    this.onLeaveTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return LayoutBuilder(builder: (context, constraints) {
      final crossCount = constraints.maxWidth > 700 ? 5 : 2;
      return GridView.count(
        crossAxisCount: crossCount,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: crossCount == 5 ? 1.2 : 1.0,
        children: [
          SummaryCard(
            label: 'Total Staff',
            value: loading ? '…' : s?.totalEmployees.toString() ?? '0',
            icon: Icons.people_outline,
            color: AppTheme.primaryBlue,
            subtitle: 'Active employees',
          ),
          SummaryCard(
            label: 'Present',
            value: loading ? '…' : s?.present.toString() ?? '0',
            icon: Icons.check_circle_outline,
            color: AppTheme.accentGreen,
            subtitle: s != null
                ? '${s.attendanceRate.toStringAsFixed(1)}% rate'
                : '',
          ),
          SummaryCard(
            label: 'Absent',
            value: loading ? '…' : s?.absent.toString() ?? '0',
            icon: Icons.cancel_outlined,
            color: AppTheme.accentRed,
            subtitle: 'Not clocked in',
          ),
          SummaryCard(
            label: 'Late',
            value: loading ? '…' : s?.late.toString() ?? '0',
            icon: Icons.schedule_outlined,
            color: AppTheme.accentOrange,
            subtitle: 'Late arrivals',
          ),
          GestureDetector(
            onTap: onLeaveTap,
            child: SummaryCard(
              label: 'Leave Requests',
              value: pendingLeaves.toString(),
              icon: Icons.event_note_outlined,
              color: AppTheme.accentPurple,
              subtitle:
                  pendingLeaves > 0 ? 'Tap to review' : 'None pending',
            ),
          ),
        ],
      );
    });
  }
}

// ── Trend Chart ────────────────────────────────────────────────

class _AttendanceTrendChart extends StatelessWidget {
  final List<Map<String, dynamic>> trend;
  final bool loading;
  const _AttendanceTrendChart(
      {required this.trend, this.loading = false});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Attendance Trend (30 days)',
                style: AppTextStyles.heading3),
            const SizedBox(height: 4),
            Text('Daily present vs absent',
                style: AppTextStyles.caption
                    .copyWith(color: const Color(0xFF64748B))),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : trend.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.bar_chart_outlined,
                                  size: 48, color: Color(0xFFE2E8F0)),
                              SizedBox(height: 8),
                              Text('No attendance data yet',
                                  style: TextStyle(
                                      color: Color(0xFF94A3B8))),
                            ],
                          ),
                        )
                      : LineChart(_buildChartData()),
            ),
          ],
        ),
      ),
    );
  }

  LineChartData _buildChartData() {
    final spots = trend.asMap().entries.map((e) {
      final present = (e.value['present'] as num?)?.toDouble() ?? 0;
      return FlSpot(e.key.toDouble(), present);
    }).toList();

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: const Color(0x1564748B), strokeWidth: 1),
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 32,
            getTitlesWidget: (v, _) => Text(v.toInt().toString(),
                style: const TextStyle(
                    fontSize: 10, color: Color(0xFF94A3B8))),
          ),
        ),
        bottomTitles:
            AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles:
            AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: AppTheme.primaryBlue,
          barWidth: 2.5,
          dotData: FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: AppTheme.primaryBlue.withOpacity(0.1),
          ),
        ),
      ],
    );
  }
}

// ── Donut Chart ────────────────────────────────────────────────

class _StatusDonutChart extends StatelessWidget {
  final DashboardSummary? summary;
  const _StatusDonutChart({this.summary});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Today's Status", style: AppTextStyles.heading3),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: s == null || s.totalEmployees == 0
                  ? const Center(
                      child: Text('No data',
                          style:
                              TextStyle(color: Color(0xFF94A3B8))))
                  : PieChart(PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 55,
                      sections: [
                        if (s.present > 0)
                          PieChartSectionData(
                            value: s.present.toDouble(),
                            color: AppTheme.accentGreen,
                            radius: 40,
                            title: '${s.present}',
                            titleStyle: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold),
                          ),
                        if (s.absent > 0)
                          PieChartSectionData(
                            value: s.absent.toDouble(),
                            color: AppTheme.accentRed,
                            radius: 40,
                            title: '${s.absent}',
                            titleStyle: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold),
                          ),
                        if (s.late > 0)
                          PieChartSectionData(
                            value: s.late.toDouble(),
                            color: AppTheme.accentOrange,
                            radius: 40,
                            title: '${s.late}',
                            titleStyle: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold),
                          ),
                      ],
                    )),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Dot(color: AppTheme.accentGreen, label: 'Present'),
                _Dot(color: AppTheme.accentRed, label: 'Absent'),
                _Dot(color: AppTheme.accentOrange, label: 'Late'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  final String label;
  const _Dot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
                color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: Color(0xFF64748B))),
      ]);
}

// ── Attendance Table ───────────────────────────────────────────

class _AttendanceTable extends StatelessWidget {
  final List<AttendanceLog> logs;
  const _AttendanceTable({required this.logs});

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Column(children: [
            Icon(Icons.inbox_outlined,
                size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text('No attendance recorded yet today',
                style: TextStyle(color: Colors.grey[500])),
          ]),
        ),
      );
    }
    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: logs.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) => AttendanceRow(log: logs[i]),
      ),
    );
  }
}

// ── Live Indicator ─────────────────────────────────────────────

class _LiveIndicator extends StatefulWidget {
  const _LiveIndicator();
  @override
  State<_LiveIndicator> createState() => _LiveIndicatorState();
}

class _LiveIndicatorState extends State<_LiveIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 1))
      ..repeat(reverse: true);
    _pulse = Tween(begin: 0.4, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) => Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: AppTheme.accentGreen.withOpacity(_pulse.value),
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 6),
        const Text('Live',
            style: TextStyle(
                fontSize: 12,
                color: AppTheme.accentGreen,
                fontWeight: FontWeight.w600)),
      ]);
}