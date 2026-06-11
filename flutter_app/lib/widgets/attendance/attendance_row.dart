import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/models.dart';
import '../../themes/app_theme.dart';
import '../common/status_chip.dart';

class AttendanceRow extends StatelessWidget {
  final AttendanceLog log;

  const AttendanceRow({super.key, required this.log});

  String _formatTime(String? iso) {
    if (iso == null) return '—';
    try {
      return DateFormat.jm().format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppTheme.primaryBlue.withOpacity(0.1),
            child: Text(
              (log.employeeName ?? '?').isNotEmpty
                  ? (log.employeeName ?? '?')[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                  color: AppTheme.primaryBlue,
                  fontWeight: FontWeight.w700,
                  fontSize: 14),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(log.employeeName ?? 'Unknown',
                    style: AppTextStyles.bodyMed),
                Text(log.attendanceDate,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF94A3B8))),
              ],
            ),
          ),
          _TimeColumn(label: 'In', time: _formatTime(log.clockIn)),
          const SizedBox(width: 16),
          _TimeColumn(label: 'Out', time: _formatTime(log.clockOut)),
          const SizedBox(width: 16),
          StatusChip(status: log.status),
          if (log.isLate) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: '${log.lateMinutes} min late',
              child: const Icon(Icons.schedule,
                  size: 16, color: AppTheme.accentOrange),
            ),
          ],
        ],
      ),
    );
  }
}

class _TimeColumn extends StatelessWidget {
  final String label;
  final String time;
  const _TimeColumn({required this.label, required this.time});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 10, color: Color(0xFF94A3B8))),
        Text(time,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
