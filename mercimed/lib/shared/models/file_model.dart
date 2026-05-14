class FileModel {
  final String id;
  final String userId;
  final String? folderId;
  final String fileName;
  final String? fileType;
  final String storagePath;
  final String? extractedText;
  final String aiScanStatus;
  final DateTime createdAt;

  const FileModel({
    required this.id,
    required this.userId,
    this.folderId,
    required this.fileName,
    this.fileType,
    required this.storagePath,
    this.extractedText,
    required this.aiScanStatus,
    required this.createdAt,
  });

  factory FileModel.fromJson(Map<String, dynamic> json) => FileModel(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        folderId: json['folder_id'] as String?,
        fileName: json['file_name'] as String,
        fileType: json['file_type'] as String?,
        storagePath: json['storage_path'] as String,
        extractedText: json['extracted_text'] as String?,
        aiScanStatus: json['ai_scan_status'] as String? ?? 'pending',
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'folder_id': folderId,
        'file_name': fileName,
        'file_type': fileType,
        'storage_path': storagePath,
        'extracted_text': extractedText,
        'ai_scan_status': aiScanStatus,
        'created_at': createdAt.toIso8601String(),
      };
}
