import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/animated_background.dart';
import '../../../shared/widgets/pill_text_field.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _emailFocus   = FocusNode();
  final _passwordFocus = FocusNode();

  bool _showPassword = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _onContinue() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;

    if (!_showPassword) {
      setState(() => _showPassword = true);
      Future.delayed(const Duration(milliseconds: 80), () {
        if (mounted) _passwordFocus.requestFocus();
      });
      return;
    }

    await ref.read(authNotifierProvider.notifier).login(
          email,
          _passwordCtrl.text,
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
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 32),

                // ── Logo ──────────────────────────────────────────
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      'm',
                      style: TextStyle(
                        color: AppTheme.teal,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // ── Heading ───────────────────────────────────────
                Text(
                  'MerciMed',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                      ),
                ),

                const SizedBox(height: 12),

                Text(
                  'Your medical record, kept quietly.\nInvitation only.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppTheme.muted,
                        height: 1.5,
                      ),
                ),

                const Spacer(),

                // ── SIGN IN label ─────────────────────────────────
                Text(
                  'SIGN IN',
                  style: Theme.of(context).textTheme.labelSmall,
                ),

                const SizedBox(height: 10),

                // ── Email field ───────────────────────────────────
                PillTextField(
                  controller: _emailCtrl,
                  focusNode: _emailFocus,
                  hint: 'Email address',
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _onContinue(),
                ),

                // ── Password field (animated in) ──────────────────
                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  child: _showPassword
                      ? Column(
                          children: [
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

                // ── Error message ─────────────────────────────────
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

                // ── Continue / Sign in button ─────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: authState.isLoading ? null : _onContinue,
                    child: authState.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(_showPassword ? 'Sign in' : 'Continue'),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Footer ────────────────────────────────────────
                Center(
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(
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

                const SizedBox(height: 12),

                // ── Create account link ───────────────────────────
                Center(
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(
                        color: AppTheme.muted,
                        fontSize: 12,
                      ),
                      children: [
                        const TextSpan(text: 'New to MerciMed? '),
                        TextSpan(
                          text: 'Create account',
                          style: const TextStyle(
                            color: AppTheme.teal,
                            fontWeight: FontWeight.w600,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => context.go('/register'),
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
    if (msg.contains('Invalid login')) return 'Incorrect email or password.';
    if (msg.contains('Email not confirmed')) return 'Check your email to confirm your account.';
    if (msg.contains('network')) return 'Connection error. Please try again.';
    return 'Something went wrong. Please try again.';
  }
}
