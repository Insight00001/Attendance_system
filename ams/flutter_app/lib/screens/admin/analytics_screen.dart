import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/attendance/attendance_bloc.dart';
import '../../themes/app_theme.dart';

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
            BlocBuilder<AttendanceBloc, AttendanceState>(
              builder: (context, state) {
                if (state is AttendanceLoading) {
                  return const Center(
                      child: CircularProgressIndicator());
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
