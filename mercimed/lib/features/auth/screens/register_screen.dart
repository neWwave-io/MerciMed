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
  final _emailCtrl    = TextEditingController();
  final _nameCtrl     = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _emailFocus   = FocusNode();
  final _nameFocus    = FocusNode();
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

                // ── CREATE ACCOUNT label ──────────────────────────
                Text(
                  'CREATE ACCOUNT',
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

                // ── Name + password (animated in) ─────────────────
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

                // ── Continue / Create account button ──────────────
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
                        : Text(_showDetails ? 'Create account' : 'Continue'),
                  ),
                ),

                const SizedBox(height: 20),

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
                    textAlign: TextAlign.center,
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
    if (msg.contains('already registered')) return 'This email is already in use.';
    if (msg.contains('password')) return 'Password must be at least 6 characters.';
    if (msg.contains('network')) return 'Connection error. Please try again.';
    return 'Something went wrong. Please try again.';
  }
}
