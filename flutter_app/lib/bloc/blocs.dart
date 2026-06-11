// ═══════════════════════════════════════════════════════════════
// ATTENDANCE BLOC
// ═══════════════════════════════════════════════════════════════
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/models.dart';
import '../../services/attendance_service.dart';
import '../../services/api_service.dart';

import '../../services/employee_service.dart';
// ─── bloc/attendance/attendance_event.dart ────────────────────
//part of 'attendance_bloc.dart';

abstract class AttendanceEvent {}

class AttendanceLoadToday extends AttendanceEvent {}
class AttendanceLoadSummary extends AttendanceEvent {}
class AttendanceLoadTrend extends AttendanceEvent { final int days; AttendanceLoadTrend({this.days = 30}); }
class AttendanceClockInFace extends AttendanceEvent {
  final String imageB64;
  final List<String> livenessFrames;
  AttendanceClockInFace(this.imageB64, {this.livenessFrames = const []});
}
class AttendanceClockOutFace extends AttendanceEvent {
  final String imageB64;
  AttendanceClockOutFace(this.imageB64);
}
class AttendanceLoadLogs extends AttendanceEvent {
  final String? startDate;
  final String? endDate;
  final String? status;
  final int page;
  AttendanceLoadLogs({this.startDate, this.endDate, this.status, this.page = 1});
}
class AttendanceRealTimeUpdate extends AttendanceEvent {
  final AttendanceLog log;
  AttendanceRealTimeUpdate(this.log);
}

// ─── bloc/attendance/attendance_state.dart ────────────────────
//part of 'attendance_bloc.dart';

abstract class AttendanceState {}
class AttendanceInitial extends AttendanceState {}
class AttendanceLoading extends AttendanceState {}

class AttendanceTodayLoaded extends AttendanceState {
  final List<AttendanceLog> logs;
  final DashboardSummary summary;
  AttendanceTodayLoaded(this.logs, this.summary);
}

class AttendanceTrendLoaded extends AttendanceState {
  final List<Map<String, dynamic>> trend;
  AttendanceTrendLoaded(this.trend);
}

class AttendanceLogsLoaded extends AttendanceState {
  final PaginatedResult<AttendanceLog> result;
  AttendanceLogsLoaded(this.result);
}

class AttendanceClockSuccess extends AttendanceState {
  final String message;
  final bool isLate;
  final int? lateMinutes;
  final int? workingMinutes;
  AttendanceClockSuccess({required this.message, this.isLate = false, this.lateMinutes, this.workingMinutes});
}

class AttendanceClockError extends AttendanceState {
  final String message;
  AttendanceClockError(this.message);
}

class AttendanceError extends AttendanceState {
  final String message;
  AttendanceError(this.message);
}

// ─── bloc/attendance/attendance_bloc.dart ─────────────────────


//part 'attendance_event.dart';
//part 'attendance_state.dart';

class AttendanceBloc extends Bloc<AttendanceEvent, AttendanceState> {
  final AttendanceService _service;

  AttendanceBloc(this._service) : super(AttendanceInitial()) {
    on<AttendanceLoadToday>(_onLoadToday);
    on<AttendanceLoadSummary>(_onLoadSummary);
    on<AttendanceLoadTrend>(_onLoadTrend);
    on<AttendanceClockInFace>(_onClockIn);
    on<AttendanceClockOutFace>(_onClockOut);
    on<AttendanceLoadLogs>(_onLoadLogs);
  }

  Future<void> _onLoadToday(AttendanceLoadToday e, Emitter<AttendanceState> emit) async {
    emit(AttendanceLoading());
    try {
      final logs = await _service.getTodayAttendance();
      final summary = await _service.getSummary();
      emit(AttendanceTodayLoaded(logs, summary));
    } catch (err) {
      emit(AttendanceError(apiErrorMessage(err)));
    }
  }

  Future<void> _onLoadSummary(AttendanceLoadSummary e, Emitter<AttendanceState> emit) async {
    try {
      final summary = await _service.getSummary();
      final logs = await _service.getTodayAttendance();
      emit(AttendanceTodayLoaded(logs, summary));
    } catch (err) {
      emit(AttendanceError(apiErrorMessage(err)));
    }
  }

  Future<void> _onLoadTrend(AttendanceLoadTrend e, Emitter<AttendanceState> emit) async {
    emit(AttendanceLoading());
    try {
      final trend = await _service.getDailyTrend(days: e.days);
      emit(AttendanceTrendLoaded(trend));
    } catch (err) {
      emit(AttendanceError(apiErrorMessage(err)));
    }
  }

  Future<void> _onClockIn(AttendanceClockInFace e, Emitter<AttendanceState> emit) async {
    emit(AttendanceLoading());
    try {
      final result = await _service.clockInByFace(
        imageB64: e.imageB64,
        livenessFrames: e.livenessFrames,
      );
      emit(AttendanceClockSuccess(
        message: result['message'] as String? ?? 'Clocked in successfully',
        isLate: result['is_late'] as bool? ?? false,
        lateMinutes: result['late_minutes'] as int?,
      ));
    } catch (err) {
      emit(AttendanceClockError(apiErrorMessage(err)));
    }
  }

  Future<void> _onClockOut(AttendanceClockOutFace e, Emitter<AttendanceState> emit) async {
    emit(AttendanceLoading());
    try {
      final result = await _service.clockOutByFace(e.imageB64);
      emit(AttendanceClockSuccess(
        message: result['message'] as String? ?? 'Clocked out successfully',
        workingMinutes: result['working_minutes'] as int?,
      ));
    } catch (err) {
      emit(AttendanceClockError(apiErrorMessage(err)));
    }
  }

  Future<void> _onLoadLogs(AttendanceLoadLogs e, Emitter<AttendanceState> emit) async {
    emit(AttendanceLoading());
    try {
      final result = await _service.getLogs(
        startDate: e.startDate, endDate: e.endDate,
        status: e.status, page: e.page,
      );
      emit(AttendanceLogsLoaded(result));
    } catch (err) {
      emit(AttendanceError(apiErrorMessage(err)));
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// EMPLOYEE BLOC
// ═══════════════════════════════════════════════════════════════

// ─── bloc/employee/employee_bloc.dart ─────────────────────────


// Events
abstract class EmployeeEvent {}
class EmployeeLoadAll extends EmployeeEvent {
  final String? query;
  final String? departmentId;
  final int page;
  EmployeeLoadAll({this.query, this.departmentId, this.page = 1});
}
class EmployeeLoadOne extends EmployeeEvent { final String id; EmployeeLoadOne(this.id); }
class EmployeeCreate extends EmployeeEvent {
  final Map<String, dynamic> data;
  final dynamic photoBytes;
  final String? photoName;
  EmployeeCreate(this.data, {this.photoBytes, this.photoName});
}
class EmployeeUpdate extends EmployeeEvent {
  final String id;
  final Map<String, dynamic> data;
  EmployeeUpdate(this.id, this.data);
}
class EmployeeDelete extends EmployeeEvent { final String id; EmployeeDelete(this.id); }
class EmployeeLoadDepartments extends EmployeeEvent {}

// States
abstract class EmployeeState {}
class EmployeeInitial extends EmployeeState {}
class EmployeeLoading extends EmployeeState {}
class EmployeeListLoaded extends EmployeeState {
  final PaginatedResult<EmployeeModel> result;
  EmployeeListLoaded(this.result);
}
class EmployeeDetailLoaded extends EmployeeState {
  final EmployeeModel employee;
  EmployeeDetailLoaded(this.employee);
}
class EmployeeOperationSuccess extends EmployeeState {
  final String message;
  final EmployeeModel? employee;
  EmployeeOperationSuccess(this.message, {this.employee});
}
class EmployeeDepartmentsLoaded extends EmployeeState {
  final List<DepartmentModel> departments;
  final List<RoleModel> roles;
  EmployeeDepartmentsLoaded(this.departments, this.roles);
}
class EmployeeError extends EmployeeState {
  final String message;
  EmployeeError(this.message);
}

class EmployeeBloc extends Bloc<EmployeeEvent, EmployeeState> {
  final EmployeeService _service;

  EmployeeBloc(this._service) : super(EmployeeInitial()) {
    on<EmployeeLoadAll>(_onLoadAll);
    on<EmployeeLoadOne>(_onLoadOne);
    on<EmployeeCreate>(_onCreate);
    on<EmployeeUpdate>(_onUpdate);
    on<EmployeeDelete>(_onDelete);
    on<EmployeeLoadDepartments>(_onLoadDepartments);
  }

  Future<void> _onLoadAll(EmployeeLoadAll e, Emitter<EmployeeState> emit) async {
    emit(EmployeeLoading());
    try {
      final result = await _service.getEmployees(
        query: e.query, departmentId: e.departmentId, page: e.page,
      );
      emit(EmployeeListLoaded(result));
    } catch (err) { emit(EmployeeError(apiErrorMessage(err))); }
  }

  Future<void> _onLoadOne(EmployeeLoadOne e, Emitter<EmployeeState> emit) async {
    emit(EmployeeLoading());
    try {
      final emp = await _service.getEmployee(e.id);
      emit(EmployeeDetailLoaded(emp));
    } catch (err) { emit(EmployeeError(apiErrorMessage(err))); }
  }

  Future<void> _onCreate(EmployeeCreate e, Emitter<EmployeeState> emit) async {
    emit(EmployeeLoading());
    try {
      final emp = await _service.createEmployee(e.data,
          photoBytes: e.photoBytes, photoName: e.photoName);
      emit(EmployeeOperationSuccess('Employee created successfully', employee: emp));
    } catch (err) { emit(EmployeeError(apiErrorMessage(err))); }
  }

  Future<void> _onUpdate(EmployeeUpdate e, Emitter<EmployeeState> emit) async {
    emit(EmployeeLoading());
    try {
      final emp = await _service.updateEmployee(e.id, e.data);
      emit(EmployeeOperationSuccess('Employee updated successfully', employee: emp));
    } catch (err) { emit(EmployeeError(apiErrorMessage(err))); }
  }

  Future<void> _onDelete(EmployeeDelete e, Emitter<EmployeeState> emit) async {
    emit(EmployeeLoading());
    try {
      await _service.deleteEmployee(e.id);
      emit(EmployeeOperationSuccess('Employee removed successfully'));
    } catch (err) { emit(EmployeeError(apiErrorMessage(err))); }
  }

  Future<void> _onLoadDepartments(EmployeeLoadDepartments e, Emitter<EmployeeState> emit) async {
    try {
      final depts = await _service.getDepartments();
      final roles = await _service.getRoles();
      emit(EmployeeDepartmentsLoaded(depts, roles));
    } catch (err) { emit(EmployeeError(apiErrorMessage(err))); }
  }
}
