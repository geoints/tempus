import 'dart:convert';

import 'package:drift/native.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tempus/design.dart';
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
    'Версия 1.0 сохраняет записи, настройки, фото и старый прогресс',
    () async {
      final db = TempusDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final image = base64Encode([87, 24, 95]);
      await db.settings('Асанали', '2026-08-10');
      final oldGoal =
          Record(
              id: 1,
              kind: Kind.goal,
              title: 'Зал 12 раз в месяц',
              date: DateTime(2026, 8, 31),
              area: 'Спорт',
              checked: {'2026-08-03'},
            ).toJson()
            ..remove('target')
            ..remove('sessions');
      final oldBook = Record(
        id: 2,
        kind: Kind.book,
        title: 'Книга',
        date: DateTime(2026, 8, 3),
        area: 'Творчество',
        notes: 'Конспект',
      ).toJson();
      await db.customStatement(
        'INSERT INTO records (id, payload) VALUES (?, ?)',
        [1, jsonEncode(oldGoal)],
      );
      await db.customStatement(
        'INSERT INTO records (id, payload, photo) VALUES (?, ?, ?)',
        [2, jsonEncode(oldBook), image],
      );
      final stored = await db.read();
      expect(stored.name, 'Асанали');
      expect(stored.history, '2026-08-10');
      final [goal, book] = stored.records;
      expect(goal.title, 'Зал 12 раз в месяц');
      expect(goal.goalTitle, 'Зал');
      expect(goal.area, 'Тренировки');
      expect(goal.target, 12);
      expect(goal.goalCount, 12);
      expect(book.area, 'Чтение');
      expect(book.notes, 'Конспект');
      expect(book.hasPhoto, isTrue);
      expect(book.photo, isNull);
      expect(await db.photo(2), image);
    },
  );

  test('Цель добавляет план по сроку и считает по дате каждой отметки', () {
    final goal = Record(
      id: 1,
      kind: Kind.goal,
      title: 'Дзюдо',
      target: 10,
      date: DateTime(2026, 8, 31),
    ).withSessions(['2026-08-03', '2026-08-03', '2026-08-31']);
    final early = ProgressSummary.between(
      [goal],
      DateTime(2026, 8, 1),
      DateTime(2026, 8, 9),
    );
    expect(early.planned, 0);
    expect(early.completed, 2);
    final month = ProgressSummary.between(
      [goal],
      DateTime(2026, 8, 1),
      DateTime(2026, 9, 1),
    );
    expect(month.planned, 10);
    expect(month.completed, 3);
  });

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
    final today = dayOnly(DateTime.now());
    await tester.runAsync(() async {
      await db.put(
        Record(
          id: 1,
          kind: Kind.goal,
          title: 'Зал',
          date: DateTime(today.year, today.month + 1, 0),
          target: 12,
          area: 'Тренировки',
        ),
      );
      await db.put(
        Record(id: 2, kind: Kind.event, title: 'Вечер в театре', date: today),
      );
    });
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
    expect(find.text('TEMPUS'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 850));
    await tester.pumpAndSettle();
    expect(find.byType(PalaceCard), findsOneWidget);
    expect(find.text('План на сегодня'), findsOneWidget);

    for (final (label, expected) in [
      ('План', 'Цели месяца'),
      ('Прогресс', 'План и факт'),
      ('Летопись', 'Поиск по летописи'),
      ('Профиль', 'Начало истории'),
    ]) {
      await tester.tap(find.widgetWithText(NavigationDestination, label));
      await tester.pumpAndSettle();
      expect(find.text(expected), findsOneWidget);
    }
    expect(find.text('Резервные копии'), findsNothing);
    await tester.tap(find.widgetWithText(NavigationDestination, 'Летопись'));
    await tester.pumpAndSettle();
    expect(find.text('Вечер в театре'), findsOneWidget);
    await tester.tap(find.widgetWithText(NavigationDestination, 'Прогресс'));
    await tester.pumpAndSettle();
    expect(find.text('0 / 12'), findsWidgets);
    await tester.tap(find.text('Зал'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 12'), findsWidgets);
    await tester.tap(find.byTooltip('Добавить отметку: Зал'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 12'), findsWidgets);
    await tester.tap(find.byTooltip('Подробнее: Зал'));
    await tester.pumpAndSettle();
    expect(find.text('Выполнено 2 из 12'), findsOneWidget);
    await tester.tap(
      find.byTooltip('Убрать одну отметку за ${shortDate(today)}'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Выполнено 1 из 12'), findsOneWidget);
    Navigator.of(tester.element(find.text('Выполнено 1 из 12'))).pop();
    await tester.pumpAndSettle();
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
      (await tester.runAsync(
        db.read,
      ))!.records.singleWhere((row) => row.kind == Kind.task).checked,
      isNotEmpty,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
