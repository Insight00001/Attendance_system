import '../services/api_service.dart';
import '../models/leave_model.dart';

class LeaveService {
  final ApiService _api;
  LeaveService(this._api);

  Future<LeaveRequest> applyLeave({
    required String startDate,
    required String endDate,
    String reason    = '',
    String leaveType = 'annual',
  }) async {
    final resp = await _api.post('/leave/apply', data: {
      'start_date':  startDate,
      'end_date':    endDate,
      'reason':      reason,
      'leave_type':  leaveType,
    });
    return LeaveRequest.fromJson(
        (resp.data as Map<String, dynamic>)['leave'] as Map<String, dynamic>);
  }

  Future<List<LeaveRequest>> getMyLeaves() async {
    final resp = await _api.get('/leave/my');
    return ((resp.data as Map<String, dynamic>)['leaves'] as List)
        .map((e) => LeaveRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> cancelLeave(String id) async {
    await _api.put('/leave/$id/cancel');
  }

  Future<Map<String, dynamic>> getAllLeaves({
    String? status,
    int page = 1,
  }) async {
    final resp = await _api.get('/leave/all', params: {
      if (status != null) 'status': status,
      'page': page,
    });
    final data = resp.data as Map<String, dynamic>;
    return {
      'leaves': ((data['leaves'] as List)
          .map((e) => LeaveRequest.fromJson(e as Map<String, dynamic>))
          .toList()),
      'total': data['total'],
      'pages': data['pages'],
    };
  }

  Future<void> reviewLeave(String id, String status) async {
    await _api.put('/leave/$id/review', data: {'status': status});
  }

  Future<int> getPendingCount() async {
    final resp = await _api.get('/leave/pending-count');
    return (resp.data as Map<String, dynamic>)['pending'] as int? ?? 0;
  }

  /// Leaves starting within the next [days] days (approved only), sorted by start date.
  Future<List<LeaveRequest>> getUpcomingLeaves({int days = 7}) async {
    final resp = await _api.get('/leave/upcoming', params: {'days': days});
    return ((resp.data as Map<String, dynamic>)['leaves'] as List)
        .map((e) => LeaveRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}