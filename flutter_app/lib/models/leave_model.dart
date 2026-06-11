// ─── models/leave_model.dart ──────────────────────────────────

const leaveTypeLabels = {
  'annual':    'Annual Leave',
  'sick':      'Sick Leave',
  'emergency': 'Emergency',
  'unpaid':    'Unpaid Leave',
  'absence':   'Absence',
  'other':     'Other',
};

class LeaveRequest {
  final String id;
  final String startDate;
  final String endDate;
  final String? reason;
  final String status;
  final String leaveType;
  final String? approvedAt;
  final String? approvedByEmail;
  final String createdAt;
  final String? employeeName;
  final String? empCode;
  final String? department;

  const LeaveRequest({
    required this.id,
    required this.startDate,
    required this.endDate,
    this.reason,
    required this.status,
    this.leaveType = 'annual',
    this.approvedAt,
    this.approvedByEmail,
    required this.createdAt,
    this.employeeName,
    this.empCode,
    this.department,
  });

  factory LeaveRequest.fromJson(Map<String, dynamic> json) => LeaveRequest(
    id:              json['id'] as String,
    startDate:       json['start_date'] as String,
    endDate:         json['end_date'] as String,
    reason:          json['reason'] as String?,
    status:          json['status'] as String? ?? 'pending',
    leaveType:       json['leave_type'] as String? ?? 'annual',
    approvedAt:      json['approved_at'] as String?,
    approvedByEmail: json['approved_by_email'] as String?,
    createdAt:       json['created_at'] as String,
    employeeName:    json['employee_name'] as String?,
    empCode:         json['emp_code'] as String?,
    department:      json['department'] as String?,
  );

  String get leaveTypeLabel =>
      leaveTypeLabels[leaveType] ?? leaveType;

  /// Counts weekdays only — matches backend attendance-marking logic.
  int get daysCount {
    try {
      final start = DateTime.parse(startDate);
      final end   = DateTime.parse(endDate);
      int count = 0;
      for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
        if (d.weekday != DateTime.saturday && d.weekday != DateTime.sunday) {
          count++;
        }
      }
      return count > 0 ? count : 1;
    } catch (_) {
      return 1;
    }
  }
}