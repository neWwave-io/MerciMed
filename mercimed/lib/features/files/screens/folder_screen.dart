import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FolderScreen extends ConsumerWidget {
  final String folderId;

  const FolderScreen({required this.folderId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Folder')),
      body: Center(
        child: Text('Folder $folderId — coming in Session 5'),
      ),
    );
  }
}
