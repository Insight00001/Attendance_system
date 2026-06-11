import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../bloc/auth/auth_bloc.dart';
import '../../services/settings_service.dart';
import '../../services/api_service.dart';
import '../../themes/app_theme.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/loading_overlay.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey            = GlobalKey<FormState>();
  bool _obscurePassword     = true;
  String _companyName       = 'AttendEase';  // default

  late AnimationController _animController;
  late Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _fadeIn = CurvedAnimation(
        parent: _animController, curve: Curves.easeOut);
    _animController.forward();
    _loadCompanyName();
  }

  Future<void> _loadCompanyName() async {
    try {
      final service  = SettingsService(ApiService());
      final settings = await service.getSettings();
      if (mounted) {
        setState(() {
          _companyName =
              settings['company_name'] as String? ?? 'AttendEase';
        });
      }
    } catch (_) {
      // Keep default if backend not reachable yet
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    context.read<AuthBloc>().add(AuthLoginRequested(
      _emailController.text.trim(),
      _passwordController.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthAuthenticated) {
          final role = state.user.role;
          context.go(role == 'employee' ? '/employee' : '/admin');
        } else if (state is AuthError) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(state.message),
            backgroundColor: AppTheme.accentRed,
          ));
        }
      },
      child: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          return LoadingOverlay(
            isLoading: state is AuthLoading,
            child: Scaffold(
              body: SafeArea(
                child: FadeTransition(
                  opacity: _fadeIn,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(maxWidth: 420),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment:
                              CrossAxisAlignment.stretch,
                          children: [
                            // ── Logo ─────────────────────────
                            Center(
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryBlue,
                                  borderRadius:
                                      BorderRadius.circular(20),
                                ),
                                child: const Icon(Icons.fingerprint,
                                    color: Colors.white, size: 40),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // ── Company Name ──────────────────
                            Text(
                              _companyName,
                              style: AppTextStyles.heading1.copyWith(
                                color: theme.colorScheme.onSurface,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Attendance Management System',
                              style: AppTextStyles.body.copyWith(
                                  color: const Color(0xFF64748B)),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Sign in to continue',
                              style: AppTextStyles.caption.copyWith(
                                  color: const Color(0xFF94A3B8)),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 40),

                            // ── Form ─────────────────────────
                            Form(
                              key: _formKey,
                              child: Column(children: [
                                AppTextField(
                                  controller: _emailController,
                                  label: 'Email address',
                                  hint: 'you@company.com',
                                  keyboardType:
                                      TextInputType.emailAddress,
                                  prefixIcon: Icons.email_outlined,
                                  validator: (v) {
                                    if (v == null || v.isEmpty)
                                      return 'Email is required';
                                    if (!v.contains('@'))
                                      return 'Enter a valid email';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                AppTextField(
                                  controller: _passwordController,
                                  label: 'Password',
                                  hint: '••••••••',
                                  obscureText: _obscurePassword,
                                  prefixIcon: Icons.lock_outline,
                                  suffixIcon: IconButton(
                                    icon: Icon(_obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined),
                                    onPressed: () => setState(() =>
                                        _obscurePassword =
                                            !_obscurePassword),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.isEmpty)
                                      return 'Password is required';
                                    if (v.length < 6)
                                      return 'Too short';
                                    return null;
                                  },
                                  onFieldSubmitted: (_) => _submit(),
                                ),
                                const SizedBox(height: 8),

                                // Forgot password
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () =>
                                        context.push('/forgot-password'),
                                    child: const Text('Forgot password?'),
                                  ),
                                ),
                                const SizedBox(height: 24),

                                AppButton(
                                  label: 'Sign In',
                                  onPressed: _submit,
                                  isLoading: state is AuthLoading,
                                ),
                              ]),
                            ),

                            const SizedBox(height: 32),

                            // ── Footer ────────────────────────
                            Text(
                              'Powered by AttendEase',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[400]),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}