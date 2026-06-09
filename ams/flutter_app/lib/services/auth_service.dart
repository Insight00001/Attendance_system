import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_service.dart';
import '../config/app_config.dart';
import '../models/models.dart';

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
