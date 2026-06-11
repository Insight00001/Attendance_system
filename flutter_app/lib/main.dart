import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'bloc/auth/auth_bloc.dart';
import 'bloc/attendance/attendance_bloc.dart';
import 'bloc/employee/employee_bloc.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/attendance_service.dart';
import 'services/employee_service.dart';
import 'services/websocket_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  final apiService        = ApiService();
  final authService       = AuthService(apiService);
  final attendanceService = AttendanceService(apiService);
  final employeeService   = EmployeeService(apiService);
  final wsService         = WebSocketService();

  runApp(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<ApiService>(create: (_) => apiService),
        RepositoryProvider<AuthService>(create: (_) => authService),
        RepositoryProvider<AttendanceService>(create: (_) => attendanceService),
        RepositoryProvider<EmployeeService>(create: (_) => employeeService),
        RepositoryProvider<WebSocketService>(create: (_) => wsService),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>(
            create: (ctx) => AuthBloc(ctx.read<AuthService>())
              ..add(AuthCheckRequested()),
          ),
          BlocProvider<AttendanceBloc>(
            create: (ctx) =>
                AttendanceBloc(ctx.read<AttendanceService>()),
          ),
          BlocProvider<EmployeeBloc>(
            create: (ctx) => EmployeeBloc(ctx.read<EmployeeService>()),
          ),
        ],
        child: const AttendEaseApp(),
      ),
    ),
  );
}
