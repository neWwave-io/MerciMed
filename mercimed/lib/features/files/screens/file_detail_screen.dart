import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FileDetailScreen extends ConsumerWidget {
  final String fileId;
  const FileDetailScreen({required this.fileId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('File')),
      body: Center(child: Text('File $fileId — coming in Screen D')),
    );
  }
}
