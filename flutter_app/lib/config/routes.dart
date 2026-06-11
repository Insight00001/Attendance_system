//import 'package:flutter/material.dart';
import 'package:flutter_app/models/models.dart';
import 'package:flutter_app/screens/admin/leave_management_screen.dart';
import 'package:go_router/go_router.dart';

import '../bloc/auth/auth_bloc.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/admin/admin_shell.dart';
import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/admin/employees_screen.dart';
import '../screens/admin/employee_detail_screen.dart';
import '../screens/admin/add_employee_screen.dart';
import '../screens/admin/attendance_logs_screen.dart';
import '../screens/admin/analytics_screen.dart';
import '../screens/admin/notifications_screen.dart';
import '../screens/admin/edit_employee_screen.dart';
import '../screens/employee/employee_shell.dart';
import '../screens/employee/employee_dashboard_screen.dart';
import '../screens/employee/my_attendance_screen.dart';
import '../screens/admin/settings_screen.dart';
import '../screens/admin/rfid_management_screen.dart';
import '../screens/employee/my_leave_screen.dart';
import '../screens/attendance/camera_attendance_screen.dart';

class AppRouter {
  static GoRouter createRouter(AuthState authState) {
    return GoRouter(
      initialLocation: '/login',
      redirect: (context, state) {
        final isLoggedIn  = authState is AuthAuthenticated;
        final isLoggingIn = state.matchedLocation == '/login' ||
            state.matchedLocation == '/forgot-password';

        if (!isLoggedIn && !isLoggingIn) return '/login';
        if (isLoggedIn && isLoggingIn) {
          final role = (authState).user.role;
          return role == 'employee' ? '/employee' : '/admin';
        }
        return null;
      },
      routes: [
        GoRoute(
            path: '/login',
            builder: (_, __) => const LoginScreen()),
        GoRoute(
            path: '/forgot-password',
            builder: (_, __) => const ForgotPasswordScreen()),
        GoRoute(
            path: '/attendance/camera',
            builder: (_, __) => const CameraAttendanceScreen()),

        // ── Admin Shell ────────────────────────────────────
        ShellRoute(
          builder: (context, state, child) => AdminShell(child: child),
          routes: [
            GoRoute(
                path: '/admin',
                builder: (_, __) => const AdminDashboardScreen()),
            GoRoute(
                path: '/admin/employees',
                builder: (_, __) => const EmployeesScreen()),
            GoRoute(
                path: '/admin/employees/add',
                builder: (_, __) => const AddEmployeeScreen()),
            GoRoute(
              path: '/admin/employees/:id',
              builder: (_, state) => EmployeeDetailScreen(
                  employeeId: state.pathParameters['id']!),
            ),
            GoRoute(
              path: '/admin/employees/:id/edit',
              builder: (_, state) => EditEmployeeScreen(
                  employee: state.extra as EmployeeModel),
            ),
            GoRoute(
                path: '/admin/attendance',
                builder: (_, __) => const AttendanceLogsScreen()),
            GoRoute(
                path: '/admin/analytics',
                builder: (_, __) => const AnalyticsScreen()),
            GoRoute(
                path: '/admin/notifications',
                builder: (_, __) => const NotificationsScreen()),
            GoRoute(
                path: '/admin/settings',
                builder: (_, __) => const SettingsScreen()),
            GoRoute(
                path: '/admin/leave',
                builder: (_, __) => const LeaveManagementScreen()),
            GoRoute(
                path: '/admin/rfid',
                builder: (_, __) => const RfidManagementScreen()),
          ],
        ),

        // ── Employee Shell ─────────────────────────────────
        ShellRoute(
          builder: (context, state, child) => EmployeeShell(child: child),
          routes: [
            GoRoute(
                path: '/employee',
                builder: (_, __) => const EmployeeDashboardScreen()),
            GoRoute(
                path: '/employee/attendance',
                builder: (_, __) => const MyAttendanceScreen()),
            GoRoute(
                path: '/employee/leave',
                builder: (_, __) => const MyLeaveScreen()),
          ],
        ),
      ],
    );
  }
}

class AppRoutes {
  static const login          = '/login';
  static const forgotPassword = '/forgot-password';
  static const adminDashboard = '/admin';
  static const employees      = '/admin/employees';
  static const addEmployee    = '/admin/employees/add';
  static const attendanceLogs = '/admin/attendance';
  static const analytics      = '/admin/analytics';
  static const notifications  = '/admin/notifications';
  static const settings       = '/admin/settings';
  static const adminLeave     = '/admin/leave';
  static const adminRfid      = '/admin/rfid';
  static const employeeDash   = '/employee';
  static const myAttendance   = '/employee/attendance';
  static const myLeave        = '/employee/leave';
  static const camera         = '/attendance/camera';

  static String employeeDetailPath(String id) => '/admin/employees/$id';
  static String employeeEditPath(String id) => '/admin/employees/$id/edit';
}