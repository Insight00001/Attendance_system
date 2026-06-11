import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/models.dart';
import '../../services/attendance_service.dart';
import '../../services/api_service.dart';

// ── Events ────────────────────────────────────────────────────
abstract class AttendanceEvent {}

class AttendanceLoadToday extends AttendanceEvent {}

class AttendanceLoadSummary extends AttendanceEvent {}

class AttendanceLoadTrend extends AttendanceEvent {
  final int days;
  AttendanceLoadTrend({this.days = 30});
}

class AttendanceLoadLateSummary extends AttendanceEvent {
  final int year;
  final int month;
  AttendanceLoadLateSummary({required this.year, required this.month});
}

class AttendanceLoadLogs extends AttendanceEvent {
  final String? startDate;
  final String? endDate;
  final String? status;
  final int page;
  AttendanceLoadLogs({this.startDate, this.endDate, this.status, this.page = 1});
}

// ── States ────────────────────────────────────────────────────
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

class AttendanceLateSummaryLoaded extends AttendanceState {
  final List<Map<String, dynamic>> summary;
  final int year;
  final int month;
  AttendanceLateSummaryLoaded(this.summary,
      {required this.year, required this.month});
}

class AttendanceLogsLoaded extends AttendanceState {
  final PaginatedResult<AttendanceLog> result;
  AttendanceLogsLoaded(this.result);
}

class AttendanceError extends AttendanceState {
  final String message;
  AttendanceError(this.message);
}

// ── BLoC ──────────────────────────────────────────────────────
class AttendanceBloc extends Bloc<AttendanceEvent, AttendanceState> {
  final AttendanceService _service;

  AttendanceBloc(this._service) : super(AttendanceInitial()) {
    on<AttendanceLoadToday>(_onLoadToday);
    on<AttendanceLoadSummary>(_onLoadSummary);
    on<AttendanceLoadTrend>(_onLoadTrend);
    on<AttendanceLoadLateSummary>(_onLoadLateSummary);
    on<AttendanceLoadLogs>(_onLoadLogs);
  }

  Future<void> _onLoadToday(
      AttendanceLoadToday e, Emitter<AttendanceState> emit) async {
    emit(AttendanceLoading());
    try {
      final logs = await _service.getTodayAttendance();
      final summary = await _service.getSummary();
      emit(AttendanceTodayLoaded(logs, summary));
    } catch (err) {
      emit(AttendanceError(apiErrorMessage(err)));
    }
  }

  Future<void> _onLoadSummary(
      AttendanceLoadSummary e, Emitter<AttendanceState> emit) async {
    try {
      final summary = await _service.getSummary();
      final logs = await _service.getTodayAttendance();
      emit(AttendanceTodayLoaded(logs, summary));
    } catch (err) {
      emit(AttendanceError(apiErrorMessage(err)));
    }
  }

Future<void> _onLoadTrend(
    AttendanceLoadTrend e, Emitter<AttendanceState> emit) async {
  // DON'T emit loading here — it wipes the summary cards
  try {
    final trend = await _service.getDailyTrend(days: e.days);
    emit(AttendanceTrendLoaded(trend));
  } catch (err) {
    // Silently fail — don't replace summary with error
    emit(AttendanceTrendLoaded([]));
  }
}
  Future<void> _onLoadLateSummary(
      AttendanceLoadLateSummary e, Emitter<AttendanceState> emit) async {
    // No loading state — keeps other analytics sections intact
    try {
      final summary =
          await _service.getMonthlyLateSummary(year: e.year, month: e.month);
      emit(AttendanceLateSummaryLoaded(summary, year: e.year, month: e.month));
    } catch (err) {
      emit(AttendanceLateSummaryLoaded(const [], year: e.year, month: e.month));
    }
  }

  Future<void> _onLoadLogs(
      AttendanceLoadLogs e, Emitter<AttendanceState> emit) async {
    emit(AttendanceLoading());
    try {
      final result = await _service.getLogs(
        startDate: e.startDate,
        endDate: e.endDate,
        status: e.status,
        page: e.page,
      );
      emit(AttendanceLogsLoaded(result));
    } catch (err) {
      emit(AttendanceError(apiErrorMessage(err)));
    }
  }
}
