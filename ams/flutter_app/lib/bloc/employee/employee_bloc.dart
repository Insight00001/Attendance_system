import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/models.dart';
import '../../services/employee_service.dart';
import '../../services/api_service.dart';

// ── Events ────────────────────────────────────────────────────
abstract class EmployeeEvent {}

class EmployeeLoadAll extends EmployeeEvent {
  final String? query;
  final String? departmentId;
  final int page;
  EmployeeLoadAll({this.query, this.departmentId, this.page = 1});
}

class EmployeeLoadOne extends EmployeeEvent {
  final String id;
  EmployeeLoadOne(this.id);
}

class EmployeeCreate extends EmployeeEvent {
  final Map<String, dynamic> data;
  final dynamic photoBytes;
  final String? photoName;
  EmployeeCreate(this.data, {this.photoBytes, this.photoName});
}

class EmployeeUpdate extends EmployeeEvent {
  final String id;
  final Map<String, dynamic> data;
  final dynamic photoBytes;
  final String? photoName;
  EmployeeUpdate(this.id, this.data, {this.photoBytes, this.photoName});
}

class EmployeeDelete extends EmployeeEvent {
  final String id;
  EmployeeDelete(this.id);
}

class EmployeeLoadDepartments extends EmployeeEvent {}

// ── States ────────────────────────────────────────────────────
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

// ── BLoC ──────────────────────────────────────────────────────
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

  Future<void> _onLoadAll(
      EmployeeLoadAll e, Emitter<EmployeeState> emit) async {
    emit(EmployeeLoading());
    try {
      final result = await _service.getEmployees(
          query: e.query, departmentId: e.departmentId, page: e.page);
      emit(EmployeeListLoaded(result));
    } catch (err) {
      emit(EmployeeError(apiErrorMessage(err)));
    }
  }

  Future<void> _onLoadOne(
      EmployeeLoadOne e, Emitter<EmployeeState> emit) async {
    emit(EmployeeLoading());
    try {
      final emp = await _service.getEmployee(e.id);
      emit(EmployeeDetailLoaded(emp));
    } catch (err) {
      emit(EmployeeError(apiErrorMessage(err)));
    }
  }

  Future<void> _onCreate(
      EmployeeCreate e, Emitter<EmployeeState> emit) async {
    emit(EmployeeLoading());
    try {
      final emp = await _service.createEmployee(e.data,
          photoBytes: e.photoBytes, photoName: e.photoName);
      emit(EmployeeOperationSuccess('Employee created successfully',
          employee: emp));
    } catch (err) {
      emit(EmployeeError(apiErrorMessage(err)));
    }
  }

  Future<void> _onUpdate(
      EmployeeUpdate e, Emitter<EmployeeState> emit) async {
    emit(EmployeeLoading());
    try {
      final emp = await _service.updateEmployee(
        e.id,
        e.data,
        photoBytes: e.photoBytes,
        photoName: e.photoName,
      );
      emit(EmployeeOperationSuccess('Employee updated successfully',
          employee: emp));
    } catch (err) {
      emit(EmployeeError(apiErrorMessage(err)));
    }
  }

  Future<void> _onDelete(
      EmployeeDelete e, Emitter<EmployeeState> emit) async {
    emit(EmployeeLoading());
    try {
      await _service.deleteEmployee(e.id);
      emit(EmployeeOperationSuccess('Employee removed successfully'));
    } catch (err) {
      emit(EmployeeError(apiErrorMessage(err)));
    }
  }

  Future<void> _onLoadDepartments(
      EmployeeLoadDepartments e, Emitter<EmployeeState> emit) async {
    try {
      final depts = await _service.getDepartments();
      final roles = await _service.getRoles();
      emit(EmployeeDepartmentsLoaded(depts, roles));
    } catch (err) {
      emit(EmployeeError(apiErrorMessage(err)));
    }
  }
}