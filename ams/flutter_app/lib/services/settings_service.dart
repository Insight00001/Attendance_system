import 'api_service.dart';

class SettingsService {
  final ApiService _api;
  SettingsService(this._api);

  // ── App Settings ──────────────────────────────────────────

  Future<Map<String, dynamic>> getSettings() async {
    final resp = await _api.get('/settings');
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateSettings(Map<String, dynamic> data) async {
    final resp = await _api.put('/settings', data: data);
    return resp.data as Map<String, dynamic>;
  }

  // ── Profile ───────────────────────────────────────────────

  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) async {
    final resp = await _api.put('/settings/profile', data: data);
    return resp.data as Map<String, dynamic>;
  }

  // ── Password ──────────────────────────────────────────────

  Future<void> changePassword(String currentPassword, String newPassword) async {
    await _api.put('/settings/change-password', data: {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
  }

  // ── Shift ─────────────────────────────────────────────────

  Future<Map<String, dynamic>> updateShift({
    String? shiftStart,
    String? shiftEnd,
    int? lateThreshold,
    String? employeeId,
  }) async {
    final resp = await _api.put('/settings/shift', data: {
      if (shiftStart != null)    'shift_start':     shiftStart,
      if (shiftEnd != null)      'shift_end':       shiftEnd,
      if (lateThreshold != null) 'late_threshold':  lateThreshold,
      if (employeeId != null)    'employee_id':     employeeId,
    });
    return resp.data as Map<String, dynamic>;
  }

  // ── Departments ───────────────────────────────────────────

  Future<List<dynamic>> getDepartments() async {
    final resp = await _api.get('/settings/departments');
    return resp.data as List;
  }

  Future<void> createDepartment(String name, String code,
      {String description = ''}) async {
    await _api.post('/settings/departments', data: {
      'name': name,
      'code': code,
      'description': description,
    });
  }

  Future<void> deleteDepartment(String id) async {
    await _api.delete('/settings/departments/$id');
  }

  // ── Roles ─────────────────────────────────────────────────

  Future<List<dynamic>> getRoles() async {
    final resp = await _api.get('/settings/roles');
    return resp.data as List;
  }

  Future<void> createRole(String name, String code,
      {String description = ''}) async {
    await _api.post('/settings/roles', data: {
      'name': name,
      'code': code,
      'description': description,
    });
  }

  Future<void> deleteRole(String id) async {
    await _api.delete('/settings/roles/$id');
  }
}