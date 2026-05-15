import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/app_bottom_sheet.dart';

/// Bottom sheet exposing the three top-level "+" actions on the home screen.
///
/// The callbacks are wired by the caller (home_screen) since they need access
/// to `Ref`, the messenger, and the existing dialogs (new folder, file picker,
/// upload preview).
Future<void> showAddMenuSheet({
  required BuildContext context,
  required VoidCallback onNewFolder,
  required VoidCallback onFileUpload,
  required VoidCallback onFolderWithFiles,
}) {
  return showAppBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _AddMenuSheet(
      onNewFolder: () {
        Navigator.of(ctx).pop();
        onNewFolder();
      },
      onFileUpload: () {
        Navigator.of(ctx).pop();
        onFileUpload();
      },
      onFolderWithFiles: () {
        Navigator.of(ctx).pop();
        onFolderWithFiles();
      },
    ),
  );
}

class _AddMenuSheet extends StatelessWidget {
  final VoidCallback onNewFolder;
  final VoidCallback onFileUpload;
  final VoidCallback onFolderWithFiles;

  const _AddMenuSheet({
    required this.onNewFolder,
    required this.onFileUpload,
    required this.onFolderWithFiles,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 0, 8, 12),
                child: Text(
                  'Add to your records',
                  style: TextStyle(
                    color: AppTheme.primaryDark,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              _AddMenuTile(
                icon: Icons.create_new_folder_rounded,
                label: 'New folder',
                description: 'Empty folder you can add files to later.',
                onTap: onNewFolder,
              ),
              const SizedBox(height: 10),
              _AddMenuTile(
                icon: Icons.upload_file_rounded,
                label: 'Upload files',
                description: 'Saves to your "General" folder.',
                onTap: onFileUpload,
              ),
              const SizedBox(height: 10),
              _AddMenuTile(
                icon: Icons.folder_special_rounded,
                label: 'Create folder with files',
                description: 'Name a new folder, then add files to it.',
                onTap: onFolderWithFiles,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddMenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;

  const _AddMenuTile({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppTheme.primaryDark.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.teal.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: AppTheme.teal, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: AppTheme.primaryDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: const TextStyle(
                        color: Color(0xFF6B7C8C),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ],
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
