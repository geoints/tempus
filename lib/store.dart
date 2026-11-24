import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'records.dart';
import 'reminders.dart';

class TempusDatabase extends GeneratedDatabase {
  TempusDatabase(super.executor);

  factory TempusDatabase.local() => TempusDatabase(
    LazyDatabase(() async {
      final folder = await getApplicationDocumentsDirectory();
      return NativeDatabase.createInBackground(
        File('${folder.path}/tempus.sqlite'),
      );
    }),
  );

  @override
  int get schemaVersion => 2;

  @override
  Iterable<TableInfo> get allTables => const [];

  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement(
        'CREATE TABLE records (id INTEGER PRIMARY KEY, payload TEXT NOT NULL, photo TEXT)',
      );
      await customStatement(
        'CREATE TABLE settings (id INTEGER PRIMARY KEY CHECK (id = 1), name TEXT NOT NULL, history TEXT NOT NULL)',
      );
      await _createAlbumTable();
    },
    onUpgrade: (migrator, from, to) => transaction(() async {
      if (from >= 2) return;
      await _createAlbumTable();
      final old = await customSelect(
        'SELECT id FROM records WHERE photo IS NOT NULL',
      ).get();
      for (final row in old) {
        final id = row.read<int>('id');
        final encoded = await photo(id);
        if (encoded == null) continue;
        try {
          await _insertPhoto(id, AlbumPhotoData(base64Decode(encoded)));
          await customStatement(
            'UPDATE records SET photo = NULL WHERE id = ?',
            [id],
          );
        } on FormatException {
          // Retain an unreadable legacy attachment without blocking the upgrade.
        }
      }
    }),
  );

  Future<void> _createAlbumTable() async {
    await customStatement(
      'CREATE TABLE album_photos (id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'record_id INTEGER NOT NULL REFERENCES records(id), content BLOB NOT NULL, '
      'thumbnail BLOB, is_cover INTEGER NOT NULL DEFAULT 0)',
    );
    await customStatement(
      'CREATE INDEX album_record_idx ON album_photos(record_id)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX album_cover_idx ON album_photos(record_id) WHERE is_cover = 1',
    );
  }

  Future<List<AlbumPhoto>> album(int id) async {
    final rows = await customSelect(
      'SELECT id, is_cover FROM album_photos WHERE record_id = ? ORDER BY id',
      variables: [Variable<int>(id)],
    ).get();
    return [
      for (final row in rows)
        AlbumPhoto(row.read<int>('id'), row.read<int>('is_cover') == 1),
    ];
  }

  Future<Uint8List?> albumImage(int id, {bool thumbnail = false}) async {
    final column = thumbnail ? 'COALESCE(thumbnail, content)' : 'content';
    final row = await customSelect(
      'SELECT $column AS bytes FROM album_photos WHERE id = ?',
      variables: [Variable<int>(id)],
    ).getSingleOrNull();
    return row?.read<Uint8List>('bytes');
  }

  Future<Uint8List?> cover(int recordId) async {
    final row = await customSelect(
      'SELECT COALESCE(thumbnail, content) AS bytes FROM album_photos '
      'WHERE record_id = ? ORDER BY is_cover DESC, id LIMIT 1',
      variables: [Variable<int>(recordId)],
    ).getSingleOrNull();
    if (row != null) return row.read<Uint8List>('bytes');
    final old = await photo(recordId);
    return old == null ? null : compute(base64Decode, old);
  }

  Future<void> _insertPhoto(
    int recordId,
    AlbumPhotoData photo,
  ) => customStatement(
    'INSERT INTO album_photos (record_id, content, thumbnail, is_cover) '
    'SELECT ?, ?, ?, NOT EXISTS (SELECT 1 FROM album_photos WHERE record_id = ?) '
    'WHERE EXISTS (SELECT 1 FROM records WHERE id = ?)',
    [recordId, photo.bytes, photo.thumbnail, recordId, recordId],
  );

  Future<void> addPhoto(int recordId, AlbumPhotoData photo) async {
    await _insertPhoto(recordId, photo);
  }

  Future<void> setCover(int recordId, int photoId) => transaction(() async {
    final photos = await album(recordId);
    if (!photos.any((photo) => photo.id == photoId)) return;
    await customStatement(
      'UPDATE album_photos SET is_cover = 0 WHERE record_id = ? AND is_cover = 1',
      [recordId],
    );
    await customStatement('UPDATE album_photos SET is_cover = 1 WHERE id = ?', [
      photoId,
    ]);
  });

  Future<void> removePhoto(int recordId, int photoId) => transaction(() async {
    await customStatement(
      'DELETE FROM album_photos WHERE record_id = ? AND id = ?',
      [recordId, photoId],
    );
    await customStatement(
      'UPDATE album_photos SET is_cover = 1 WHERE id = '
      '(SELECT MIN(id) FROM album_photos WHERE record_id = ?) '
      'AND NOT EXISTS (SELECT 1 FROM album_photos WHERE record_id = ? AND is_cover = 1)',
      [recordId, recordId],
    );
  });

  Future<Snapshot> read() => transaction(() async {
    final settings = await customSelect(
      'SELECT name, history FROM settings WHERE id = 1',
    ).getSingleOrNull();
    final items = await customSelect(
      'SELECT payload, photo IS NOT NULL OR EXISTS ('
      'SELECT 1 FROM album_photos WHERE record_id = records.id) AS has_photo FROM records ORDER BY id',
    ).get();
    return Snapshot(
      name: settings?.read<String>('name') ?? '',
      history: settings?.read<String>('history') ?? '2026-08-01',
      records: items
          .map(
            (row) => Record.fromJson(
              {
                ...jsonDecode(row.read<String>('payload'))
                    as Map<String, dynamic>,
              },
              validatePhoto: false,
              hasPhoto: row.read<int>('has_photo') == 1,
            ),
          )
          .toList(growable: false),
    );
  });

  Future<String?> photo(int id) async {
    final row = await customSelect(
      'SELECT photo FROM records WHERE id = ?',
      variables: [Variable<int>(id)],
    ).getSingleOrNull();
    return row?.readNullable<String>('photo');
  }

  Future<void> put(Record record) => transaction(() async {
    await customStatement(
      'INSERT INTO records (id, payload) VALUES (?, ?) '
      'ON CONFLICT(id) DO UPDATE SET payload = excluded.payload',
      [
        record.id,
        jsonEncode({...record.toJson(), 'photo': null}),
      ],
    );
    if (record.photo case final String encoded) {
      await _insertPhoto(record.id, AlbumPhotoData(base64Decode(encoded)));
    }
  });

  Future<void> remove(int id) => transaction(() async {
    await customStatement('DELETE FROM album_photos WHERE record_id = ?', [id]);
    await customStatement('DELETE FROM records WHERE id = ?', [id]);
  });

  Future<void> settings(String name, String history) => customStatement(
    'INSERT INTO settings (id, name, history) VALUES (1, ?, ?) ON CONFLICT(id) DO UPDATE SET name = excluded.name, history = excluded.history',
    [name, history],
  );
}

final databaseProvider = Provider<TempusDatabase>((ref) {
  final db = TempusDatabase.local();
  ref.onDispose(db.close);
  return db;
});

class AlbumPhoto {
  const AlbumPhoto(this.id, this.isCover);
  final int id;
  final bool isCover;
}

class AlbumPhotoData {
  const AlbumPhotoData(this.bytes, [this.thumbnail]);
  final Uint8List bytes;
  final Uint8List? thumbnail;
}

final archiveCoverProvider = FutureProvider.autoDispose.family<Uint8List?, int>(
  (ref, id) => ref.watch(databaseProvider).cover(id),
);

final albumProvider = FutureProvider.autoDispose.family<List<AlbumPhoto>, int>(
  (ref, id) => ref.watch(databaseProvider).album(id),
);

final albumThumbProvider = FutureProvider.autoDispose.family<Uint8List?, int>(
  (ref, id) => ref.watch(databaseProvider).albumImage(id, thumbnail: true),
);

final recordsProvider = AsyncNotifierProvider<RecordsController, Snapshot>(
  RecordsController.new,
);

class RecordsController extends AsyncNotifier<Snapshot> {
  final reminders = Reminders();
  Future<void> _pending = Future.value();
  TempusDatabase get _db => ref.read(databaseProvider);

  @override
  Future<Snapshot> build() async {
    final snapshot = await ref.watch(databaseProvider).read();
    await reminders.refresh(snapshot.records);
    return snapshot;
  }

  Future<void> _apply(
    Future<void> Function(Snapshot) operation, {
    bool schedule = true,
  }) {
    final next = _pending.then((_) async {
      final previous = state.requireValue;
      await operation(previous);
      final snapshot = await _db.read();
      state = AsyncData(snapshot);
      if (schedule) await reminders.refresh(snapshot.records);
    });
    _pending = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> save(Record record) => _apply((snapshot) async {
    final nextId =
        snapshot.records.fold(0, (max, row) => row.id > max ? row.id : max) + 1;
    final updated = Record.fromJson({
      ...record.toJson(),
      if (record.id == 0) 'id': nextId,
      if (record.kind == Kind.goal && record.id != 0)
        'sessions': snapshot.records
            .firstWhere((row) => row.id == record.id)
            .sessions,
    });
    await _db.put(updated);
    if (!record.kind.isPlan && !record.kind.isMoney) {
      _refreshAlbum(updated.id);
    }
  });

  void _refreshAlbum(int id) {
    ref.invalidate(albumProvider(id));
    ref.invalidate(archiveCoverProvider(id));
  }

  Future<void> addPhoto(int id, AlbumPhotoData photo) => _apply((_) async {
    await _db.addPhoto(id, photo);
    _refreshAlbum(id);
  }, schedule: false);

  Future<void> chooseCover(int id, int photoId) => _apply((_) async {
    await _db.setCover(id, photoId);
    _refreshAlbum(id);
  }, schedule: false);

  Future<void> removePhoto(int id, int photoId) => _apply((_) async {
    await _db.removePhoto(id, photoId);
    _refreshAlbum(id);
  }, schedule: false);

  Future<void> logGoal(int id, DateTime day) => _apply((snapshot) async {
    final goal = snapshot.records.firstWhere((row) => row.id == id);
    if (goal.kind != Kind.goal ||
        !goal.occursOn(day) ||
        dayOnly(day).isAfter(dayOnly(DateTime.now())) ||
        goal.goalCount >= maxGoalTarget) {
      return;
    }
    await _db.put(goal.withSessions([...goal.sessions, dayKey(day)]));
  });

  Future<void> undoGoal(int id, String date) => _apply((snapshot) async {
    final goal = snapshot.records.firstWhere((row) => row.id == id);
    if (goal.kind != Kind.goal || !goal.sessions.contains(date)) return;
    final sessions = [...goal.sessions]..remove(date);
    await _db.put(goal.withSessions(sessions));
  });

  Future<void> toggle(int id, DateTime day) => _apply((snapshot) {
    final record = snapshot.records.firstWhere((item) => item.id == id);
    if (record.kind == Kind.goal) return Future.value();
    return _db.put(record.toggle(day));
  });

  Future<void> remove(int id) => _apply((_) async {
    await _db.remove(id);
    _refreshAlbum(id);
  });

  Future<void> refreshReminders() {
    final next = _pending.then((_) async {
      final snapshot = state.valueOrNull;
      if (snapshot != null) await reminders.refresh(snapshot.records);
    });
    _pending = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> profile(String name, DateTime history) =>
      _apply((_) => _db.settings(name, dayKey(history)), schedule: false);
}
