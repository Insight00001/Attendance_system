import 'package:flutter/material.dart';
import '../../themes/app_theme.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';

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
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot Password')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _sent
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.mark_email_read_outlined,
                      size: 64, color: AppTheme.accentGreen),
                  const SizedBox(height: 16),
                  const Text('Reset link sent!',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text('Check ${_emailCtrl.text}',
                      style:
                          const TextStyle(color: Color(0xFF64748B))),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                      'Enter your email to receive a password reset link.'),
                  const SizedBox(height: 24),
                  AppTextField(
                    controller: _emailCtrl,
                    label: 'Email',
                    keyboardType: TextInputType.emailAddress,
                    prefixIcon: Icons.email_outlined,
                  ),
                  const SizedBox(height: 20),
                  AppButton(
                    label: 'Send Reset Link',
                    isLoading: _loading,
                    onPressed: () async {
                      if (_emailCtrl.text.isEmpty) return;
                      setState(() => _loading = true);
                      await Future.delayed(const Duration(seconds: 1));
                      setState(() {
                        _loading = false;
                        _sent = true;
                      });
                    },
                  ),
                ],
              ),
      ),
    );
  }
}
