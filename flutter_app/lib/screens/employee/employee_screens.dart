// ═══════════════════════════════════════════════════════════════
// screens/admin/employees_screen.dart
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../bloc/employee/employee_bloc.dart';
import '../../models/models.dart';
import '../../themes/app_theme.dart';
import '../../config/routes.dart';
import '../../config/app_config.dart';
import '../../widgets/common/app_text_field.dart';
//import '../../widgets/common/section_header.dart';

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});
  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  final _searchCtrl = TextEditingController();
  String? _selectedDepartment;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    context.read<EmployeeBloc>().add(EmployeeLoadAll(
      query: _searchCtrl.text.trim(),
      departmentId: _selectedDepartment,
      page: _page,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // ── Toolbar ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(children: [
              Expanded(
                child: AppTextField(
                  controller: _searchCtrl,
                  hint: 'Search employees…',
                  prefixIcon: Icons.search,
                  onChanged: (_) { _page = 1; _load(); },
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => context.push(AppRoutes.addEmployee).then((_) => _load()),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Employee'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                ),
              ),
            ]),
          ),

          // ── Employee Grid/List ────────────────────────────────
          Expanded(
            child: BlocBuilder<EmployeeBloc, EmployeeState>(
              builder: (context, state) {
                if (state is EmployeeLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is EmployeeError) {
                  return Center(child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: AppTheme.accentRed),
                      const SizedBox(height: 12),
                      Text(state.message),
                      TextButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ));
                }

                if (state is EmployeeListLoaded) {
                  final employees = state.result.items;
                  if (employees.isEmpty) {
                    return Center(child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text('No employees found', style: TextStyle(color: Colors.grey[500])),
                      ],
                    ));
                  }

                  return LayoutBuilder(builder: (context, constraints) {
                    final isGrid = constraints.maxWidth > 700;
                    return isGrid
                        ? _EmployeeGrid(employees: employees, onTap: (e) =>
                            context.push(AppRoutes.employeeDetailPath(e.id)))
                        : _EmployeeList(employees: employees, onTap: (e) =>
                            context.push(AppRoutes.employeeDetailPath(e.id)));
                  });
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

class _EmployeeGrid extends StatelessWidget {
  final List<EmployeeModel> employees;
  final void Function(EmployeeModel) onTap;
  const _EmployeeGrid({required this.employees, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        childAspectRatio: 0.85,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: employees.length,
      itemBuilder: (_, i) => _EmployeeCard(employee: employees[i], onTap: () => onTap(employees[i])),
    );
  }
}

class _EmployeeList extends StatelessWidget {
  final List<EmployeeModel> employees;
  final void Function(EmployeeModel) onTap;
  const _EmployeeList({required this.employees, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      itemCount: employees.length,
      itemBuilder: (_, i) {
        final e = employees[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            onTap: () => onTap(e),
            leading: _Avatar(employee: e, radius: 22),
            title: Text(e.fullName, style: AppTextStyles.bodyMed),
            subtitle: Text(e.jobTitle ?? e.department?.name ?? '', style: AppTextStyles.caption),
            trailing: _StatusBadge(status: e.employmentStatus),
          ),
        );
      },
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  final EmployeeModel employee;
  final VoidCallback onTap;
  const _EmployeeCard({required this.employee, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Avatar(employee: employee, radius: 36),
              const SizedBox(height: 12),
              Text(employee.fullName,
                style: AppTextStyles.bodyMed,
                textAlign: TextAlign.center,
                maxLines: 2, overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(employee.jobTitle ?? employee.department?.name ?? 'No role',
                style: AppTextStyles.caption.copyWith(color: const Color(0xFF64748B)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              _StatusBadge(status: employee.employmentStatus),
              const SizedBox(height: 4),
              Text(employee.employeeId,
                style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final EmployeeModel employee;
  final double radius;
  const _Avatar({required this.employee, required this.radius});

  @override
  Widget build(BuildContext context) {
    final photoUrl = employee.photoUrl;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      // Build full URL — strip leading slash if present
      final clean = photoUrl.startsWith('/') ? photoUrl.substring(1) : photoUrl;
      final fullUrl = '${AppConfig.baseUrl.replaceAll('/api/v1', '')}/uploads/$clean';
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppTheme.primaryBlue.withOpacity(0.1),
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: fullUrl,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            placeholder: (_, __) => CircularProgressIndicator(strokeWidth: 2),
            errorWidget: (_, __, ___) => Text(
              employee.avatarInitials,
              style: TextStyle(
                color: AppTheme.primaryBlue,
                fontWeight: FontWeight.w700,
                fontSize: radius * 0.7,
              ),
            ),
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppTheme.primaryBlue.withOpacity(0.15),
      child: Text(
        employee.avatarInitials,
        style: TextStyle(
          color: AppTheme.primaryBlue,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.7,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'active'     => AppTheme.accentGreen,
      'inactive'   => AppTheme.accentOrange,
      'terminated' => AppTheme.accentRed,
      'suspended'  => AppTheme.accentPurple,
      _            => const Color(0xFF94A3B8),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}