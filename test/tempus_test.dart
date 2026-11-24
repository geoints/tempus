import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tempus/export.dart';
import 'package:tempus/main.dart';
import 'package:tempus/records.dart';
import 'package:tempus/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));

  test('План и факт считают каждое повторение в диапазоне', () {
    final first = DateTime(2026, 8, 3);
    final habit = Record(
      id: 1,
      kind: Kind.habit,
      title: 'Тренировка',
      date: first,
      weekdays: {DateTime.monday, DateTime.wednesday},
    ).toggle(first);
    final task = Record(id: 2, kind: Kind.task, title: 'Книга', date: first);
    final income = Record(
      id: 3,
      kind: Kind.income,
      title: 'Стипендия',
      date: first,
      amount: 4814000,
    );
    final expense = Record(
      id: 4,
      kind: Kind.expense,
      title: 'Транспорт',
      date: first,
      amount: 10050,
    );
    final summary = ProgressSummary.between(
      [habit, task, income, expense],
      first,
      shiftDay(first, 7),
    );
    expect(summary.planned, 3);
    expect(summary.completed, 1);
    expect(summary.income - summary.expense, 4803950);
    expect(habit.doneOn(shiftDay(first, 2)), isFalse);
    expect(habit.toggle(first).doneOn(first), isFalse);
  });

  test(
    'SQLite хранит вложение отдельно и восстанавливает записи и настройки',
    () async {
      final db = TempusDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final image = base64Encode([87, 24, 95]);
      final row = Record(
        id: 1,
        kind: Kind.event,
        title: 'Театр',
        date: DateTime(2026, 8, 3),
        photo: image,
      );
      await db.put(row);
      final entry = (await db.read()).records.single;
      expect(entry.hasPhoto, isTrue);
      expect(entry.photo, isNull);
      expect(await db.photo(1), image);
      await db.settings('Асан', '2026-08-10');
      final export = await db.read(includePhotos: true);
      expect(export.records.single.photo, image);
      await db.replace(const Snapshot());
      expect((await db.read()).records, isEmpty);
      await db.replace(export);
      final restored = await db.read();
      expect(restored.name, 'Асан');
      expect(restored.history, '2026-08-10');
      expect(restored.records.single.title, 'Театр');
      expect(await db.photo(1), image);
    },
  );

  test(
    'Резервная копия принимает верный пароль и отклоняет неверный',
    () async {
      final row = Record(
        id: 1,
        kind: Kind.journal,
        title: 'Первая запись',
        date: DateTime(2026, 8, 1),
        notes: 'Личные заметки',
      );
      final snapshot = Snapshot(records: [row]);
      const password = 'личный-пароль';
      final bytes = await Backup.encode(snapshot, password);
      expect(utf8.decode(bytes), isNot(contains(row.title)));
      final decoded = Backup.inspect(bytes);
      expect(Backup.isEncrypted(decoded), true);
      expect(
        (await Backup.decode(decoded, password)).toJson(),
        snapshot.toJson(),
      );
      await expectLater(
        Backup.decode(decoded, 'неверный пароль'),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
      final plain = await Backup.encode(snapshot, '');
      expect(
        (await Backup.decode(Backup.inspect(plain), '')).toJson(),
        snapshot.toJson(),
      );
    },
  );

  test('Годовая сводка создаётся в PDF с русским текстом', () async {
    final snapshot = Snapshot(
      records: [
        Record(
          id: 1,
          kind: Kind.achievement,
          title: 'Первое достижение',
          date: DateTime(2026, 8, 1),
        ),
      ],
    );
    final bytes = await yearPdf(snapshot, 2026);
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    expect(bytes.length, greaterThan(2000));
  });

  testWidgets('Навигация, создание и выполнение задачи на экране телефона', (
    tester,
  ) async {
    final db = TempusDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.runAsync(db.read);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const TempusApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('План на сегодня'), findsOneWidget);

    for (final (label, expected) in [
      ('План', 'Цели месяца'),
      ('Прогресс', 'План и факт'),
      ('Летопись', 'Поиск по летописи'),
      ('Профиль', 'Резервные копии'),
    ]) {
      await tester.tap(find.widgetWithText(NavigationDestination, label));
      await tester.pumpAndSettle();
      expect(find.text(expected), findsOneWidget);
    }
    await tester.tap(find.widgetWithText(NavigationDestination, 'Сегодня'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Добавить в план'));
    await tester.pumpAndSettle();
    expect(find.text('Новая запись'), findsOneWidget);
    expect(find.text('Название'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField).first,
      'Повторить английский',
    );
    await tester.ensureVisible(find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Повторить английский'), findsOneWidget);
    await tester.tap(find.byTooltip('Отметить выполненным'));
    await tester.pumpAndSettle();
    expect(find.text('1 из 1'), findsOneWidget);
    expect(
      (await tester.runAsync(db.read))!.records.single.checked,
      isNotEmpty,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
