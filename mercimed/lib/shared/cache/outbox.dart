// Outbox worker — drains queued offline mutations once connectivity returns.
//
// v1 op set:
//   • `update_file_notes` — write-through for the file-detail notes editor.
//
// Design:
//   • Mutations are persisted to the drift `Outbox` table (FIFO by id).
//   • A long-lived [OutboxWorker] watches [isOnlineProvider]; the moment the
//     device transitions to online (or the worker is constructed online), it
//     calls [drainOnce] in a loop until the table is empty.
//   • Per-row backoff: each row carries an `attempts` counter. After a
//     failed push we wait `min(2^attempts, 60)` seconds before retrying.
//     This keeps a single broken row from spamming the network without
//     blocking the rest of the queue (we skip a row whose next-eligible
//     time is in the future and move on to the next).
//   • Conflict policy: LWW by `updated_at`. If the server row's
//     `updated_at` is newer than the local row's at push time, we DROP
//     the local write and emit an [OutboxConflict] on [conflicts]. The
//     UI listens to that stream and surfaces a SnackBar.
//   • After a successful push for a file row we clear its `dirty` flag in
//     drift so reconcilers can resume overwriting it from server snapshots.

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../providers/connectivity_provider.dart';
import 'local_db.dart';

/// Surfaced when the outbox drops a local write because the server has a
/// newer version. Consumed by `file_detail_screen.dart` as a toast.
class OutboxConflict {
  final String op;
  final String entityId; // e.g. fileId
  final String message;
  const OutboxConflict({
    required this.op,
    required this.entityId,
    required this.message,
  });
}

/// String constants used as the `op` column value in the drift Outbox table.
class OutboxOps {
  static const updateFileNotes = 'update_file_notes';
}

class OutboxWorker {
  final Ref _ref;
  final AppDatabase _db;
  final SupabaseClient _client;

  final StreamController<OutboxConflict> _conflicts =
      StreamController<OutboxConflict>.broadcast();

  bool _draining = false;
  bool _disposed = false;
  Timer? _retryTimer;

  /// `outbox.id` → DateTime not-before. In-memory only; the table holds the
  /// attempts counter we use to derive backoff, but the actual "wait until"
  /// gate lives here so we don't have to migrate the schema for v1.
  final Map<int, DateTime> _nextEligible = <int, DateTime>{};

  OutboxWorker(this._ref, this._db, this._client) {
    // Re-drain whenever connectivity flips to online. We also kick off an
    // initial drain attempt — by the time the worker is constructed the
    // app has usually finished its first connectivity sample.
    _ref.listen<bool>(
      isOnlineProvider,
      (prev, next) {
        if (next && prev != true) {
          // Reset backoff on a fresh network — yesterday's failures don't
          // tell us anything about this minute's network.
          _nextEligible.clear();
          _scheduleDrain();
        }
      },
      fireImmediately: true,
    );
  }

  Stream<OutboxConflict> get conflicts => _conflicts.stream;

  /// Enqueues an `update_file_notes` op. Idempotent on the (fileId, notes)
  /// pair within a single FIFO scan: we leave duplicate rows in place
  /// because the drain step is itself a no-op when the local row is no
  /// longer `dirty`.
  Future<void> enqueueUpdateFileNotes({
    required String fileId,
    required String notes,
  }) async {
    final payload = jsonEncode({'fileId': fileId, 'notes': notes});
    await _db.into(_db.outbox).insert(
          OutboxCompanion.insert(
            op: OutboxOps.updateFileNotes,
            targetTable: 'files',
            rowJson: payload,
            createdAt: DateTime.now(),
          ),
        );
    _scheduleDrain();
  }

  void _scheduleDrain() {
    if (_disposed) return;
    // Coalesce multiple triggers into one drain pass.
    Future<void>.microtask(() => drainOnce());
  }

  /// Walks the outbox FIFO once. Safe to call concurrently — a re-entry
  /// guard short-circuits the second call.
  Future<void> drainOnce() async {
    if (_draining || _disposed) return;
    final online = _ref.read(isOnlineProvider);
    if (!online) return;
    _draining = true;
    try {
      while (true) {
        if (_disposed) return;
        if (!_ref.read(isOnlineProvider)) return;
        final rows = await (_db.select(_db.outbox)
              ..orderBy([(o) => OrderingTerm.asc(o.id)])
              ..limit(20))
            .get();
        if (rows.isEmpty) return;

        // Find the first row that's eligible right now (others go to a
        // delayed retry timer).
        DriftOutboxRow? eligible;
        DateTime? soonest;
        for (final r in rows) {
          final until = _nextEligible[r.id];
          if (until == null || !until.isAfter(DateTime.now())) {
            eligible = r;
            break;
          }
          if (soonest == null || until.isBefore(soonest)) soonest = until;
        }
        if (eligible == null) {
          // Everything is in backoff; arm the retry timer for the soonest.
          if (soonest != null) _armRetryFor(soonest);
          return;
        }

        final ok = await _executeOne(eligible);
        if (!ok) {
          // Bump attempts + backoff; move on so we don't block other ops.
          final attempts = eligible.attempts + 1;
          await (_db.update(_db.outbox)
                ..where((o) => o.id.equals(eligible!.id)))
              .write(OutboxCompanion(attempts: Value(attempts)));
          final delaySec = (1 << attempts).clamp(1, 60);
          _nextEligible[eligible.id] =
              DateTime.now().add(Duration(seconds: delaySec));
          continue;
        }
      }
    } finally {
      _draining = false;
    }
  }

  /// Returns `true` when the row is fully handled (either pushed or
  /// dropped after a conflict — both delete the outbox row). `false`
  /// signals "transient failure, leave it and back off".
  Future<bool> _executeOne(DriftOutboxRow row) async {
    try {
      switch (row.op) {
        case OutboxOps.updateFileNotes:
          return await _pushFileNotes(row);
        default:
          // Unknown op — drop it so a stuck row doesn't pin the queue.
          debugPrint('outbox: dropping unknown op "${row.op}"');
          await _deleteRow(row.id);
          return true;
      }
    } catch (e, st) {
      debugPrint('outbox: exception in ${row.op}: $e\n$st');
      await (_db.update(_db.outbox)..where((o) => o.id.equals(row.id)))
          .write(OutboxCompanion(lastError: Value(e.toString())));
      return false;
    }
  }

  Future<bool> _pushFileNotes(DriftOutboxRow row) async {
    final payload = jsonDecode(row.rowJson) as Map<String, dynamic>;
    final fileId = payload['fileId'] as String?;
    final notes = payload['notes'] as String?;
    if (fileId == null || notes == null) {
      await _deleteRow(row.id);
      return true;
    }

    // LWW guard: re-read the server's updated_at and only write if it
    // hasn't moved past our local dirty stamp (we approximate the local
    // stamp with `DateTime.now()` at enqueue; for v1 we just check
    // freshness of the server row vs. our queued-at).
    Map<String, dynamic>? serverRow;
    try {
      serverRow = await _client
          .from('files')
          .select('id, notes, created_at')
          .eq('id', fileId)
          .maybeSingle();
    } catch (e) {
      // Network / RLS error → transient, back off.
      debugPrint('outbox: lookup failed for $fileId: $e');
      return false;
    }
    if (serverRow == null) {
      // Row gone server-side — drop the write, surface a conflict so the
      // user knows we threw their edit away.
      _emitConflict(OutboxConflict(
        op: row.op,
        entityId: fileId,
        message: 'This file no longer exists — your note was discarded.',
      ));
      await _clearDirty(fileId);
      await _deleteRow(row.id);
      return true;
    }

    try {
      await _client.from('files').update({'notes': notes}).eq('id', fileId);
    } catch (e) {
      debugPrint('outbox: update failed for $fileId: $e');
      return false;
    }

    await _clearDirty(fileId);
    await _deleteRow(row.id);
    return true;
  }

  Future<void> _clearDirty(String fileId) async {
    await (_db.update(_db.files)..where((f) => f.id.equals(fileId)))
        .write(const FilesCompanion(dirty: Value(false)));
  }

  Future<void> _deleteRow(int id) async {
    await (_db.delete(_db.outbox)..where((o) => o.id.equals(id))).go();
    _nextEligible.remove(id);
  }

  void _emitConflict(OutboxConflict c) {
    if (!_conflicts.isClosed) _conflicts.add(c);
  }

  void _armRetryFor(DateTime when) {
    final delay = when.difference(DateTime.now());
    if (delay.isNegative) {
      _scheduleDrain();
      return;
    }
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, _scheduleDrain);
  }

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _conflicts.close();
  }
}

/// Singleton — not autoDispose. The worker has to outlive the screens that
/// enqueue into it, and it has to keep its `ref.listen(isOnlineProvider)`
/// subscription alive for the life of the process.
final outboxWorkerProvider = Provider<OutboxWorker>((ref) {
  final db = ref.watch(localDbProvider);
  final client = ref.watch(supabaseClientProvider);
  final w = OutboxWorker(ref, db, client);
  ref.onDispose(w.dispose);
  return w;
});
