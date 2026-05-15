import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
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
  File? _avatar;

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

  Future<void> _pickAvatar() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: false,
    );
    if (res == null || res.files.isEmpty) return;
    final path = res.files.single.path;
    if (path == null) return;
    setState(() => _avatar = File(path));
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
          avatar: _avatar,
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),

                _BrandMark(),

                const SizedBox(height: 28),

                Text(
                  'MerciMed',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontSize: 44,
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

                const SizedBox(height: 28),

                Text(
                  'CREATE ACCOUNT',
                  style: TextStyle(
                    color: AppTheme.primaryDark.withValues(alpha: 0.55),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.8,
                  ),
                ),

                const SizedBox(height: 16),

                // ── Avatar picker ─────────────────────────────────
                Center(
                  child: _AvatarPicker(
                    file: _avatar,
                    onTap: _pickAvatar,
                  ),
                ),

                const SizedBox(height: 20),

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

// ── Brand mark ───────────────────────────────────────────────────────────────

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
          ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
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

// ── Avatar picker (glass circle) ─────────────────────────────────────────────

class _AvatarPicker extends StatelessWidget {
  final File? file;
  final VoidCallback onTap;

  const _AvatarPicker({required this.file, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const size = 104.0;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Soft drop + lift shadows
                Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryDark.withValues(alpha: 0.10),
                        blurRadius: 22,
                        spreadRadius: -2,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.45),
                        blurRadius: 14,
                        spreadRadius: -4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                ),
                // Glass body — refracts the bubbles behind it.
                ClipOval(
                  child: file != null
                      ? Image.file(
                          file!,
                          width: size,
                          height: size,
                          fit: BoxFit.cover,
                        )
                      : BackdropFilter(
                          filter:
                              ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                          child: Container(
                            width: size,
                            height: size,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.white.withValues(alpha: 0.42),
                                  Colors.white.withValues(alpha: 0.18),
                                ],
                              ),
                            ),
                            child: Icon(
                              Icons.add_a_photo_outlined,
                              size: 28,
                              color: AppTheme.primaryDark
                                  .withValues(alpha: 0.65),
                            ),
                          ),
                        ),
                ),
                // Small "edit" badge in the corner when an image is set.
                if (file != null)
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryDark,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.edit_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            file == null ? 'Add a photo (optional)' : 'Change photo',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.primaryDark.withValues(alpha: 0.65),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
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
