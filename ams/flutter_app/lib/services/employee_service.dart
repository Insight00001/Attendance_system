import 'package:dio/dio.dart';
import 'api_service.dart';
import '../models/models.dart';

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

  Future<EmployeeModel> createEmployee(
    Map<String, dynamic> data, {
    dynamic photoBytes,
    String? photoName,
  }) async {
    if (photoBytes != null) {
      final formData = FormData.fromMap({
        ...data,
        'photo': MultipartFile.fromBytes(photoBytes,
            filename: photoName ?? 'photo.jpg'),
      });
      final resp = await _api.postMultipart('/employees', formData);
      return EmployeeModel.fromJson(
          (resp.data as Map<String, dynamic>)['employee']
              as Map<String, dynamic>);
    }
    final resp = await _api.post('/employees', data: data);
    return EmployeeModel.fromJson(
        (resp.data as Map<String, dynamic>)['employee']
            as Map<String, dynamic>);
  }

  Future<EmployeeModel> updateEmployee(
    String id,
    Map<String, dynamic> data, {
    dynamic photoBytes,
    String? photoName,
  }) async {
    if (photoBytes != null) {
      // Multipart — include photo
      final formData = FormData.fromMap({
        ...data,
        'photo': MultipartFile.fromBytes(
          photoBytes,
          filename: photoName ?? 'photo.jpg',
        ),
      });
      final resp = await _api.postMultipart('/employees/$id', formData);
      return EmployeeModel.fromJson(
          (resp.data as Map<String, dynamic>)['employee']
              as Map<String, dynamic>);
    }
    // JSON only — no photo change
    final resp = await _api.put('/employees/$id', data: data);
    return EmployeeModel.fromJson(
        (resp.data as Map<String, dynamic>)['employee']
            as Map<String, dynamic>);
  }

  Future<void> deleteEmployee(String id) async {
    await _api.delete('/employees/$id?hard=true');
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