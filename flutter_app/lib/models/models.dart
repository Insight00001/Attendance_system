// ─── models/user_model.dart ────────────────────────────────────
class UserModel {
  final String id;
  final String email;
  final String role;
  final bool isActive;
  final bool isVerified;
  final String? lastLoginAt;
  final EmployeeModel? employee;

  const UserModel({
    required this.id,
    required this.email,
    required this.role,
    required this.isActive,
    required this.isVerified,
    this.lastLoginAt,
    this.employee,
  });

  bool get isAdmin => ['super_admin', 'admin', 'hr'].contains(role);

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
    id:          json['id'] as String,
    email:       json['email'] as String,
    role:        json['role'] as String? ?? 'employee',
    isActive:    json['is_active'] as bool? ?? true,
    isVerified:  json['is_verified'] as bool? ?? false,
    lastLoginAt: json['last_login_at'] as String?,
    employee:    json['employee'] != null
        ? EmployeeModel.fromJson(json['employee'] as Map<String, dynamic>)
        : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'email': email, 'role': role,
    'is_active': isActive, 'is_verified': isVerified,
  };
}

// ─── models/employee_model.dart ────────────────────────────────
class EmployeeModel {
  final String id;
  final String employeeId;
  final String fullName;
  final String firstName;
  final String lastName;
  final String? gender;
  final String? phone;
  final String? jobTitle;
  final String employmentStatus;
  final String? hireDate;
  final String? photoUrl;
  final String? shiftStart;
  final String? shiftEnd;
  final int lateThreshold;
  final DepartmentModel? department;
  final RoleModel? role;
  final String? email;
  final String? rfidCardUid;

  const EmployeeModel({
    required this.id,
    required this.employeeId,
    required this.fullName,
    required this.firstName,
    required this.lastName,
    this.gender,
    this.phone,
    this.jobTitle,
    required this.employmentStatus,
    this.hireDate,
    this.photoUrl,
    this.shiftStart,
    this.shiftEnd,
    required this.lateThreshold,
    this.department,
    this.role,
    this.email,
    this.rfidCardUid,
  });

  factory EmployeeModel.fromJson(Map<String, dynamic> json) => EmployeeModel(
    id:               json['id'] as String,
    employeeId:       json['employee_id'] as String,
    fullName:         json['full_name'] as String? ?? '',
    firstName:        json['first_name'] as String? ?? '',
    lastName:         json['last_name'] as String? ?? '',
    gender:           json['gender'] as String?,
    phone:            json['phone'] as String?,
    jobTitle:         json['job_title'] as String?,
    employmentStatus: json['employment_status'] as String? ?? 'active',
    hireDate:         json['hire_date'] as String?,
    photoUrl:         json['photo_url'] as String?,
    shiftStart:       json['shift_start'] as String?,
    shiftEnd:         json['shift_end'] as String?,
    lateThreshold:    json['late_threshold'] as int? ?? 15,
    department:       json['department'] != null
        ? DepartmentModel.fromJson(json['department'] as Map<String, dynamic>)
        : null,
    role:             json['role'] != null
        ? RoleModel.fromJson(json['role'] as Map<String, dynamic>)
        : null,
    email:            json['email'] as String?,
    rfidCardUid:      json['card_uid'] as String?,
  );

  String get avatarInitials {
    final f = firstName.isNotEmpty ? firstName[0] : '';
    final l = lastName.isNotEmpty ? lastName[0] : '';
    return '$f$l'.toUpperCase();
  }
}

class DepartmentModel {
  final String id;
  final String name;
  final String code;

  const DepartmentModel({required this.id, required this.name, required this.code});

  factory DepartmentModel.fromJson(Map<String, dynamic> json) => DepartmentModel(
    id: json['id'] as String,
    name: json['name'] as String,
    code: json['code'] as String,
  );
}

class RoleModel {
  final String id;
  final String name;
  final String code;

  const RoleModel({required this.id, required this.name, required this.code});

  factory RoleModel.fromJson(Map<String, dynamic> json) => RoleModel(
    id: json['id'] as String,
    name: json['name'] as String,
    code: json['code'] as String,
  );
}

// ─── models/attendance_model.dart ──────────────────────────────
class AttendanceLog {
  final String id;
  final String employeeId;
  final String? employeeName;
  final String attendanceDate;
  final String? clockIn;
  final String? clockOut;
  final String? clockInMethod;
  final String status;
  final bool isLate;
  final int lateMinutes;
  final int workingMinutes;
  final int overtimeMinutes;
  final double? confidence;
  final bool flagged;

  const AttendanceLog({
    required this.id,
    required this.employeeId,
    this.employeeName,
    required this.attendanceDate,
    this.clockIn,
    this.clockOut,
    this.clockInMethod,
    required this.status,
    required this.isLate,
    required this.lateMinutes,
    required this.workingMinutes,
    required this.overtimeMinutes,
    this.confidence,
    required this.flagged,
  });

  factory AttendanceLog.fromJson(Map<String, dynamic> json) => AttendanceLog(
    id:              json['id'] as String,
    employeeId:      json['employee_id'] as String,
    employeeName:    json['employee_name'] as String?,
    attendanceDate:  json['attendance_date'] as String,
    clockIn:         json['clock_in'] as String?,
    clockOut:        json['clock_out'] as String?,
    clockInMethod:   json['clock_in_method'] as String?,
    status:          json['status'] as String? ?? 'present',
    isLate:          json['is_late'] as bool? ?? false,
    lateMinutes:     json['late_minutes'] as int? ?? 0,
    workingMinutes:  json['working_minutes'] as int? ?? 0,
    overtimeMinutes: json['overtime_minutes'] as int? ?? 0,
    confidence:      (json['confidence_in'] as num?)?.toDouble(),
    flagged:         json['flagged'] as bool? ?? false,
  );

  String get formattedWorkingTime {
    final h = workingMinutes ~/ 60;
    final m = workingMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}

// ── Dashboard summary model ──
class DashboardSummary {
  final int totalEmployees;
  final int present;
  final int absent;
  final int late;
  final int clockedOut;
  final int stillInOffice;
  final double attendanceRate;
  final double avgWorkingMinutes;
  final String date;

  const DashboardSummary({
    required this.totalEmployees,
    required this.present,
    required this.absent,
    required this.late,
    required this.clockedOut,
    required this.stillInOffice,
    required this.attendanceRate,
    required this.avgWorkingMinutes,
    required this.date,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> json) => DashboardSummary(
    totalEmployees:  json['total_employees'] as int? ?? 0,
    present:         json['present'] as int? ?? 0,
    absent:          json['absent'] as int? ?? 0,
    late:            json['late'] as int? ?? 0,
    clockedOut:      json['clocked_out'] as int? ?? 0,
    stillInOffice:   json['still_in_office'] as int? ?? 0,
    attendanceRate:  (json['attendance_rate'] as num?)?.toDouble() ?? 0.0,
    avgWorkingMinutes: (json['avg_working_minutes'] as num?)?.toDouble() ?? 0.0,
    date:            json['date'] as String? ?? '',
  );
}

// ── Notification model ──
class NotificationModel {
  final String id;
  final String type;
  final String title;
  final String message;
  final bool isRead;
  final String? readAt;
  final String createdAt;

  const NotificationModel({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.isRead,
    this.readAt,
    required this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) => NotificationModel(
    id:        json['id'] as String,
    type:      json['type'] as String? ?? 'info',
    title:     json['title'] as String,
    message:   json['message'] as String,
    isRead:    json['is_read'] as bool? ?? false,
    readAt:    json['read_at'] as String?,
    createdAt: json['created_at'] as String,
  );
}

// ── Paginated result wrapper ──
class PaginatedResult<T> {
  final List<T> items;
  final int total;
  final int pages;
  final int page;

  const PaginatedResult({
    required this.items,
    required this.total,
    required this.pages,
    required this.page,
  });
}