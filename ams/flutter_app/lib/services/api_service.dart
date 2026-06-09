import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_config.dart';

/// Central HTTP client with:
/// - JWT auth header injection
/// - Auto token refresh on 401
/// - Error normalization
class ApiService {
  late final Dio _dio;
  final _storage = const FlutterSecureStorage();

  ApiService() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.addAll([
      _AuthInterceptor(_storage, _dio),
      _LoggingInterceptor(),
    ]);
  }

  // ── Generic request methods ──────────────────────────────────

  Future<Response> get(String path, {Map<String, dynamic>? params}) =>
      _dio.get(path, queryParameters: params);

  /// GET that returns raw bytes (file downloads).
  Future<Response<List<int>>> getBytes(String path,
          {Map<String, dynamic>? params}) =>
      _dio.get<List<int>>(path,
          queryParameters: params,
          options: Options(responseType: ResponseType.bytes));

  Future<Response> post(String path, {dynamic data, Map<String, dynamic>? params}) =>
      _dio.post(path, data: data, queryParameters: params);

  Future<Response> put(String path, {dynamic data}) =>
      _dio.put(path, data: data);

  Future<Response> delete(String path) => _dio.delete(path);

  Future<Response> postMultipart(String path, FormData formData) =>
      _dio.post(path, data: formData,
        options: Options(contentType: 'multipart/form-data'));

  // ── Auth token management ────────────────────────────────────

  Future<void> saveTokens(String access, String refresh) async {
    await _storage.write(key: AppConfig.accessTokenKey, value: access);
    await _storage.write(key: AppConfig.refreshTokenKey, value: refresh);
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: AppConfig.accessTokenKey);
    await _storage.delete(key: AppConfig.refreshTokenKey);
    await _storage.delete(key: AppConfig.userKey);
  }

  Future<String?> getAccessToken() =>
      _storage.read(key: AppConfig.accessTokenKey);
}

// ── Auth Interceptor ──────────────────────────────────────────

class _AuthInterceptor extends Interceptor {
  final FlutterSecureStorage _storage;
  final Dio _dio;
  bool _isRefreshing = false;

  _AuthInterceptor(this._storage, this._dio);

  @override
  @override
Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
) async {
  // Skip token for auth endpoints
 if (options.path.contains('/auth/login') ||
    options.path.contains('/auth/refresh') ||
    options.path == '/settings' ||
    options.path.contains('/employees/departments') ||
    options.path.contains('/employees/roles')) {
  return handler.next(options);
}
  final token = await _storage.read(
    key: AppConfig.accessTokenKey,
  );

  if (token != null) {
    options.headers['Authorization'] = 'Bearer $token';
  }

  handler.next(options);
}
  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    // Auto-refresh on 401
    if (err.response?.statusCode == 401 && !_isRefreshing) {
      _isRefreshing = true;
      try {
        final refreshToken = await _storage.read(key: AppConfig.refreshTokenKey);
        if (refreshToken == null) {
          return handler.next(err);
        }

        final refreshDio = Dio(BaseOptions(baseUrl: AppConfig.baseUrl));
        final resp = await refreshDio.post('/auth/refresh',
            data: {'refresh_token': refreshToken});

        final newAccess  = resp.data['access_token'] as String;
        final newRefresh = resp.data['refresh_token'] as String;

        await _storage.write(key: AppConfig.accessTokenKey, value: newAccess);
        await _storage.write(key: AppConfig.refreshTokenKey, value: newRefresh);

        // Retry original request
        err.requestOptions.headers['Authorization'] = 'Bearer $newAccess';
        final retryResp = await _dio.fetch(err.requestOptions);
        return handler.resolve(retryResp);
      } catch (_) {
        // Refresh failed → force logout
        await _storage.deleteAll();
        return handler.next(err);
      } finally {
        _isRefreshing = false;
      }
    }
    handler.next(err);
  }
}

// ── Logging Interceptor ───────────────────────────────────────

class _LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // ignore: avoid_print
    print('→ ${options.method} ${options.path}');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    // ignore: avoid_print
    print('← ${response.statusCode} ${response.requestOptions.path}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // ignore: avoid_print
    print('✕ ${err.response?.statusCode} ${err.requestOptions.path}: ${err.message}');
    handler.next(err);
  }
}

/// Normalize Dio errors into readable messages
String apiErrorMessage(dynamic error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data.containsKey('error')) {
      return data['error'] as String;
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout  => 'Connection timed out. Check your network.',
      DioExceptionType.receiveTimeout     => 'Server took too long to respond.',
      DioExceptionType.connectionError    => 'Cannot connect to server.',
      DioExceptionType.badResponse        => 'Server error (${error.response?.statusCode})',
      _ => 'Network error: ${error.message}',
    };
  }
  return error.toString();
}
