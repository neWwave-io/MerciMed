import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/files/providers/files_provider.dart';
import '../../../shared/models/profile.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/pill_text_field.dart';

Future<bool> showEditProfileSheet(BuildContext context, Profile? profile) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EditProfileSheet(profile: profile),
  );
  return saved ?? false;
}

class _EditProfileSheet extends ConsumerStatefulWidget {
  final Profile? profile;
  const _EditProfileSheet({required this.profile});

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  late final TextEditingController _nameCtrl;
  File? _newAvatar;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.profile?.fullName ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  String get _initial {
    final n = widget.profile?.fullName?.trim();
    if (n != null && n.isNotEmpty) return n[0].toUpperCase();
    final e = widget.profile?.email?.trim();
    if (e != null && e.isNotEmpty) return e[0].toUpperCase();
    return '?';
  }

  Future<void> _pickAvatar() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: false,
    );
    if (res == null || res.files.isEmpty) return;
    final path = res.files.single.path;
    if (path == null) return;
    setState(() => _newAvatar = File(path));
  }

  Future<void> _onSave() async {
    final newName = _nameCtrl.text.trim();
    final originalName = widget.profile?.fullName?.trim() ?? '';
    final nameChanged = newName != originalName && newName.isNotEmpty;

    if (!nameChanged && _newAvatar == null) {
      Navigator.of(context).pop(false);
      return;
    }

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authNotifierProvider.notifier).updateProfile(
            fullName: nameChanged ? newName : null,
            avatar: _newAvatar,
          );
      ref.invalidate(currentUserProfileProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      messenger.showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Profile updated.'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(
        backgroundColor: const Color(0xFFD64B4B),
        behavior: SnackBarBehavior.floating,
        content: Text(
          'Could not update profile: $e',
          style: const TextStyle(color: Colors.white),
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final bottomGap = keyboard > 0 ? keyboard : 100.0;
    final existingUrl = widget.profile?.avatarUrl;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomGap),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF6FAF8),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryDark.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Edit profile',
                  style: TextStyle(
                    color: AppTheme.primaryDark,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Update your photo and display name.',
                  style: TextStyle(
                    color: Color(0xFF4A5568),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 22),
                Center(
                  child: _AvatarPicker(
                    newAvatar: _newAvatar,
                    existingUrl: existingUrl,
                    initial: _initial,
                    onTap: _saving ? null : _pickAvatar,
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: _saving ? null : _pickAvatar,
                    child: const Text(
                      'Change photo',
                      style: TextStyle(
                        color: AppTheme.primaryDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.only(left: 6, bottom: 8),
                  child: Text(
                    'FULL NAME',
                    style: TextStyle(
                      color: Color(0xFF4A5568),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
                PillTextField(
                  controller: _nameCtrl,
                  hint: 'Your full name',
                  keyboardType: TextInputType.name,
                  textInputAction: TextInputAction.done,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        foregroundColor: const Color(0xFF4A5568),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: _saving ? null : _onSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A212B),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      icon: _saving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.check_rounded, size: 18),
                      label: Text(_saving ? 'Saving…' : 'Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarPicker extends StatelessWidget {
  final File? newAvatar;
  final String? existingUrl;
  final String initial;
  final VoidCallback? onTap;

  const _AvatarPicker({
    required this.newAvatar,
    required this.existingUrl,
    required this.initial,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const size = 104.0;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryDark.withValues(alpha: 0.12),
                    blurRadius: 20,
                    spreadRadius: -2,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
            ),
            ClipOval(
              child: _buildImage(size),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A212B),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFF6FAF8), width: 2),
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage(double size) {
    if (newAvatar != null) {
      return Image.file(
        newAvatar!,
        width: size,
        height: size,
        fit: BoxFit.cover,
      );
    }
    if (existingUrl != null && existingUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: existingUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, _) => _fallback(size),
        errorWidget: (_, _, _) => _fallback(size),
      );
    }
    return _fallback(size);
  }

  Widget _fallback(double size) {
    return BackdropFilter(
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
              Colors.white.withValues(alpha: 0.85),
              const Color(0xFFE3EFE9).withValues(alpha: 0.85),
            ],
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          initial,
          style: const TextStyle(
            color: AppTheme.primaryDark,
            fontSize: 38,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
