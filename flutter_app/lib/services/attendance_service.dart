import 'api_service.dart';
import '../models/models.dart';

class AttendanceService {
  final ApiService _api;
  AttendanceService(this._api);

  Future<Map<String, dynamic>> clockInByFace({
    required String imageB64,
    List<String> livenessFrames = const [],
  }) async {
    final resp = await _api.post('/attendance/clock-in', data: {
      'image_b64': imageB64,
      'liveness_frames': livenessFrames,
    });
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> clockOutByFace(String imageB64) async {
    final resp = await _api.post('/attendance/clock-out',
        data: {'image_b64': imageB64});
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> verifyFace(String imageB64) async {
    final resp = await _api
        .post('/attendance/face-verify', data: {'image_b64': imageB64});
    return resp.data as Map<String, dynamic>;
  }

  Future<List<AttendanceLog>> getTodayAttendance() async {
    final resp = await _api.get('/attendance/today');
    final logs = (resp.data['logs'] as List);
    return logs
        .map((e) => AttendanceLog.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PaginatedResult<AttendanceLog>> getLogs({
    String? startDate,
    String? endDate,
    String? employeeId,
    String? status,
    int page = 1,
  }) async {
    final resp = await _api.get('/attendance/logs', params: {
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (employeeId != null) 'employee_id': employeeId,
      if (status != null) 'status': status,
      'page': page,
    });
    final data = resp.data as Map<String, dynamic>;
    return PaginatedResult(
      items: (data['logs'] as List)
          .map((e) => AttendanceLog.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: data['total'] as int,
      pages: data['pages'] as int,
      page: data['page'] as int,
    );
  }

  Future<DashboardSummary> getSummary({String? date}) async {
    final resp = await _api.get('/analytics/summary',
        params: date != null ? {'date': date} : null);
    return DashboardSummary.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<List<Map<String, dynamic>>> getDailyTrend({int days = 30}) async {
    final resp =
        await _api.get('/analytics/trend', params: {'days': days});
    final data = resp.data as Map<String, dynamic>;
    return (data['trend'] as List).cast<Map<String, dynamic>>();
  }

  /// All active staff with late counts for a month.
  /// Returns list of {employee_id, name, department, late_count,
  /// total_late_minutes, days_present}
  Future<List<Map<String, dynamic>>> getMonthlyLateSummary({
    int? year,
    int? month,
  }) async {
    final now = DateTime.now();
    final resp = await _api.get('/analytics/late-summary', params: {
      'year': year ?? now.year,
      'month': month ?? now.month,
    });
    final data = resp.data as Map<String, dynamic>;
    return (data['summary'] as List).cast<Map<String, dynamic>>();
  }

  /// Download the monthly late summary as a file.
  /// [format] is 'pdf' or 'xlsx'. Returns raw file bytes.
  Future<List<int>> exportLateSummary({
    required int year,
    required int month,
    required String format,
  }) async {
    final resp = await _api.getBytes('/analytics/late-summary/export',
        params: {'year': year, 'month': month, 'format': format});
    return resp.data ?? <int>[];
  }

  Future<List<Map<String, dynamic>>> getDepartmentStats() async {
    final resp = await _api.get('/analytics/department');
    return (resp.data as List).cast<Map<String, dynamic>>();
  }

  /// Employee's own logs (no admin required).
  Future<PaginatedResult<AttendanceLog>> getMyLogs({
    String? startDate,
    String? endDate,
    String? status,
    int page = 1,
  }) async {
    final resp = await _api.get('/attendance/my-logs', params: {
      if (startDate != null) 'start_date': startDate,
      if (endDate   != null) 'end_date':   endDate,
      if (status    != null) 'status':     status,
      'page': page,
    });
    final data = resp.data as Map<String, dynamic>;
    return PaginatedResult(
      items: (data['logs'] as List)
          .map((e) => AttendanceLog.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: data['total'] as int,
      pages: data['pages'] as int,
      page:  data['page']  as int,
    );
  }

  /// Returns {year, month, days_in_month, days: {"2026-06-01": {status, clock_in, ...}}}
  Future<Map<String, dynamic>> getCalendar({
    int? year,
    int? month,
    String? employeeId,
  }) async {
    final now = DateTime.now();
    final resp = await _api.get('/attendance/calendar', params: {
      'year':  year  ?? now.year,
      'month': month ?? now.month,
      if (employeeId != null) 'employee_id': employeeId,
    });
    return resp.data as Map<String, dynamic>;
  }
}
