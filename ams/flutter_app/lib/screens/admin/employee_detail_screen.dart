import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../bloc/employee/employee_bloc.dart';
import '../../config/app_config.dart';
import '../../config/routes.dart';
import '../../models/models.dart';
import '../../themes/app_theme.dart';

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
    _load();
  }

  void _load() =>
      context.read<EmployeeBloc>().add(EmployeeLoadOne(widget.employeeId));

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<EmployeeBloc, EmployeeState>(
      builder: (context, state) {
        if (state is EmployeeLoading) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (state is EmployeeError) {
          return Scaffold(body: Center(child: Text(state.message)));
        }
        if (state is! EmployeeDetailLoaded) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        final e = state.employee;
        return Scaffold(
          appBar: AppBar(
            title: Text(e.fullName),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit Employee',
                onPressed: () async {
                  final result = await context.push(
                    AppRoutes.employeeEditPath(e.id),
                    extra: e,
                  );
                  if (result == true) _load();
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: AppTheme.accentRed),
                onPressed: () => _confirmDelete(context, e),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              // ── Profile Card ──────────────────────────────
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(children: [
                    _ProfilePhoto(employee: e, radius: 52),
                    const SizedBox(height: 16),
                    Text(e.fullName,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(e.jobTitle ?? 'No job title',
                        style: const TextStyle(
                            color: Color(0xFF64748B))),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(e.employeeId,
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.primaryBlue,
                              fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 16),

              // ── Info Card ─────────────────────────────────
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    _InfoTile(
                        icon: Icons.email_outlined,
                        label: 'Email',
                        value: e.email ?? '-'),
                    _InfoTile(
                        icon: Icons.phone_outlined,
                        label: 'Phone',
                        value: e.phone ?? '-'),
                    _InfoTile(
                        icon: Icons.business_outlined,
                        label: 'Department',
                        value: e.department?.name ?? '-'),
                    _InfoTile(
                        icon: Icons.badge_outlined,
                        label: 'Role',
                        value: e.role?.name ?? '-'),
                    _InfoTile(
                        icon: Icons.calendar_today_outlined,
                        label: 'Hire Date',
                        value: e.hireDate ?? '-'),
                    _InfoTile(
                        icon: Icons.access_time_outlined,
                        label: 'Shift',
                        value:
                            '${e.shiftStart ?? "08:00"} – ${e.shiftEnd ?? "17:00"}'),
                    _InfoTile(
                        icon: Icons.timer_outlined,
                        label: 'Late grace',
                        value: '${e.lateThreshold} minutes'),
                    _RfidStatusTile(cardUid: e.rfidCardUid),
                  ]),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  // ── Delete confirmation ────────────────────────────────────

  void _confirmDelete(BuildContext context, EmployeeModel e) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Employee'),
        content: Text(
            'Permanently delete ${e.fullName}? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              // 1. Close dialog using dialog's own context
              Navigator.of(dialogContext).pop();
              // 2. Dispatch delete
              context.read<EmployeeBloc>().add(EmployeeDelete(e.id));
              // 3. Navigate using GoRouter — never Navigator.pop for pages
              context.go(AppRoutes.employees);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ── Profile Photo ──────────────────────────────────────────────

class _ProfilePhoto extends StatelessWidget {
  final EmployeeModel employee;
  final double radius;
  const _ProfilePhoto({required this.employee, required this.radius});

  @override
  Widget build(BuildContext context) {
    final photoUrl = employee.photoUrl;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      final clean = photoUrl.startsWith('/')
          ? photoUrl.substring(1)
          : photoUrl;
      final serverBase = AppConfig.baseUrl.replaceAll('/api/v1', '');
      final fullUrl = '$serverBase/uploads/$clean';
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppTheme.primaryBlue.withOpacity(0.1),
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: fullUrl,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            placeholder: (_, __) =>
                const CircularProgressIndicator(strokeWidth: 2),
            errorWidget: (_, url, err) {
              debugPrint('Photo error: $url $err');
              return _Initials(
                  text: employee.avatarInitials, radius: radius);
            },
          ),
        ),
      );
    }
    return _Initials(text: employee.avatarInitials, radius: radius);
  }
}

// ── Initials Avatar ────────────────────────────────────────────

class _Initials extends StatelessWidget {
  final String text;
  final double radius;
  const _Initials({required this.text, required this.radius});

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: radius,
        backgroundColor: AppTheme.primaryBlue.withOpacity(0.15),
        child: Text(text,
            style: TextStyle(
                color: AppTheme.primaryBlue,
                fontWeight: FontWeight.w700,
                fontSize: radius * 0.7)),
      );
}

// ── RFID Status Tile ───────────────────────────────────────────

class _RfidStatusTile extends StatelessWidget {
  final String? cardUid;
  const _RfidStatusTile({this.cardUid});

  @override
  Widget build(BuildContext context) {
    final hasCard = cardUid != null && cardUid!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Icon(
          Icons.credit_card,
          size: 18,
          color: hasCard
              ? AppTheme.accentGreen
              : const Color(0xFF94A3B8),
        ),
        const SizedBox(width: 12),
        const Text('RFID Card: ',
            style:
                TextStyle(color: Color(0xFF64748B), fontSize: 13)),
        Expanded(
          child: hasCard
              ? Text(
                  cardUid!,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppTheme.accentGreen,
                      letterSpacing: 0.5),
                )
              : const Text(
                  'No card assigned',
                  style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF94A3B8),
                      fontStyle: FontStyle.italic),
                ),
        ),
      ]),
    );
  }
}

// ── Info Tile ──────────────────────────────────────────────────

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoTile(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Icon(icon, size: 18, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 12),
          Text('$label: ',
              style: const TextStyle(
                  color: Color(0xFF64748B), fontSize: 13)),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.w500, fontSize: 13),
                  overflow: TextOverflow.ellipsis)),
        ]),
      );
}