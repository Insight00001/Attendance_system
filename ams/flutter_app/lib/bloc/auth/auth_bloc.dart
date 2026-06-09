import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/models.dart';
import '../../services/auth_service.dart';
import '../../services/api_service.dart';

// ── Events ────────────────────────────────────────────────────
abstract class AuthEvent {}

class AuthCheckRequested extends AuthEvent {}

class AuthLoginRequested extends AuthEvent {
  final String email;
  final String password;
  AuthLoginRequested(this.email, this.password);
}

class AuthLogoutRequested extends AuthEvent {}

// ── States ────────────────────────────────────────────────────
abstract class AuthState {}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class AuthAuthenticated extends AuthState {
  final UserModel user;
  AuthAuthenticated(this.user);
}

class AuthUnauthenticated extends AuthState {}

class AuthError extends AuthState {
  final String message;
  AuthError(this.message);
}

// ── BLoC ──────────────────────────────────────────────────────
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthService _authService;
  String? _refreshToken;

  AuthBloc(this._authService) : super(AuthInitial()) {
    on<AuthCheckRequested>(_onCheckRequested);
    on<AuthLoginRequested>(_onLoginRequested);
    on<AuthLogoutRequested>(_onLogoutRequested);
  }

  Future<void> _onCheckRequested(
      AuthCheckRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final user = await _authService.getStoredUser();
      if (user != null) {
        final fresh = await _authService.getMe();
        emit(AuthAuthenticated(fresh));
      } else {
        emit(AuthUnauthenticated());
      }
    } catch (_) {
      emit(AuthUnauthenticated());
    }
  }

  Future<void> _onLoginRequested(
      AuthLoginRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final data = await _authService.login(event.email, event.password);
      _refreshToken = data['refresh_token'] as String?;
      final user =
          UserModel.fromJson(data['user'] as Map<String, dynamic>);
      emit(AuthAuthenticated(user));
    } catch (e) {
      emit(AuthError(apiErrorMessage(e)));
    }
  }

  Future<void> _onLogoutRequested(
      AuthLogoutRequested event, Emitter<AuthState> emit) async {
    await _authService.logout(_refreshToken ?? '');
    _refreshToken = null;
    emit(AuthUnauthenticated());
  }
}
