import 'dart:ui';

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
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _emailFocus = FocusNode();
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
            padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),

                // ── Logo ──────────────────────────────────────────
                _BrandMark(),

                const SizedBox(height: 36),

                // ── Heading ───────────────────────────────────────
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

                // ── SIGN IN label ─────────────────────────────────
                Text(
                  'SIGN IN',
                  style: TextStyle(
                    color: AppTheme.primaryDark.withValues(alpha: 0.55),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.8,
                  ),
                ),

                const SizedBox(height: 12),

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

                // ── Continue button ───────────────────────────────
                _ContinueButton(
                  label: _showPassword ? 'Sign in' : 'Continue',
                  loading: authState.isLoading,
                  onPressed: authState.isLoading ? null : _onContinue,
                ),

                const SizedBox(height: 14),

                // ── Footer ────────────────────────────────────────
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

                // ── Create account link ───────────────────────────
                Center(
                  child: Text.rich(
                    TextSpan(
                      style: const TextStyle(
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
    if (msg.contains('Email not confirmed')) {
      return 'Check your email to confirm your account.';
    }
    if (msg.contains('network')) return 'Connection error. Please try again.';
    return 'Something went wrong. Please try again.';
  }
}

class _BrandMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const size = 72.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Frosted glass disc — refracts the bubbles behind it.
          ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // Very faint top-down sheen — keeps it readable as glass
                  // without an obvious border.
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.32),
                      Colors.white.withValues(alpha: 0.12),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // The "m" sits on top of the glass.
          ShaderMask(
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppTheme.primaryDark,
                AppTheme.primaryDark.withValues(alpha: 0.82),
              ],
            ).createShader(rect),
            child: const Text(
              'm',
              style: TextStyle(
                color: Colors.white,
                fontSize: 38,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
                height: 1,
              ),
            ),
          ),
        ],
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
