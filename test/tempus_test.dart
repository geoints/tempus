import 'dart:convert';

import 'package:drift/native.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tempus/design.dart';
import 'package:tempus/export.dart';
import 'package:tempus/main.dart';
import 'package:tempus/photography.dart';
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

  test(
    'Обложка из базы v1 переносится в альбом и остаётся редактируемой',
    () async {
      final original = Uint8List.fromList([10, 20, 30]);
      final row = Record(
        id: 7,
        kind: Kind.theatre,
        title: 'Походы',
        date: DateTime(2026, 9, 4),
      );
      final db = TempusDatabase(
        NativeDatabase.memory(
          setup: (db) {
            db.execute(
              'CREATE TABLE records (id INTEGER PRIMARY KEY, payload TEXT NOT NULL, photo TEXT)',
            );
            db.execute(
              'CREATE TABLE settings (id INTEGER PRIMARY KEY, name TEXT NOT NULL, history TEXT NOT NULL)',
            );
            db.execute(
              'INSERT INTO records (id, payload, photo) VALUES (?, ?, ?)',
              [row.id, jsonEncode(row.toJson()), base64Encode(original)],
            );
            db.execute('PRAGMA user_version = 1');
          },
        ),
      );
      addTearDown(db.close);
      expect((await db.read()).records.single.hasPhoto, isTrue);
      final first = (await db.album(7)).single;
      expect(first.isCover, isTrue);
      expect(await db.albumImage(first.id), original);
      expect(await db.photo(7), isNull);
      final secondBytes = Uint8List.fromList([70, 71, 72]);
      final thumb = Uint8List.fromList([77]);
      await db.addPhoto(7, AlbumPhotoData(secondBytes, thumb));
      final second = (await db.album(7)).last;
      expect(second.isCover, isFalse);
      await db.setCover(7, second.id);
      expect(await db.cover(7), thumb);
      expect(await db.albumImage(second.id), secondBytes);
      await db.put(row);
      expect((await db.album(7)).length, 2);
      await db.removePhoto(7, second.id);
      expect((await db.album(7)).single.isCover, isTrue);
      await db.remove(7);
      expect(await db.album(7), isEmpty);
      expect(await db.albumImage(first.id), isNull);
    },
  );

  test('Пресет оригинала нейтрален, у JPEG определяется размер', () async {
    expect(FilmLook.original.preview(.8), FilmLook.chestnut.preview(0));
    expect(FilmLook.bronze.preview(.8), isNot(FilmLook.chestnut.preview(.8)));
    final asset = await rootBundle.load('assets/tempus-palace.jpg');
    final dimensions = jpegDimensions(
      asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
    );
    expect(dimensions, (1440, 960));
    expect(jpegDimensions(Uint8List.fromList([255, 216, 255, 192, 0])), isNull);
  });

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

  test(
    'Время задачи сохраняется и проверяется с точностью до минуты',
    () async {
      final db = TempusDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      expect(parseMinute('08:07'), 487);
      expect(parseMinute('0808'), 488);
      expect(parseMinute('24:00'), 1440);
      expect(parseMinute('24:01'), isNull);
      expect(parseMinute('08:60'), isNull);
      final row = Record(
        id: 1,
        kind: Kind.task,
        title: 'Короткое дело',
        date: DateTime(2026, 11, 24),
        timeRange: (start: 487, end: 488),
      );
      expect(
        () => Record.fromJson({...row.toJson(), 'endMinute': 487}),
        throwsFormatException,
      );
      expect(
        () => Record.fromJson({...row.toJson(), 'endMinute': 1441}),
        throwsFormatException,
      );
      await db.put(row);
      final stored = (await db.read()).records.single;
      expect(stored.timeRange, (start: 487, end: 488));
      expect(stored.toggle(stored.date).timeRange, stored.timeRange);
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
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.text('TEMPUS'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.byType(PalaceCard), findsOneWidget);
    expect(find.text('План на сегодня'), findsOneWidget);
    expect(find.text('Запись в дневник'), findsNothing);
    expect(find.text('Расписание по времени'), findsOneWidget);

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
    expect(find.byTooltip('Камера TEMPUS'), findsOneWidget);
    await tester.tap(find.text('Вечер в театре'));
    await tester.pumpAndSettle();
    expect(find.text('Фотоальбом'), findsOneWidget);
    expect(find.text('Добавить фото'), findsOneWidget);
    expect(find.text('Снять'), findsOneWidget);
    Navigator.of(tester.element(find.text('Фотоальбом'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Дневник'), findsNothing);
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
    expect(find.text('Заметки'), findsNothing);
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
    await tester.tap(find.text('Расписание по времени'));
    await tester.pumpAndSettle();
    expect(find.text('Расписание'), findsOneWidget);
    await tester.tap(find.byTooltip('Показать три дня'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Показать один день'), findsOneWidget);
    await tester.tap(find.byTooltip('Добавить дело по времени'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Минутное дело');
    await tester.enterText(find.byType(TextFormField).at(1), '08:07');
    await tester.enterText(find.byType(TextFormField).at(2), '08:08');
    await tester.ensureVisible(find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(
      (await tester.runAsync(
        db.read,
      ))!.records.singleWhere((row) => row.title == 'Минутное дело').timeRange,
      (start: 487, end: 488),
    );
    await tester.tap(find.text('Дела дня · 1 без времени'));
    await tester.pumpAndSettle();
    expect(find.text('Минутное дело'), findsOneWidget);
    expect(find.textContaining('08:07–08:08'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
