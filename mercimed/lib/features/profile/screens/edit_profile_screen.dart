import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/files/providers/files_provider.dart';
import '../../../shared/models/profile.dart';
import '../../../shared/theme/app_theme.dart';

/// Edit-profile route. Loads the current profile, lets the user change their
/// avatar (gallery → upload to `avatars/{uid}/avatar.jpg`), full name, date
/// of birth, gender, and phone, then upserts back into `profiles`.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  DateTime? _dob;
  String? _gender; // 'Male' | 'Female' | 'Other'
  File? _newAvatar;
  bool _saving = false;
  bool _hydrated = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _hydrate(Profile p) {
    if (_hydrated) return;
    _hydrated = true;
    _nameCtrl.text = p.fullName ?? '';
    _phoneCtrl.text = p.phone ?? '';
    _dob = p.dateOfBirth;
    _gender = p.gender;
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null) return;
    if (!mounted) return;
    setState(() => _newAvatar = File(picked.path));
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 120),
      lastDate: now,
      initialDate: _dob ?? DateTime(now.year - 30, now.month, now.day),
      helpText: 'Date of birth',
    );
    if (picked != null && mounted) setState(() => _dob = picked);
  }

  String _dobLabel() {
    if (_dob == null) return 'Pick a date';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[_dob!.month - 1]} ${_dob!.day}, ${_dob!.year}';
  }

  Future<String?> _uploadAvatar(String userId) async {
    final client = ref.read(supabaseClientProvider);
    final path = '$userId/avatar.jpg';
    final bytes = await _newAvatar!.readAsBytes();
    await client.storage.from('avatars').uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(
        contentType: 'image/jpeg',
        upsert: true,
      ),
    );
    final url = client.storage.from('avatars').getPublicUrl(path);
    // Cache-bust so CachedNetworkImage reloads after re-upload.
    return '$url?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> _save() async {
    if (_saving) return;
    final messenger = ScaffoldMessenger.of(context);
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() => _saving = true);
    try {
      final client = ref.read(supabaseClientProvider);
      String? avatarUrl;
      if (_newAvatar != null) {
        avatarUrl = await _uploadAvatar(user.id);
      }
      final payload = <String, dynamic>{
        'id': user.id,
        'full_name': _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        'gender': _gender,
        'date_of_birth': _dob?.toIso8601String().split('T').first,
        // ignore: use_null_aware_elements
        if (avatarUrl != null) 'avatar_url': avatarUrl,
      };
      await client.from('profiles').upsert(payload);
      ref.invalidate(currentUserProfileProvider);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Profile updated'),
      ));
      if (context.canPop()) context.pop();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        backgroundColor: const Color(0xFFD64B4B),
        behavior: SnackBarBehavior.floating,
        content: Text('Save failed: $e', style: const TextStyle(color: Colors.white)),
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    profileAsync.whenData((p) {
      if (p != null) _hydrate(p);
    });

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Edit profile',
          style: TextStyle(
            color: AppTheme.primaryDark,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: profileAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Failed to load profile: $e')),
          data: (p) => ListView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 140),
            children: [
              Center(
                child: _AvatarPicker(
                  url: p?.avatarUrl,
                  newFile: _newAvatar,
                  initial: _initial(p?.fullName, p?.email),
                  onTap: _pickAvatar,
                ),
              ),
              const SizedBox(height: 32),
              const _FieldLabel('Full name'),
              const SizedBox(height: 6),
              _TextField(
                controller: _nameCtrl,
                hint: 'Your full name',
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 18),
              const _FieldLabel('Date of birth'),
              const SizedBox(height: 6),
              _TapField(
                icon: Icons.cake_rounded,
                label: _dobLabel(),
                muted: _dob == null,
                onTap: _pickDob,
              ),
              const SizedBox(height: 18),
              const _FieldLabel('Gender'),
              const SizedBox(height: 6),
              _GenderSegmented(
                value: _gender,
                onChanged: (v) => setState(() => _gender = v),
              ),
              const SizedBox(height: 18),
              const _FieldLabel('Phone'),
              const SizedBox(height: 6),
              _TextField(
                controller: _phoneCtrl,
                hint: 'Optional',
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Save changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _initial(String? name, String? email) {
    final src = (name?.trim().isNotEmpty == true)
        ? name!.trim()
        : (email ?? '');
    if (src.isEmpty) return '?';
    return src[0].toUpperCase();
  }
}

// ── Avatar picker ────────────────────────────────────────────────────────────

class _AvatarPicker extends StatelessWidget {
  final String? url;
  final File? newFile;
  final String initial;
  final VoidCallback onTap;

  const _AvatarPicker({
    required this.url,
    required this.newFile,
    required this.initial,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const size = 116.0;
    Widget circle;
    if (newFile != null) {
      circle = Image.file(newFile!, width: size, height: size, fit: BoxFit.cover);
    } else if (url != null && url!.isNotEmpty) {
      circle = CachedNetworkImage(
        imageUrl: url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, _) => _fallback(),
        errorWidget: (_, _, _) => _fallback(),
      );
    } else {
      circle = _fallback();
    }
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          children: [
            ClipOval(child: SizedBox(width: size, height: size, child: circle)),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.primaryDark,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallback() => Container(
        color: const Color(0xFFE3EFE9),
        alignment: Alignment.center,
        child: Text(
          initial,
          style: const TextStyle(
            color: AppTheme.primaryDark,
            fontSize: 40,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

// ── Form atoms ───────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xFF4A5568),
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;

  const _TextField({
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primaryDark.withValues(alpha: 0.06)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        style: const TextStyle(
          color: AppTheme.primaryDark,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: AppTheme.primaryDark.withValues(alpha: 0.4),
          ),
          isDense: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}

class _TapField extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool muted;
  final VoidCallback onTap;
  const _TapField({
    required this.icon,
    required this.label,
    required this.muted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.primaryDark.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.primaryDark),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: muted
                        ? AppTheme.primaryDark.withValues(alpha: 0.5)
                        : AppTheme.primaryDark,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF6B7C8C),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GenderSegmented extends StatelessWidget {
  final String? value;
  final ValueChanged<String> onChanged;
  const _GenderSegmented({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primaryDark.withValues(alpha: 0.06)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (final v in const ['Male', 'Female', 'Other'])
            Expanded(child: _GenderSeg(label: v, selected: value == v, onTap: () => onChanged(v))),
        ],
      ),
    );
  }
}

class _GenderSeg extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _GenderSeg({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppTheme.primaryDark : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppTheme.primaryDark,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
