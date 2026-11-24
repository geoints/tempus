import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
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

  Future<Snapshot> read({bool includePhotos = false}) => transaction(() async {
    final settings = await customSelect(
      'SELECT name, history FROM settings WHERE id = 1',
    ).getSingleOrNull();
    final photoColumn = includePhotos ? 'photo' : 'NULL AS photo';
    final items = await customSelect(
      'SELECT payload, photo IS NOT NULL AS has_photo, $photoColumn FROM records ORDER BY id',
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
                'photo': row.readNullable<String>('photo'),
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

  Future<void> replace(Snapshot snapshot) => transaction(() async {
    await customStatement('DELETE FROM records');
    for (final item in snapshot.records) {
      await put(item);
    }
    await settings(snapshot.name, snapshot.history);
  });
}

final databaseProvider = Provider<TempusDatabase>((ref) {
  final db = TempusDatabase.local();
  ref.onDispose(db.close);
  return db;
});

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

  Future<void> save(Record record) => _apply((snapshot) {
    final nextId =
        snapshot.records.fold(0, (max, row) => row.id > max ? row.id : max) + 1;
    final updated = Record.fromJson({
      ...record.toJson(),
      if (record.id == 0) 'id': nextId,
    });
    return _db.put(updated);
  });

  Future<void> toggle(int id, DateTime day) => _apply((snapshot) {
    final record = snapshot.records.firstWhere((item) => item.id == id);
    return _db.put(record.toggle(day));
  });

  Future<void> remove(int id) => _apply((_) => _db.remove(id));

  Future<void> refreshReminders() {
    final next = _pending.then((_) async {
      final snapshot = state.valueOrNull;
      if (snapshot != null) await reminders.refresh(snapshot.records);
    });
    _pending = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<Snapshot> backupSnapshot() => _db.read(includePhotos: true);

  Future<void> restore(Snapshot snapshot) =>
      _apply((_) => _db.replace(snapshot));

  Future<void> profile(String name, DateTime history) =>
      _apply((_) => _db.settings(name, dayKey(history)), schedule: false);
}

class Backup {
  static final _cipher = AesGcm.with256bits();
  static final _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 600000,
    bits: 256,
  );
  static const maxBytes = 128 * 1024 * 1024;

  static Future<List<int>> encode(Snapshot snapshot, String password) =>
      Isolate.run(() => _encode(snapshot, password));

  static Future<List<int>> _encode(Snapshot snapshot, String password) async {
    final bytes = utf8.encode(jsonEncode(snapshot.toJson()));
    if (password.isEmpty) return bytes;
    final salt = _cipher.newNonce();
    final key = await _kdf.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final box = await _cipher.encrypt(bytes, secretKey: key);
    return utf8.encode(
      jsonEncode({
        'format': 'tempus-aes256-gcm-v1',
        'salt': base64Encode(salt),
        'nonce': base64Encode(box.nonce),
        'mac': base64Encode(box.mac.bytes),
        'data': base64Encode(box.cipherText),
      }),
    );
  }

  static Map<String, dynamic> inspect(List<int> bytes) {
    if (bytes.length > maxBytes) {
      throw const FormatException('Копия превышает 128 МБ');
    }
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  static bool isEncrypted(Map<String, dynamic> json) =>
      json['format'] == 'tempus-aes256-gcm-v1';

  static Future<Snapshot> decode(Map<String, dynamic> json, String password) =>
      Isolate.run(() => _decode(json, password));

  static Future<Snapshot> _decode(
    Map<String, dynamic> json,
    String password,
  ) async {
    if (!isEncrypted(json)) return Snapshot.fromJson(json);
    final salt = base64Decode(json['salt'] as String);
    final nonce = base64Decode(json['nonce'] as String);
    final mac = base64Decode(json['mac'] as String);
    if (salt.length != 12 || nonce.length != 12 || mac.length != 16) {
      throw const FormatException('Повреждённый заголовок резервной копии');
    }
    final key = await _kdf.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final bytes = await _cipher.decrypt(
      SecretBox(
        base64Decode(json['data'] as String),
        nonce: nonce,
        mac: Mac(mac),
      ),
      secretKey: key,
    );
    return Snapshot.fromJson(inspect(bytes));
  }
}
