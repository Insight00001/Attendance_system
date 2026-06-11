import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// ── Status colours ─────────────────────────────────────────────

const _kPresent = Color(0xFF22C55E);
const _kLate    = Color(0xFFF97316);
const _kAbsent  = Color(0xFFEF4444);
const _kLeave   = Color(0xFF3B82F6);  // blue

bool _isLeaveStatus(String? s) => s == 'on_leave' || s == 'leave_pending';

Color _statusColor(String? status) => switch (status) {
  'present'       => _kPresent,
  'late'          => _kLate,
  'absent'        => _kAbsent,
  'on_leave'      => _kLeave,
  'leave_pending' => _kLeave,
  _               => Colors.transparent,
};

// ── Main widget ────────────────────────────────────────────────

class AttendanceCalendarWidget extends StatelessWidget {
  final Map<String, dynamic> dayData; // "YYYY-MM-DD" → {status, …}
  final int year;
  final int month;
  final void Function(int year, int month)? onMonthChanged;

  const AttendanceCalendarWidget({
    super.key,
    required this.dayData,
    required this.year,
    required this.month,
    this.onMonthChanged,
  });

  String? _statusFor(int day) {
    final key =
        '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
    final v = dayData[key];
    if (v == null) return null;
    return (v is Map) ? v['status'] as String? : v as String?;
  }

  _Summary get _summary {
    int p = 0, l = 0, a = 0, lv = 0;
    for (final v in dayData.values) {
      final s = (v is Map) ? v['status'] as String? : v as String?;
      switch (s) {
        case 'present':  p++;  break;
        case 'late':     l++;  break;
        case 'absent':   a++;  break;
        case 'on_leave':
        case 'leave_pending': lv++; break;
      }
    }
    return _Summary(p, l, a, lv);
  }

  @override
  Widget build(BuildContext context) {
    final label       = DateFormat('MMMM yyyy').format(DateTime(year, month));
    final firstWeekday = DateTime(year, month, 1).weekday; // Mon=1
    final daysInMonth  = DateTimeRange(
      start: DateTime(year, month, 1),
      end:   DateTime(year, month + 1, 1),
    ).duration.inDays;
    final today = DateTime.now();
    final s     = _summary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Month navigation ───────────────────────────────
        Row(children: [
          IconButton(
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: const Icon(Icons.chevron_left),
            onPressed: onMonthChanged == null ? null : () {
              final d = DateTime(year, month - 1);
              onMonthChanged!(d.year, d.month);
            },
          ),
          Expanded(
            child: Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          IconButton(
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: const Icon(Icons.chevron_right),
            onPressed: onMonthChanged == null ? null : () {
              final d = DateTime(year, month + 1);
              onMonthChanged!(d.year, d.month);
            },
          ),
        ]),

        const SizedBox(height: 4),

        // ── 7-column grid ──────────────────────────────────
        // Uses LayoutBuilder so cell width = min(availableWidth/7, 34)
        // and the grid centres itself.
        LayoutBuilder(builder: (ctx, box) {
          final cell = (box.maxWidth / 7).clamp(0.0, 46.0);
          final gridW = cell * 7;

          // Build all cells (empty + day cells)
          final totalCells = (firstWeekday - 1) + daysInMonth;
          final rows = (totalCells / 7).ceil();

          return Center(
            child: SizedBox(
              width: gridW,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Day headers
                  Row(
                    children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                        .map((h) => SizedBox(
                              width: cell,
                              height: cell * 0.55,
                              child: Center(
                                child: Text(h,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF94A3B8))),
                              ),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 2),

                  // Day rows
                  ...List.generate(rows, (row) {
                    return Row(
                      children: List.generate(7, (col) {
                        final idx     = row * 7 + col;
                        final dayNum  = idx - (firstWeekday - 1) + 1;
                        final isEmpty = idx < (firstWeekday - 1) ||
                                        dayNum > daysInMonth;

                        if (isEmpty) {
                          return SizedBox(width: cell, height: cell);
                        }

                        final weekday    = DateTime(year, month, dayNum).weekday;
                        final isWeekend  = weekday >= 6;
                        final isToday    = today.year == year &&
                                           today.month == month &&
                                           today.day == dayNum;
                        final isFuture   =
                            DateTime(year, month, dayNum).isAfter(today);
                        final status     = _statusFor(dayNum);
                        // Leave days always show blue, even in the future.
                        // All other future/weekend days stay transparent.
                        final color = (!isWeekend && _isLeaveStatus(status))
                            ? _kLeave
                            : (isWeekend || isFuture)
                                ? Colors.transparent
                                : _statusColor(status);
                        final hasColor   = color != Colors.transparent;

                        return SizedBox(
                          width: cell,
                          height: cell,
                          child: Padding(
                            padding: const EdgeInsets.all(1.5),
                            child: Container(
                              decoration: BoxDecoration(
                                color: hasColor
                                    ? color.withOpacity(0.15)
                                    : isWeekend
                                        ? const Color(0xFFF1F5F9)
                                        : null,
                                shape: BoxShape.circle,
                                border: isToday
                                    ? Border.all(
                                        color: Theme.of(ctx).primaryColor,
                                        width: 1.5)
                                    : null,
                              ),
                              child: Center(
                                child: Text(
                                  '$dayNum',
                                  style: TextStyle(
                                    fontSize: (cell * 0.36).clamp(10, 15),
                                    fontWeight: isToday
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                    color: hasColor
                                        ? color
                                        : isWeekend
                                            ? const Color(0xFFCBD5E1)
                                            : const Color(0xFF475569),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    );
                  }),
                ],
              ),
            ),
          );
        }),

        const SizedBox(height: 8),

        // ── Legend ─────────────────────────────────────────
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _Dot(color: _kPresent, label: 'Present'),
          const SizedBox(width: 10),
          _Dot(color: _kLate,    label: 'Late'),
          const SizedBox(width: 10),
          _Dot(color: _kAbsent,  label: 'Absent'),
          const SizedBox(width: 10),
          _Dot(color: _kLeave,   label: 'Leave'),
        ]),

        const SizedBox(height: 10),

        // ── Summary chips ──────────────────────────────────
        Row(children: [
          _Chip(label: 'Present', count: s.present, color: _kPresent),
          const SizedBox(width: 6),
          _Chip(label: 'Late',    count: s.late,    color: _kLate),
          const SizedBox(width: 6),
          _Chip(label: 'Absent',  count: s.absent,  color: _kAbsent),
          const SizedBox(width: 6),
          _Chip(label: 'Leave',   count: s.onLeave, color: _kLeave),
        ]),
      ],
    );
  }
}

// ── Internal models & helpers ──────────────────────────────────

class _Summary {
  final int present, late, absent, onLeave;
  const _Summary(this.present, this.late, this.absent, this.onLeave);
}

class _Dot extends StatelessWidget {
  final Color color;
  final String label;
  const _Dot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 7,
              height: 7,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 3),
          Text(label,
              style:
                  const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
        ],
      );
}

class _Chip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _Chip(
      {required this.label, required this.count, required this.color});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$count',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: color)),
            Text(label,
                style: TextStyle(
                    fontSize: 9, color: color.withOpacity(0.85))),
          ]),
        ),
      );
}
