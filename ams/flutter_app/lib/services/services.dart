// ─── services/auth_service.dart ───────────────────────────────
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_service.dart';
import '../config/app_config.dart';
import '../models/models.dart';
import 'package:dio/dio.dart';

import 'package:socket_io_client/socket_io_client.dart' as io;


class AuthService {
  final ApiService _api;
  final _storage = const FlutterSecureStorage();

  AuthService(this._api);

  Future<Map<String, dynamic>> login(String email, String password) async {
    final resp = await _api.post('/auth/login', data: {
      'email': email.trim().toLowerCase(),
      'password': password,
    });
    final data = resp.data as Map<String, dynamic>;
    await _api.saveTokens(
      data['access_token'] as String,
      data['refresh_token'] as String,
    );
    await _storage.write(
      key: AppConfig.userKey,
      value: jsonEncode(data['user']),
    );
    return data;
  }

  Future<void> logout(String refreshToken) async {
    try {
      await _api.post('/auth/logout', data: {'refresh_token': refreshToken});
    } catch (_) {}
    await _api.clearTokens();
  }

  Future<UserModel?> getStoredUser() async {
    final json = await _storage.read(key: AppConfig.userKey);
    if (json == null) return null;
    return UserModel.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  Future<UserModel> getMe() async {
    final resp = await _api.get('/auth/me');
    return UserModel.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<void> forgotPassword(String email) async {
    await _api.post('/auth/forgot-password', data: {'email': email});
  }

  Future<void> resetPassword(String token, String newPassword) async {
    await _api.post('/auth/reset-password', data: {
      'token': token,
      'password': newPassword,
    });
  }
}

// ─── services/attendance_service.dart ─────────────────────────

class AttendanceService {
  final ApiService _api;
  AttendanceService(this._api);

  /// Clock in via face recognition (image_b64 = base64 JPEG)
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
    final resp = await _api.post('/attendance/clock-out', data: {'image_b64': imageB64});
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> verifyFace(String imageB64) async {
    final resp = await _api.post('/attendance/face-verify', data: {'image_b64': imageB64});
    return resp.data as Map<String, dynamic>;
  }

  Future<List<AttendanceLog>> getTodayAttendance() async {
    final resp = await _api.get('/attendance/today');
    final logs = (resp.data['logs'] as List);
    return logs.map((e) => AttendanceLog.fromJson(e as Map<String, dynamic>)).toList();
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
    final resp = await _api.get('/analytics/daily', params: {'days': days});
    return (resp.data as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getDepartmentStats() async {
    final resp = await _api.get('/analytics/department');
    return (resp.data as List).cast<Map<String, dynamic>>();
  }
}

// ─── services/employee_service.dart ───────────────────────────


class EmployeeService {
  final ApiService _api;
  EmployeeService(this._api);

  Future<PaginatedResult<EmployeeModel>> getEmployees({
    String? query,
    String? departmentId,
    String status = 'active',
    int page = 1,
  }) async {
    final resp = await _api.get('/employees', params: {
      if (query != null && query.isNotEmpty) 'query': query,
      if (departmentId != null) 'department_id': departmentId,
      'status': status,
      'page': page,
      'per_page': 20,
    });
    final data = resp.data as Map<String, dynamic>;
    return PaginatedResult(
      items: (data['employees'] as List)
          .map((e) => EmployeeModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: data['total'] as int,
      pages: data['pages'] as int,
      page: data['page'] as int,
    );
  }

  Future<EmployeeModel> getEmployee(String id) async {
    final resp = await _api.get('/employees/$id');
    return EmployeeModel.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<EmployeeModel> createEmployee(Map<String, dynamic> data, {dynamic photoBytes, String? photoName}) async {
    FormData formData;
    if (photoBytes != null) {
      formData = FormData.fromMap({
        ...data,
        'photo': MultipartFile.fromBytes(photoBytes, filename: photoName ?? 'photo.jpg'),
      });
      final resp = await _api.postMultipart('/employees', formData);
      return EmployeeModel.fromJson((resp.data as Map<String, dynamic>)['employee']);
    }
    final resp = await _api.post('/employees', data: data);
    return EmployeeModel.fromJson((resp.data as Map<String, dynamic>)['employee']);
  }

  Future<EmployeeModel> updateEmployee(String id, Map<String, dynamic> data) async {
    final resp = await _api.put('/employees/$id', data: data);
    return EmployeeModel.fromJson((resp.data as Map<String, dynamic>)['employee']);
  }

  Future<void> deleteEmployee(String id) async {
    await _api.delete('/employees/$id');
  }

  Future<List<DepartmentModel>> getDepartments() async {
    final resp = await _api.get('/employees/departments');
    return (resp.data as List)
        .map((e) => DepartmentModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<RoleModel>> getRoles() async {
    final resp = await _api.get('/employees/roles');
    return (resp.data as List)
        .map((e) => RoleModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

// ─── services/websocket_service.dart ──────────────────────────


typedef EventCallback = void Function(dynamic data);

class WebSocketService {
  io.Socket? _socket;
  final Map<String, List<EventCallback>> _listeners = {};

  void connect(String accessToken) {
    _socket = io.io(
      AppConfig.wsUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setQuery({'token': accessToken})
          .enableReconnection()
          .setReconnectionAttempts(5)
          .setReconnectionDelay(2000)
          .build(),
    );

    _socket!
      ..onConnect((_) {
        print('✅ WebSocket connected');
        _notifyListeners('connected', null);
      })
      ..onDisconnect((_) {
        print('⚠️ WebSocket disconnected');
        _notifyListeners('disconnected', null);
      })
      ..onConnectError((e) => print('WebSocket error: $e'))
      ..on('attendance.clock_in', (d) => _notifyListeners('attendance.clock_in', d))
      ..on('attendance.clock_out', (d) => _notifyListeners('attendance.clock_out', d))
      ..on('attendance.alert', (d) => _notifyListeners('attendance.alert', d))
      ..on('notification.new', (d) => _notifyListeners('notification.new', d));
  }

  void on(String event, EventCallback callback) {
    _listeners[event] = [...(_listeners[event] ?? []), callback];
  }

  void off(String event, EventCallback callback) {
    _listeners[event]?.remove(callback);
  }

  void _notifyListeners(String event, dynamic data) {
    for (final cb in _listeners[event] ?? []) {
      cb(data);
    }
  }

  void disconnect() {
    _socket?.disconnect();
    _socket = null;
    _listeners.clear();
  }

  bool get isConnected => _socket?.connected ?? false;
}
