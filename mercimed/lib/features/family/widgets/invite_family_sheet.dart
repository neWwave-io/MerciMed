import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/profile.dart';
import '../../../shared/theme/app_theme.dart';
import '../providers/family_provider.dart';

const _kRelationshipTypes = [
  'Mom',
  'Dad',
  'Sister',
  'Brother',
  'Spouse',
  'Other',
];

/// Opens the family-invite UI as a full-screen modal route.
///
/// Originally a draggable bottom sheet, this got promoted to a full-screen
/// route because the keyboard + search results + nested relationship picker
/// dialog made the sheet variant cramped and the nested-modal pattern
/// fragile. The page covers the bottom nav while open, which removes any
/// reserved-height math.
Future<bool> showInviteFamilySheet(BuildContext context) async {
  final sent = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const InviteFamilyPage(),
    ),
  );
  return sent ?? false;
}

class InviteFamilyPage extends ConsumerStatefulWidget {
  const InviteFamilyPage({super.key});

  @override
  ConsumerState<InviteFamilyPage> createState() => _InviteFamilyPageState();
}

class _InviteFamilyPageState extends ConsumerState<InviteFamilyPage> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      setState(() => _query = v.trim());
    });
  }

  Future<void> _pickRelationshipAndSend(Profile target) async {
    final relationship = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => _RelationshipPickerDialog(target: target),
    );
    if (!mounted || relationship == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(familyNotifierProvider.notifier)
        .sendInviteByUserId(
          targetUserId: target.id,
          relationshipType: relationship,
        );
    if (!mounted) return;
    if (result.success) {
      Navigator.of(context).pop(true);
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          'Request sent to ${target.fullName?.trim().isNotEmpty == true ? target.fullName : target.email ?? "user"}.',
        ),
      ));
    } else {
      messenger.showSnackBar(SnackBar(
        backgroundColor: const Color(0xFFD64B4B),
        behavior: SnackBarBehavior.floating,
        content: Text(
          result.errorMessage ?? 'Could not send request.',
          style: const TextStyle(color: Colors.white),
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final searchAsync = ref.watch(userSearchProvider(_query));

    return Scaffold(
      backgroundColor: const Color(0xFFF6FAF8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6FAF8),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
        ),
        title: const Text(
          'Add family member',
          style: TextStyle(
            color: AppTheme.primaryDark,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Search a member by name or email. Tap to send a request.",
                    style: TextStyle(
                      color: Color(0xFF4A5568),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SearchField(
                    controller: _searchCtrl,
                    onChanged: _onSearchChanged,
                  ),
                ],
              ),
            ),
            Expanded(
              child: _ResultsList(
                query: _query,
                asyncResults: searchAsync,
                onTapProfile: _pickRelationshipAndSend,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _SearchField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        autofocus: true,
        onChanged: onChanged,
        style: const TextStyle(
          color: AppTheme.primaryDark,
          fontSize: 15,
        ),
        decoration: InputDecoration(
          hintText: 'Search by name or email',
          hintStyle: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 15,
          ),
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 14, right: 8),
            child: Icon(
              Icons.search_rounded,
              color: Color(0xFF6B7C8C),
              size: 20,
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          isDense: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
        ),
      ),
    );
  }
}

class _ResultsList extends StatelessWidget {
  final String query;
  final AsyncValue<List<Profile>> asyncResults;
  final void Function(Profile) onTapProfile;

  const _ResultsList({
    required this.query,
    required this.asyncResults,
    required this.onTapProfile,
  });

  String _initial(Profile p) {
    final n = p.fullName?.trim();
    if (n != null && n.isNotEmpty) return n[0].toUpperCase();
    final e = p.email?.trim();
    if (e != null && e.isNotEmpty) return e[0].toUpperCase();
    return '?';
  }

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return const _CenterMessage(
        icon: Icons.person_search_rounded,
        title: 'Find a family member',
        body: 'Type a name or email of someone who already has a MerciMed account.',
      );
    }
    return asyncResults.when(
      data: (results) {
        if (results.isEmpty) {
          return _CenterMessage(
            icon: Icons.person_off_rounded,
            title: 'No one found',
            body:
                "We couldn't find anyone matching “$query”. They might not have an account yet.",
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          itemCount: results.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final p = results[i];
            final name = p.fullName?.trim().isNotEmpty == true
                ? p.fullName!
                : p.email ?? '—';
            final secondary = p.fullName?.trim().isNotEmpty == true
                ? (p.email ?? '')
                : '';
            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onTapProfile(p),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.primaryDark.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE3EFE9),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _initial(p),
                          style: const TextStyle(
                            color: AppTheme.primaryDark,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppTheme.primaryDark,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (secondary.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                secondary,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF6B7C8C),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.add_circle_outline_rounded,
                        color: AppTheme.primaryDark,
                        size: 22,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.only(top: 32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => _CenterMessage(
        icon: Icons.error_outline_rounded,
        title: 'Search failed',
        body: '$e',
      ),
    );
  }
}

class _CenterMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _CenterMessage({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: const Color(0xFF6B7C8C)),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.primaryDark,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF6B7C8C),
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RelationshipPickerDialog extends StatefulWidget {
  final Profile target;
  const _RelationshipPickerDialog({required this.target});

  @override
  State<_RelationshipPickerDialog> createState() =>
      _RelationshipPickerDialogState();
}

class _RelationshipPickerDialogState extends State<_RelationshipPickerDialog> {
  String _type = _kRelationshipTypes.first;

  @override
  Widget build(BuildContext context) {
    final name = widget.target.fullName?.trim().isNotEmpty == true
        ? widget.target.fullName!
        : widget.target.email ?? 'this person';
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Who is $name to you?',
              style: const TextStyle(
                color: AppTheme.primaryDark,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in _kRelationshipTypes)
                  _TypeChip(
                    label: t,
                    selected: _type == t,
                    onTap: () => setState(() => _type = t),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
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
                  onPressed: () => Navigator.of(context).pop(_type),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A212B),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: const Text('Send request'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1A212B) : Colors.white,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: selected
                ? const Color(0xFF1A212B)
                : AppTheme.primaryDark.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppTheme.primaryDark,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
