import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/auth/auth_bloc.dart';
import '../../services/settings_service.dart';
import '../../services/api_service.dart';
import '../../themes/app_theme.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/loading_overlay.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settingsService = SettingsService(ApiService());

  // Company settings controllers
  final _companyNameCtrl  = TextEditingController();
  final _shiftStartCtrl   = TextEditingController();
  final _shiftEndCtrl     = TextEditingController();
  final _lateThresholdCtrl = TextEditingController();

  // Profile controllers
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl  = TextEditingController();
  final _phoneCtrl     = TextEditingController();

  // Password controllers
  final _currentPassCtrl = TextEditingController();
  final _newPassCtrl     = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  bool _loadingSettings = false;
  bool _savingCompany   = false;
  bool _savingProfile   = false;
  bool _savingPassword  = false;
  bool _savingShift     = false;

  List<dynamic> _departments = [];
  List<dynamic> _roles = [];
  final _newDeptNameCtrl = TextEditingController();
  final _newDeptCodeCtrl = TextEditingController();
  final _newRoleNameCtrl = TextEditingController();
  final _newRoleCodeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _companyNameCtrl.dispose();
    _shiftStartCtrl.dispose();
    _shiftEndCtrl.dispose();
    _lateThresholdCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _currentPassCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    _newDeptNameCtrl.dispose();
    _newDeptCodeCtrl.dispose();
    _newRoleNameCtrl.dispose();
    _newRoleCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _loadingSettings = true);
    try {
      final settings = await _settingsService.getSettings();
      final depts = await _settingsService.getDepartments();
      final roles = await _settingsService.getRoles();
      setState(() {
        _departments = depts;
        _roles = roles;
        _companyNameCtrl.text   = settings['company_name'] ?? 'AttendEase';
        _shiftStartCtrl.text    = settings['default_shift_start'] ?? '08:00';
        _shiftEndCtrl.text      = settings['default_shift_end'] ?? '17:00';
        _lateThresholdCtrl.text = '${settings['default_late_threshold'] ?? 15}';
      });

      // Pre-fill profile from auth state
      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticated) {
        final emp = authState.user.employee;
        if (emp != null) {
          _firstNameCtrl.text = emp.firstName;
          _lastNameCtrl.text  = emp.lastName;
          _phoneCtrl.text     = emp.phone ?? '';
        }
      }
    } catch (e) {
      _showError('Failed to load settings: $e');
    } finally {
      setState(() => _loadingSettings = false);
    }
  }
  Future<void> _saveCompanySettings() async {
    setState(() => _savingCompany = true);
    try {
      await _settingsService.updateSettings({
        'company_name': _companyNameCtrl.text.trim(),
      });
      _showSuccess('Company settings saved');
    } catch (e) {
      _showError(apiErrorMessage(e));
    } finally {
      setState(() => _savingCompany = false);
    }
  }

  Future<void> _saveShift() async {
    setState(() => _savingShift = true);
    try {
      await _settingsService.updateShift(
        shiftStart: _shiftStartCtrl.text.trim(),
        shiftEnd: _shiftEndCtrl.text.trim(),
        lateThreshold: int.tryParse(_lateThresholdCtrl.text.trim()),
      );
      _showSuccess('Shift settings updated for all active employees');
    } catch (e) {
      _showError(apiErrorMessage(e));
    } finally {
      setState(() => _savingShift = false);
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _savingProfile = true);
    try {
      await _settingsService.updateProfile({
        'first_name': _firstNameCtrl.text.trim(),
        'last_name':  _lastNameCtrl.text.trim(),
        'phone':      _phoneCtrl.text.trim(),
      });
      _showSuccess('Profile updated');
    } catch (e) {
      _showError(apiErrorMessage(e));
    } finally {
      setState(() => _savingProfile = false);
    }
  }

  Future<void> _changePassword() async {
    if (_newPassCtrl.text != _confirmPassCtrl.text) {
      _showError('New passwords do not match');
      return;
    }
    if (_newPassCtrl.text.length < 8) {
      _showError('Password must be at least 8 characters');
      return;
    }
    setState(() => _savingPassword = true);
    try {
      await _settingsService.changePassword(
        _currentPassCtrl.text,
        _newPassCtrl.text,
      );
      _currentPassCtrl.clear();
      _newPassCtrl.clear();
      _confirmPassCtrl.clear();
      _showSuccess('Password changed successfully');
    } catch (e) {
      _showError(apiErrorMessage(e));
    } finally {
      setState(() => _savingPassword = false);
    }
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppTheme.accentGreen,
    ));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppTheme.accentRed,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: _loadingSettings,
      child: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Settings', style: AppTextStyles.heading2),
                const SizedBox(height: 24),

                // ── Company Settings ─────────────────────────
                _SectionCard(
                  title: 'Company',
                  icon: Icons.business_outlined,
                  child: Column(children: [
                    AppTextField(
                      controller: _companyNameCtrl,
                      label: 'Company Name',
                      hint: 'e.g. ZICS Engineering',
                      prefixIcon: Icons.badge_outlined,
                    ),
                    const SizedBox(height: 16),
                    AppButton(
                      label: 'Save Company Settings',
                      isLoading: _savingCompany,
                      onPressed: _saveCompanySettings,
                      icon: Icons.save_outlined,
                    ),
                  ]),
                ),
                const SizedBox(height: 16),

                // ── Work Shift Settings ──────────────────────
                _SectionCard(
                  title: 'Default Work Shift',
                  icon: Icons.schedule_outlined,
                  subtitle: 'Applies to all active employees',
                  child: Column(children: [
                    Row(children: [
                      Expanded(
                        child: AppTextField(
                          controller: _shiftStartCtrl,
                          label: 'Shift Start',
                          hint: '08:00',
                          prefixIcon: Icons.login_outlined,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppTextField(
                          controller: _shiftEndCtrl,
                          label: 'Shift End',
                          hint: '17:00',
                          prefixIcon: Icons.logout_outlined,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: _lateThresholdCtrl,
                      label: 'Late Grace Period (minutes)',
                      hint: '15',
                      keyboardType: TextInputType.number,
                      prefixIcon: Icons.timer_outlined,
                    ),
                    const SizedBox(height: 16),
                    AppButton(
                      label: 'Apply Shift to All Employees',
                      isLoading: _savingShift,
                      onPressed: _saveShift,
                      icon: Icons.groups_outlined,
                      backgroundColor: AppTheme.accentGreen,
                    ),
                  ]),
                ),
                const SizedBox(height: 16),

                // ── Profile Settings ─────────────────────────
                _SectionCard(
                  title: 'My Profile',
                  icon: Icons.person_outline,
                  child: Column(children: [
                    Row(children: [
                      Expanded(
                        child: AppTextField(
                          controller: _firstNameCtrl,
                          label: 'First Name',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppTextField(
                          controller: _lastNameCtrl,
                          label: 'Last Name',
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: _phoneCtrl,
                      label: 'Phone',
                      keyboardType: TextInputType.phone,
                      prefixIcon: Icons.phone_outlined,
                    ),
                    const SizedBox(height: 16),
                    AppButton(
                      label: 'Save Profile',
                      isLoading: _savingProfile,
                      onPressed: _saveProfile,
                      icon: Icons.save_outlined,
                    ),
                  ]),
                ),
                const SizedBox(height: 16),

                // ── Change Password ──────────────────────────
                _SectionCard(
                  title: 'Change Password',
                  icon: Icons.lock_outline,
                  child: Column(children: [
                    AppTextField(
                      controller: _currentPassCtrl,
                      label: 'Current Password',
                      obscureText: true,
                      prefixIcon: Icons.lock_outlined,
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: _newPassCtrl,
                      label: 'New Password',
                      obscureText: true,
                      prefixIcon: Icons.lock_reset_outlined,
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: _confirmPassCtrl,
                      label: 'Confirm New Password',
                      obscureText: true,
                      prefixIcon: Icons.lock_reset_outlined,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Min 8 characters, 1 uppercase, 1 number, 1 special character',
                      style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                    ),
                    const SizedBox(height: 16),
                    AppButton(
                      label: 'Change Password',
                      isLoading: _savingPassword,
                      onPressed: _changePassword,
                      icon: Icons.security_outlined,
                      backgroundColor: AppTheme.accentOrange,
                    ),
                  ]),
                ),
                const SizedBox(height: 16),

                // ── Departments ──────────────────────────────
                _SectionCard(
                  title: 'Departments',
                  icon: Icons.business_outlined,
                  child: Column(children: [
                    ..._departments.map((d) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(d['name'] as String),
                          subtitle: Text(d['code'] as String),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: AppTheme.accentRed, size: 20),
                            onPressed: () async {
                              try {
                                await _settingsService
                                    .deleteDepartment(d['id'] as String);
                                _showSuccess('Department removed');
                                _loadSettings();
                              } catch (e) {
                                _showError(apiErrorMessage(e));
                              }
                            },
                          ),
                        )),
                    const Divider(),
                    AppButton(
                      label: 'Add Department',
                      icon: Icons.add,
                      backgroundColor: AppTheme.accentGreen,
                      onPressed: _showAddDeptDialog,
                    ),
                  ]),
                ),
                const SizedBox(height: 16),

                // ── Roles ────────────────────────────────────
                _SectionCard(
                  title: 'Roles',
                  icon: Icons.badge_outlined,
                  child: Column(children: [
                    ..._roles.map((r) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(r['name'] as String),
                          subtitle: Text(r['code'] as String),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: AppTheme.accentRed, size: 20),
                            onPressed: () async {
                              try {
                                await _settingsService
                                    .deleteRole(r['id'] as String);
                                _showSuccess('Role removed');
                                _loadSettings();
                              } catch (e) {
                                _showError(apiErrorMessage(e));
                              }
                            },
                          ),
                        )),
                    const Divider(),
                    AppButton(
                      label: 'Add Role',
                      icon: Icons.add,
                      backgroundColor: AppTheme.accentGreen,
                      onPressed: _showAddRoleDialog,
                    ),
                  ]),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Department add dialog ──────────────────────────────────
  void _showAddDeptDialog() {
  _newDeptNameCtrl.clear();
  _newDeptCodeCtrl.clear();
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Add Department'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        AppTextField(
            controller: _newDeptNameCtrl,
            label: 'Department Name'),
        const SizedBox(height: 12),
        AppTextField(
            controller: _newDeptCodeCtrl,
            label: 'Code (e.g. ENG, HR)'),
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            final name = _newDeptNameCtrl.text.trim();
            final code = _newDeptCodeCtrl.text.trim();
            if (name.isEmpty || code.isEmpty) return;
            Navigator.of(dialogContext).pop();
            try {
              await _settingsService.createDepartment(name, code);
              _showSuccess('Department added');
              _loadSettings();
            } catch (e) {
              _showError(apiErrorMessage(e));
            }
          },
          child: const Text('Add'),
        ),
      ],
    ),
  );
}

void _showAddRoleDialog() {
  _newRoleNameCtrl.clear();
  _newRoleCodeCtrl.clear();
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Add Role'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        AppTextField(
            controller: _newRoleNameCtrl,
            label: 'Role Name'),
        const SizedBox(height: 12),
        AppTextField(
            controller: _newRoleCodeCtrl,
            label: 'Code (e.g. SWE, MGR)'),
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            final name = _newRoleNameCtrl.text.trim();
            final code = _newRoleCodeCtrl.text.trim();
            if (name.isEmpty || code.isEmpty) return;
            Navigator.of(dialogContext).pop();
            try {
              await _settingsService.createRole(name, code);
              _showSuccess('Role added');
              _loadSettings();
            } catch (e) {
              _showError(apiErrorMessage(e));
            }
          },
          child: const Text('Add'),
        ),
      ],
    ),
  );
}
    
  
}

// ── Section Card Widget ────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? subtitle;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 20, color: AppTheme.primaryBlue),
              const SizedBox(width: 8),
              Text(title, style: AppTextStyles.heading3),
            ]),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF94A3B8))),
            ],
            const Divider(height: 24),
            child,
          ],
        ),
      ),
    );
  }
}