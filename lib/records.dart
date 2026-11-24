import 'dart:convert';

import 'package:intl/intl.dart';

enum Kind {
  task('Задача'),
  habit('Привычка'),
  goal('Месячная цель'),
  journal('Дневник'),
  event('Событие'),
  book('Книга'),
  theatre('Театр'),
  craft('Ремесло'),
  achievement('Достижение'),
  recovery('Восстановление'),
  income('Доход'),
  expense('Расход');

  const Kind(this.label);
  final String label;

  bool get isPlan => index <= goal.index;
  bool get isMoney => this == income || this == expense;
}

const areas = [
  'Личное',
  'Учёба',
  'Спорт',
  'Работа',
  'Финансы',
  'Творчество',
  'Здоровье',
];

DateTime dayOnly(DateTime date) => DateTime(date.year, date.month, date.day);
DateTime shiftDay(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);
String dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
String shortDate(DateTime date) => DateFormat('d MMMM', 'ru').format(date);
String monthTitle(DateTime date) => DateFormat('LLLL yyyy', 'ru').format(date);
String money(int minor) =>
    '${NumberFormat.decimalPatternDigits(locale: 'ru', decimalDigits: minor % 100 == 0 ? 0 : 2).format(minor / 100)} ₸';

class Record {
  const Record({
    required this.id,
    required this.kind,
    required this.title,
    required this.date,
    this.notes = '',
    this.area = 'Личное',
    this.checked = const {},
    this.weekdays = const {},
    this.amount = 0,
    this.reminder,
    this.photo,
    this.hasPhoto = false,
  });

  final int id;
  final Kind kind;
  final String title;
  final DateTime date;
  final String notes;
  final String area;
  final Set<String> checked;
  final Set<int> weekdays;
  final int amount;
  final int? reminder;
  final String? photo;
  final bool hasPhoto;

  bool occursOn(DateTime day) {
    if (kind == Kind.habit) {
      return !dayOnly(day).isBefore(dayOnly(date)) &&
          weekdays.contains(day.weekday);
    }
    if (kind == Kind.goal) {
      return date.year == day.year && date.month == day.month;
    }
    return date.year == day.year &&
        date.month == day.month &&
        date.day == day.day;
  }

  bool doneOn(DateTime day) =>
      kind == Kind.habit ? checked.contains(dayKey(day)) : checked.isNotEmpty;

  Record toggle(DateTime day) {
    final values = {...checked};
    if (doneOn(day)) {
      if (kind == Kind.habit) {
        values.remove(dayKey(day));
      } else {
        values.clear();
      }
    } else {
      values.add(dayKey(day));
    }
    return Record.fromJson({...toJson(), 'checked': values.toList()});
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    'date': dayKey(date),
    'notes': notes,
    'area': area,
    'checked': checked.toList(),
    'weekdays': weekdays.toList(),
    'amount': amount,
    'reminder': reminder,
    'photo': photo,
  };

  factory Record.fromJson(
    Map<String, dynamic> json, {
    bool validatePhoto = true,
    bool hasPhoto = false,
  }) {
    final id = json['id'] as int;
    final title = json['title'] as String;
    final kind = Kind.values.byName(json['kind'] as String);
    final dateText = json['date'] as String;
    final date = DateTime.parse(dateText);
    final weekdays = (json['weekdays'] as List).cast<int>().toSet();
    final checked = (json['checked'] as List).cast<String>().toSet();
    final reminder = json['reminder'] as int?;
    final amount = json['amount'] as int;
    final area = json['area'] as String;
    if (id < 1 ||
        id > 0x7fffffff ~/ 7 ||
        title.trim().isEmpty ||
        dateText != dayKey(date) ||
        date.year < 1900 ||
        date.year > 2100 ||
        !areas.contains(area) ||
        weekdays.any((value) => value < 1 || value > 7) ||
        (kind == Kind.habit && weekdays.isEmpty) ||
        (reminder != null &&
            (reminder < 0 || reminder >= 1440 || !kind.isPlan)) ||
        (kind.isMoney && (amount <= 0 || amount > 99999999999)) ||
        checked.any((value) {
          final parsed = DateTime.tryParse(value);
          return parsed == null || dayKey(parsed) != value;
        }) ||
        (kind != Kind.habit && checked.length > 1)) {
      throw const FormatException('Некорректная запись TEMPUS');
    }
    final photo = json['photo'] as String?;
    if (validatePhoto &&
        photo != null &&
        base64Decode(photo).length > photoLimit) {
      throw const FormatException('Фото превышает допустимый размер');
    }
    return Record(
      id: id,
      kind: kind,
      title: title,
      date: date,
      notes: json['notes'] as String,
      area: area,
      checked: checked,
      weekdays: weekdays,
      amount: amount,
      reminder: reminder,
      photo: photo,
      hasPhoto: hasPhoto || photo != null,
    );
  }
}

const photoLimit = 15 * 1024 * 1024;

class Snapshot {
  const Snapshot({
    this.records = const [],
    this.name = '',
    this.history = '2026-08-01',
  });

  final List<Record> records;
  final String name;
  final String history;

  Map<String, Object?> toJson() => {
    'schema': 1,
    'name': name,
    'history': history,
    'records': records.map((item) => item.toJson()).toList(),
  };

  factory Snapshot.fromJson(Map<String, dynamic> json) {
    if (json['schema'] != 1) {
      throw const FormatException('Версия резервной копии не поддерживается');
    }
    final rows = (json['records'] as List)
        .map((item) => Record.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final history = json['history'] as String;
    final start = DateTime.parse(history);
    if (rows.map((row) => row.id).toSet().length != rows.length ||
        history != dayKey(start) ||
        start.year < 1900 ||
        start.year > 2100) {
      throw const FormatException('Некорректная резервная копия');
    }
    return Snapshot(
      records: rows,
      name: json['name'] as String,
      history: history,
    );
  }
}

class ProgressSummary {
  const ProgressSummary(
    this.planned,
    this.completed,
    this.income,
    this.expense,
    this.archive,
  );
  final int planned;
  final int completed;
  final int income;
  final int expense;
  final int archive;

  double get ratio => planned == 0 ? 0 : completed / planned;

  factory ProgressSummary.between(
    List<Record> records,
    DateTime start,
    DateTime end,
  ) {
    var planned = 0;
    var completed = 0;
    var income = 0;
    var expense = 0;
    var archive = 0;
    bool inRange(DateTime day) => !day.isBefore(start) && day.isBefore(end);
    for (final row in records) {
      if (row.kind == Kind.habit) {
        final first = row.date.isAfter(start) ? row.date : start;
        for (var day = first; day.isBefore(end); day = shiftDay(day, 1)) {
          if (row.weekdays.contains(day.weekday)) {
            planned++;
            if (row.doneOn(day)) completed++;
          }
        }
      } else if (inRange(row.date)) {
        switch (row.kind) {
          case Kind.task:
          case Kind.goal:
            planned++;
            if (row.checked.isNotEmpty) completed++;
          case Kind.income:
            income += row.amount;
          case Kind.expense:
            expense += row.amount;
          default:
            archive++;
        }
      }
    }
    return ProgressSummary(planned, completed, income, expense, archive);
  }
}
