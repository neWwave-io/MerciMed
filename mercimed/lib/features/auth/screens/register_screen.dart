import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/animated_background.dart';
import '../../../shared/widgets/pill_text_field.dart';
import '../providers/auth_provider.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _emailCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _emailFocus = FocusNode();
  final _nameFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _showDetails = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    _passwordCtrl.dispose();
    _emailFocus.dispose();
    _nameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _onContinue() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;

    if (!_showDetails) {
      setState(() => _showDetails = true);
      Future.delayed(const Duration(milliseconds: 80), () {
        if (mounted) _nameFocus.requestFocus();
      });
      return;
    }

    final name = _nameCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (name.isEmpty || password.isEmpty) return;

    await ref.read(authNotifierProvider.notifier).register(
          email,
          password,
          name,
        );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);

    return AnimatedBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),

                _BrandMark(),

                const SizedBox(height: 36),

                Text(
                  'MerciMed',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontSize: 48,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                        height: 1.05,
                      ),
                ),

                const SizedBox(height: 10),

                Text(
                  'Your medical record, kept quietly.\nInvitation only.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppTheme.primaryDark.withValues(alpha: 0.65),
                        fontWeight: FontWeight.w500,
                        height: 1.5,
                      ),
                ),

                const Spacer(),

                Text(
                  'CREATE ACCOUNT',
                  style: TextStyle(
                    color: AppTheme.primaryDark.withValues(alpha: 0.55),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.8,
                  ),
                ),

                const SizedBox(height: 12),

                PillTextField(
                  controller: _emailCtrl,
                  focusNode: _emailFocus,
                  hint: 'Email address',
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _onContinue(),
                ),

                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  child: _showDetails
                      ? Column(
                          children: [
                            const SizedBox(height: 12),
                            PillTextField(
                              controller: _nameCtrl,
                              focusNode: _nameFocus,
                              hint: 'Full name',
                              textInputAction: TextInputAction.next,
                              onSubmitted: (_) =>
                                  _passwordFocus.requestFocus(),
                            ),
                            const SizedBox(height: 12),
                            PillTextField(
                              controller: _passwordCtrl,
                              focusNode: _passwordFocus,
                              hint: 'Password',
                              obscureText: true,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _onContinue(),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),

                if (authState.hasError) ...[
                  const SizedBox(height: 10),
                  Text(
                    _friendlyError(authState.error),
                    style: const TextStyle(
                      color: Color(0xFFD64B4B),
                      fontSize: 13,
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                _ContinueButton(
                  label: _showDetails ? 'Create account' : 'Continue',
                  loading: authState.isLoading,
                  onPressed: authState.isLoading ? null : _onContinue,
                ),

                const SizedBox(height: 14),

                Center(
                  child: Text.rich(
                    TextSpan(
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                      children: [
                        const TextSpan(
                            text: 'By continuing you agree to our '),
                        TextSpan(
                          text: 'terms',
                          style: const TextStyle(
                            decoration: TextDecoration.underline,
                            decorationColor: Color(0xFF6B8A8A),
                          ),
                          recognizer: TapGestureRecognizer()..onTap = () {},
                        ),
                        const TextSpan(text: ' and '),
                        TextSpan(
                          text: 'care policy',
                          style: const TextStyle(
                            decoration: TextDecoration.underline,
                            decorationColor: Color(0xFF6B8A8A),
                          ),
                          recognizer: TapGestureRecognizer()..onTap = () {},
                        ),
                        const TextSpan(text: '.'),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                const SizedBox(height: 14),

                Center(
                  child: Text.rich(
                    TextSpan(
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: 12,
                      ),
                      children: [
                        const TextSpan(text: 'Already have an account? '),
                        TextSpan(
                          text: 'Sign in',
                          style: const TextStyle(
                            color: AppTheme.teal,
                            fontWeight: FontWeight.w600,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => context.go('/login'),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _friendlyError(Object? error) {
    final msg = error?.toString() ?? '';
    if (msg.contains('already registered')) {
      return 'This email is already in use.';
    }
    if (msg.contains('password')) {
      return 'Password must be at least 6 characters.';
    }
    if (msg.contains('network')) return 'Connection error. Please try again.';
    return 'Something went wrong. Please try again.';
  }
}

class _BrandMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: Text(
          'm',
          style: TextStyle(
            color: AppTheme.primaryDark,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  const _ContinueButton({
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryDark,
          foregroundColor: Colors.white,
          shape: const StadiumBorder(),
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Text(label),
      ),
    );
  }
}
