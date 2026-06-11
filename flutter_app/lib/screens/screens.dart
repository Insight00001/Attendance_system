// ═══════════════════════════════════════════════════════════════
// screens/admin/add_employee_screen.dart
// ═══════════════════════════════════════════════════════════════

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_app/bloc/auth/auth_bloc.dart';
import 'package:flutter_app/config/routes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../bloc/employee/employee_bloc.dart';
import '../../models/models.dart';
import '../../themes/app_theme.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/loading_overlay.dart';



import 'package:intl/intl.dart';
import '../../bloc/attendance/attendance_bloc.dart';
import '../../widgets/attendance/attendance_row.dart';

class AddEmployeeScreen extends StatefulWidget {
  const AddEmployeeScreen({super.key});
  @override
  State<AddEmployeeScreen> createState() => _AddEmployeeScreenState();
}

class _AddEmployeeScreenState extends State<AddEmployeeScreen> {
  final _formKey      = GlobalKey<FormState>();
  final _firstName    = TextEditingController();
  final _lastName     = TextEditingController();
  final _email        = TextEditingController();
  final _phone        = TextEditingController();
  final _jobTitle     = TextEditingController();
  String _gender      = 'prefer_not_to_say';
  String? _deptId;
  String? _roleId;
  Uint8List? _photoBytes;
  String? _photoName;
  List<DepartmentModel> _departments = [];
  List<RoleModel> _roles = [];

  @override
  void initState() {
    super.initState();
    context.read<EmployeeBloc>().add(EmployeeLoadDepartments());
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() { _photoBytes = bytes; _photoName = picked.name; });
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    context.read<EmployeeBloc>().add(EmployeeCreate({
      'email':      _email.text.trim(),
      'first_name': _firstName.text.trim(),
      'last_name':  _lastName.text.trim(),
      'phone':      _phone.text.trim(),
      'job_title':  _jobTitle.text.trim(),
      'gender':     _gender,
      if (_deptId != null) 'department_id': _deptId,
      if (_roleId != null) 'role_id': _roleId,
    }, photoBytes: _photoBytes, photoName: _photoName));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<EmployeeBloc, EmployeeState>(
      listener: (context, state) {
        if (state is EmployeeDepartmentsLoaded) {
          setState(() { _departments = state.departments; _roles = state.roles; });
        } else if (state is EmployeeOperationSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: AppTheme.accentGreen),
          );
          Navigator.pop(context);
        } else if (state is EmployeeError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: AppTheme.accentRed),
          );
        }
      },
      child: BlocBuilder<EmployeeBloc, EmployeeState>(
        builder: (context, state) => LoadingOverlay(
          isLoading: state is EmployeeLoading,
          child: Scaffold(
            appBar: AppBar(title: const Text('Add Employee')),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Photo Picker ──────────────────────────
                      Center(
                        child: GestureDetector(
                          onTap: _pickPhoto,
                          child: CircleAvatar(
                            radius: 52,
                            backgroundColor: const Color(0xFFEFF6FF),
                            backgroundImage: _photoBytes != null
                                ? MemoryImage(_photoBytes!) : null,
                            child: _photoBytes == null
                                ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                    const Icon(Icons.camera_alt_outlined, color: AppTheme.primaryBlue, size: 28),
                                    const SizedBox(height: 4),
                                    const Text('Add Photo', style: TextStyle(fontSize: 11, color: AppTheme.primaryBlue)),
                                  ])
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Center(
                        child: Text('Photo is used for face recognition',
                          style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                      ),
                      const SizedBox(height: 28),

                      // ── Name Row ──────────────────────────────
                      Row(children: [
                        Expanded(child: AppTextField(
                          controller: _firstName, label: 'First Name',
                          validator: (v) => (v?.isEmpty ?? true) ? 'Required' : null,
                        )),
                        const SizedBox(width: 12),
                        Expanded(child: AppTextField(
                          controller: _lastName, label: 'Last Name',
                          validator: (v) => (v?.isEmpty ?? true) ? 'Required' : null,
                        )),
                      ]),
                      const SizedBox(height: 16),

                      AppTextField(
                        controller: _email, label: 'Email Address',
                        keyboardType: TextInputType.emailAddress,
                        prefixIcon: Icons.email_outlined,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          if (!v.contains('@')) return 'Invalid email';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      Row(children: [
                        Expanded(child: AppTextField(
                          controller: _phone, label: 'Phone',
                          keyboardType: TextInputType.phone,
                          prefixIcon: Icons.phone_outlined,
                        )),
                        const SizedBox(width: 12),
                        Expanded(child: AppTextField(
                          controller: _jobTitle, label: 'Job Title',
                        )),
                      ]),
                      const SizedBox(height: 16),

                      // ── Department Dropdown ───────────────────
                      DropdownButtonFormField<String>(
                        value: _deptId,
                        hint: const Text('Select Department'),
                        decoration: const InputDecoration(labelText: 'Department'),
                        items: _departments.map((d) => DropdownMenuItem(
                          value: d.id, child: Text(d.name),
                        )).toList(),
                        onChanged: (v) => setState(() => _deptId = v),
                      ),
                      const SizedBox(height: 16),

                      // ── Role Dropdown ─────────────────────────
                      DropdownButtonFormField<String>(
                        value: _roleId,
                        hint: const Text('Select Role'),
                        decoration: const InputDecoration(labelText: 'Role'),
                        items: _roles.map((r) => DropdownMenuItem(
                          value: r.id, child: Text(r.name),
                        )).toList(),
                        onChanged: (v) => setState(() => _roleId = v),
                      ),
                      const SizedBox(height: 16),

                      // ── Gender ────────────────────────────────
                      DropdownButtonFormField<String>(
                        value: _gender,
                        decoration: const InputDecoration(labelText: 'Gender'),
                        items: const [
                          DropdownMenuItem(value: 'male', child: Text('Male')),
                          DropdownMenuItem(value: 'female', child: Text('Female')),
                          DropdownMenuItem(value: 'other', child: Text('Other')),
                          DropdownMenuItem(value: 'prefer_not_to_say', child: Text('Prefer not to say')),
                        ],
                        onChanged: (v) => setState(() => _gender = v ?? _gender),
                      ),
                      const SizedBox(height: 32),

                      AppButton(label: 'Create Employee', onPressed: _submit),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// screens/admin/employee_detail_screen.dart
// ═══════════════════════════════════════════════════════════════


class EmployeeDetailScreen extends StatefulWidget {
  final String employeeId;
  const EmployeeDetailScreen({super.key, required this.employeeId});
  @override
  State<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends State<EmployeeDetailScreen> {
  @override
  void initState() {
    super.initState();
    context.read<EmployeeBloc>().add(EmployeeLoadOne(widget.employeeId));
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<EmployeeBloc, EmployeeState>(
      builder: (context, state) {
        if (state is EmployeeLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        if (state is EmployeeError) return Scaffold(body: Center(child: Text(state.message)));
        if (state is! EmployeeDetailLoaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));

        final e = state.employee;
        return Scaffold(
          appBar: AppBar(
            title: Text(e.fullName),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppTheme.accentRed),
                onPressed: () => _confirmDelete(context, e),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // ── Profile Card ──────────────────────────────
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(children: [
                      CircleAvatar(
                        radius: 48,
                        backgroundColor: AppTheme.primaryBlue.withOpacity(0.1),
                        child: Text(e.avatarInitials,
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: AppTheme.primaryBlue)),
                      ),
                      const SizedBox(height: 16),
                      Text(e.fullName, style: AppTextStyles.heading3),
                      Text(e.jobTitle ?? 'No job title',
                        style: AppTextStyles.body.copyWith(color: const Color(0xFF64748B))),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryBlue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(e.employeeId,
                          style: const TextStyle(fontSize: 12, color: AppTheme.primaryBlue, fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Info Tiles ────────────────────────────────
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      _InfoTile(icon: Icons.email_outlined, label: 'Email', value: e.email ?? '-'),
                      _InfoTile(icon: Icons.phone_outlined, label: 'Phone', value: e.phone ?? '-'),
                      _InfoTile(icon: Icons.business_outlined, label: 'Department', value: e.department?.name ?? '-'),
                      _InfoTile(icon: Icons.badge_outlined, label: 'Role', value: e.role?.name ?? '-'),
                      _InfoTile(icon: Icons.calendar_today_outlined, label: 'Hire Date', value: e.hireDate ?? '-'),
                      _InfoTile(icon: Icons.access_time_outlined, label: 'Shift',
                        value: '${e.shiftStart ?? '08:00'} – ${e.shiftEnd ?? '17:00'}'),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, EmployeeModel e) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Employee'),
        content: Text('Terminate ${e.fullName}? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<EmployeeBloc>().add(EmployeeDelete(e.id));
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentRed),
            child: const Text('Terminate'),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoTile({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Icon(icon, size: 18, color: const Color(0xFF94A3B8)),
        const SizedBox(width: 12),
        Text('$label: ', style: const TextStyle(color: Color(0xFF64748B), fontSize: 13)),
        Expanded(child: Text(value,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// screens/admin/attendance_logs_screen.dart
// ═══════════════════════════════════════════════════════════════



class AttendanceLogsScreen extends StatefulWidget {
  const AttendanceLogsScreen({super.key});
  @override
  State<AttendanceLogsScreen> createState() => _AttendanceLogsScreenState();
}

class _AttendanceLogsScreenState extends State<AttendanceLogsScreen> {
  String? _statusFilter;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    context.read<AttendanceBloc>().add(AttendanceLoadLogs(
      status: _statusFilter,
      page: _page,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Filter bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Text('Attendance Logs', style: AppTextStyles.heading3),
              const Spacer(),
              DropdownButton<String?>(
                value: _statusFilter,
                hint: const Text('All Status'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('All')),
                  DropdownMenuItem(value: 'present', child: Text('Present')),
                  DropdownMenuItem(value: 'late', child: Text('Late')),
                  DropdownMenuItem(value: 'absent', child: Text('Absent')),
                ],
                onChanged: (v) { setState(() { _statusFilter = v; _page = 1; }); _load(); },
              ),
            ]),
          ),
          // Logs
          Expanded(
            child: BlocBuilder<AttendanceBloc, AttendanceState>(
              builder: (context, state) {
                if (state is AttendanceLoading) return const Center(child: CircularProgressIndicator());
                if (state is AttendanceError) return Center(child: Text(state.message));
                if (state is AttendanceLogsLoaded) {
                  final logs = state.result.items;
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: logs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => AttendanceRow(log: logs[i]),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// screens/admin/analytics_screen.dart
// ═══════════════════════════════════════════════════════════════

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<AttendanceBloc>().add(AttendanceLoadTrend(days: 30));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Analytics & Reports', style: AppTextStyles.heading2),
            const SizedBox(height: 24),
            BlocBuilder<AttendanceBloc, AttendanceState>(
              builder: (context, state) {
                if (state is AttendanceTrendLoaded) {
                  return _TrendTable(trend: state.trend);
                }
                return const Center(child: CircularProgressIndicator());
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendTable extends StatelessWidget {
  final List<Map<String, dynamic>> trend;
  const _TrendTable({required this.trend});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('Present')),
          DataColumn(label: Text('Absent')),
          DataColumn(label: Text('Late')),
          DataColumn(label: Text('Rate')),
        ],
        rows: trend.reversed.take(14).map((row) => DataRow(cells: [
          DataCell(Text(row['date'] as String? ?? '')),
          DataCell(Text('${row['present'] ?? 0}')),
          DataCell(Text('${row['absent'] ?? 0}')),
          DataCell(Text('${row['late'] ?? 0}')),
          DataCell(Text('${row['attendance_rate'] ?? 0}%')),
        ])).toList(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// screens/admin/notifications_screen.dart
// ═══════════════════════════════════════════════════════════════

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('Notifications', style: AppTextStyles.heading3),
            const SizedBox(height: 8),
            Text('No new notifications', style: TextStyle(color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// screens/auth/forgot_password_screen.dart
// ═══════════════════════════════════════════════════════════════

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  bool _sent = false;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot Password')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _sent
            ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.mark_email_read_outlined, size: 64, color: AppTheme.accentGreen),
                const SizedBox(height: 16),
                const Text('Reset link sent!', style: AppTextStyles.heading3),
                const SizedBox(height: 8),
                Text('Check ${_emailCtrl.text}', style: const TextStyle(color: Color(0xFF64748B))),
              ])
            : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('Enter your email to receive a password reset link.'),
                const SizedBox(height: 24),
                AppTextField(controller: _emailCtrl, label: 'Email', keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 20),
                AppButton(
                  label: 'Send Reset Link',
                  isLoading: _loading,
                  onPressed: () async {
                    setState(() => _loading = true);
                    await Future.delayed(const Duration(seconds: 1)); // Simulate API
                    setState(() { _loading = false; _sent = true; });
                  },
                ),
              ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// screens/employee/employee_shell.dart
// ═══════════════════════════════════════════════════════════════

class EmployeeShell extends StatefulWidget {
  final Widget child;
  const EmployeeShell({super.key, required this.child});
  @override
  State<EmployeeShell> createState() => _EmployeeShellState();
}

class _EmployeeShellState extends State<EmployeeShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) {
          setState(() => _selectedIndex = i);
          final routes = ['/employee', '/employee/attendance'];
          context.go(routes[i]);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.history_outlined), selectedIcon: Icon(Icons.history), label: 'History'),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// screens/employee/employee_dashboard_screen.dart
// ═══════════════════════════════════════════════════════════════

class EmployeeDashboardScreen extends StatelessWidget {
  const EmployeeDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    final name = authState is AuthAuthenticated
        ? authState.user.employee?.firstName ?? 'Employee'
        : 'Employee';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hello, $name 👋', style: AppTextStyles.heading2),
              Text(DateFormat('EEEE, d MMMM').format(DateTime.now()),
                style: AppTextStyles.body.copyWith(color: const Color(0xFF64748B))),
              const SizedBox(height: 32),

              // Clock in/out card
              Card(
                color: AppTheme.primaryBlue,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(children: [
                    const Icon(Icons.fingerprint, color: Colors.white, size: 64),
                    const SizedBox(height: 16),
                    const Text('Face Attendance', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    const Text('Tap to clock in or out using your face',
                      style: TextStyle(color: Colors.white70), textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => context.push(AppRoutes.camera),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppTheme.primaryBlue,
                      ),
                      child: const Text('Open Camera'),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// screens/employee/my_attendance_screen.dart
// ═══════════════════════════════════════════════════════════════

class MyAttendanceScreen extends StatefulWidget {
  const MyAttendanceScreen({super.key});
  @override
  State<MyAttendanceScreen> createState() => _MyAttendanceScreenState();
}

class _MyAttendanceScreenState extends State<MyAttendanceScreen> {
  @override
  void initState() {
    super.initState();
    context.read<AttendanceBloc>().add(AttendanceLoadLogs());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Attendance')),
      body: BlocBuilder<AttendanceBloc, AttendanceState>(
        builder: (context, state) {
          if (state is AttendanceLoading) return const Center(child: CircularProgressIndicator());
          if (state is AttendanceLogsLoaded) {
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: state.result.items.length,
              itemBuilder: (_, i) => AttendanceRow(log: state.result.items[i]),
            );
          }
          return const Center(child: Text('No attendance records found'));
        },
      ),
    );
  }
}
