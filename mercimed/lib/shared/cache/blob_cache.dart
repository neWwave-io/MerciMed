// Persistent disk cache for Supabase Storage blobs (PDFs + images).
//
// Replaces the previous pattern of "create a 30-minute signed URL, download
// to a temp directory on every open". Now: download once, keep it in the
// app's support directory, and let the UI read from `Image.file(...)` /
// `PDFView(filePath:)` directly on subsequent opens. The drift `BlobCache`
// table maps storagePath → localPath so we can also detect cache hits
// while offline.
//
// Eviction is not implemented yet (see TODO at the bottom of this file).
// `totalBytes()` is provided so a later phase can wire an LRU eviction
// policy.

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// drift's transitive `path` dep is what we use here; importing path directly
// keeps the call sites readable but is flagged by `depend_on_referenced_packages`.
// Suppressed because we already get the package via drift.
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_db.dart';

class BlobCache {
  final AppDatabase _db;
  final Dio _dio;
  Directory? _root;

  BlobCache(this._db, {Dio? dio}) : _dio = dio ?? Dio();

  Future<Directory> _blobsDir() async {
    if (_root != null) return _root!;
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'blobs'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _root = dir;
    return dir;
  }

  /// Returns the local file path for [storagePath], downloading via a signed
  /// URL from the given Storage [bucketName] if needed. Idempotent. Returns
  /// null if the device is offline AND the blob isn't cached yet — callers
  /// should handle that by showing a "you need to be online to load this
  /// file the first time" state.
  Future<String?> getOrDownload({
    required SupabaseClient client,
    required String storagePath,
    required String bucketName,
  }) async {
    final cached = await getCached(storagePath);
    if (cached != null) {
      await _touch(storagePath);
      return cached;
    }

    // Cache miss — try to fetch. Caller already short-circuits on the
    // offline state, but we tolerate the network failing here too.
    final localPath = await _localPathFor(storagePath);
    final localFile = File(localPath);

    String signedUrl;
    try {
      signedUrl = await client.storage
          .from(bucketName)
          .createSignedUrl(storagePath, 60 * 30); // 30 min
    } catch (_) {
      return null;
    }

    try {
      final res = await _dio.get<List<int>>(
        signedUrl,
        options: Options(
          responseType: ResponseType.bytes,
          // Don't auto-throw on 404 — caller checks for null instead.
          validateStatus: (s) => s != null && s >= 200 && s < 400,
        ),
      );
      final bytes = res.data;
      if (bytes == null || bytes.isEmpty) return null;
      await localFile.writeAsBytes(bytes, flush: true);

      final digest = sha256.convert(bytes).toString();

      await _db.into(_db.blobCache).insertOnConflictUpdate(
            BlobCacheCompanion.insert(
              storagePath: storagePath,
              localPath: localPath,
              sha256: digest,
              sizeBytes: bytes.length,
              lastUsedAt: DateTime.now(),
            ),
          );

      // Best-effort: mark as excluded from iCloud backup. The platform API
      // for setting NSURLIsExcludedFromBackupKey isn't exposed by
      // path_provider; for v1 we drop a sibling `.nobackup` marker so a
      // future migration can sweep these out. TODO(offline-v2): proper
      // platform channel.
      try {
        if (Platform.isIOS) {
          await File('$localPath.nobackup').writeAsString('1');
        }
      } catch (_) {}

      return localPath;
    } catch (_) {
      // Clean up a partial write so the next call re-downloads cleanly.
      if (await localFile.exists()) {
        try {
          await localFile.delete();
        } catch (_) {}
      }
      return null;
    }
  }

  /// Returns the local file path if cached AND the file exists on disk;
  /// otherwise null. Pure read — no network, safe to call offline.
  Future<String?> getCached(String storagePath) async {
    final row = await (_db.select(_db.blobCache)
          ..where((b) => b.storagePath.equals(storagePath)))
        .getSingleOrNull();
    if (row == null) return null;
    final f = File(row.localPath);
    if (!await f.exists()) {
      // Cache row points at a deleted file — purge it so the next call
      // re-downloads instead of returning a stale path.
      await (_db.delete(_db.blobCache)
            ..where((b) => b.storagePath.equals(storagePath)))
          .go();
      return null;
    }
    return row.localPath;
  }

  /// Evict a single entry: delete the row + the on-disk file. Tolerant of
  /// the file already being missing.
  Future<void> evict(String storagePath) async {
    final row = await (_db.select(_db.blobCache)
          ..where((b) => b.storagePath.equals(storagePath)))
        .getSingleOrNull();
    if (row == null) return;
    await (_db.delete(_db.blobCache)
          ..where((b) => b.storagePath.equals(storagePath)))
        .go();
    final f = File(row.localPath);
    if (await f.exists()) {
      try {
        await f.delete();
      } catch (_) {}
    }
    final marker = File('${row.localPath}.nobackup');
    if (await marker.exists()) {
      try {
        await marker.delete();
      } catch (_) {}
    }
  }

  /// Total bytes consumed by all cached blobs. Drives a future LRU eviction
  /// policy (TODO(offline-v2): cap at ~500 MB and trim oldest-lastUsedAt).
  Future<int> totalBytes() async {
    final all = await _db.select(_db.blobCache).get();
    var sum = 0;
    for (final r in all) {
      sum += r.sizeBytes;
    }
    return sum;
  }

  Future<void> _touch(String storagePath) async {
    await (_db.update(_db.blobCache)
          ..where((b) => b.storagePath.equals(storagePath)))
        .write(BlobCacheCompanion(lastUsedAt: Value(DateTime.now())));
  }

  /// Hash the storagePath so we get a flat, collision-free layout regardless
  /// of how nested the original path is.
  Future<String> _localPathFor(String storagePath) async {
    final dir = await _blobsDir();
    final hash = sha1.convert(storagePath.codeUnits).toString();
    final ext = p.extension(storagePath);
    return p.join(dir.path, '$hash$ext');
  }
}

/// Lifecycle-tied singleton. Lives as long as the app does.
final blobCacheProvider = Provider<BlobCache>((ref) {
  return BlobCache(ref.watch(localDbProvider));
});
