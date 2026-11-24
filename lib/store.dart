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
  int get schemaVersion => 1;

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
    },
  );

  Future<Snapshot> read() => transaction(() async {
    final settings = await customSelect(
      'SELECT name, history FROM settings WHERE id = 1',
    ).getSingleOrNull();
    final items = await customSelect(
      'SELECT payload, photo IS NOT NULL AS has_photo FROM records ORDER BY id',
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

  Future<void> put(Record record) => customStatement(
    'INSERT INTO records (id, payload, photo) VALUES (?, ?, ?) '
    'ON CONFLICT(id) DO UPDATE SET payload = excluded.payload, photo = excluded.photo',
    [
      record.id,
      jsonEncode({...record.toJson(), 'photo': null}),
      record.photo,
    ],
  );

  Future<void> remove(int id) =>
      customStatement('DELETE FROM records WHERE id = ?', [id]);

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

final archiveCoverProvider = FutureProvider.autoDispose.family<Uint8List?, int>(
  (ref, id) async {
    final encoded = await ref.watch(databaseProvider).photo(id);
    return encoded == null ? null : compute(base64Decode, encoded);
  },
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
      ref.invalidate(archiveCoverProvider(updated.id));
    }
  });

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
    ref.invalidate(archiveCoverProvider(id));
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
