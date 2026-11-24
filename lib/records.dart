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
  'Отношения',
  'Тренировки',
  'Развитие',
  'Культурное развитие',
  'Чтение',
  'Английский',
  'Работа',
];

String _recordArea(String old, String title, Kind kind) {
  if (areas.contains(old)) return old;
  final text = title.toLowerCase();
  if (text.contains('английск') || text.contains('english')) {
    return 'Английский';
  }
  if (kind == Kind.book ||
      text.contains('чтени') ||
      text.contains('прочитать')) {
    return 'Чтение';
  }
  if (kind == Kind.theatre ||
      text.contains('театр') ||
      text.contains('библиотек') ||
      text.contains('музей') ||
      text.contains('выставк')) {
    return 'Культурное развитие';
  }
  return switch (old) {
    'Спорт' => 'Тренировки',
    'Учёба' || 'Творчество' => 'Развитие',
    _ => 'Личное',
  };
}

const maxGoalTarget = 9999;

int _legacyGoalTarget(String title) {
  final counts = RegExp(
    r'(\d{1,4})(?:\s*[-–—]\s*\d{1,4})?\s*(?:раз|трениров|заняти|посещен|сесси|дне|дня)',
    caseSensitive: false,
  ).firstMatch(title);
  final afterUnit = RegExp(
    r'(?:раз|тренировок|занятий)\s+(\d{1,4})(?:\D|$)',
    caseSensitive: false,
  ).firstMatch(title);
  return (int.tryParse(counts?.group(1) ?? afterUnit?.group(1) ?? '') ?? 1)
      .clamp(1, maxGoalTarget);
}

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
    this.target = 1,
    this.sessions = const [],
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
  final int target;
  final List<String> sessions;

  int get goalCount => sessions.length;

  String get goalTitle {
    final trimmed = title
        .replaceFirst(
          RegExp(
            r'\s+\d{1,4}(?:\s*[-–—]\s*\d{1,4})?\s*раз(?:а)?(?:\s+в\s+месяц)?\s*$',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    return trimmed.isEmpty ? title : trimmed;
  }

  Record withSessions(List<String> value) =>
      Record.fromJson({...toJson(), 'sessions': value});

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

  bool doneOn(DateTime day) => switch (kind) {
    Kind.habit => checked.contains(dayKey(day)),
    Kind.goal => goalCount >= target,
    _ => checked.isNotEmpty,
  };

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
    if (kind == Kind.goal) 'target': target,
    if (kind == Kind.goal) 'sessions': sessions,
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
    final area = _recordArea(json['area'] as String, title, kind);
    final target = kind == Kind.goal
        ? (json['target'] as int? ?? _legacyGoalTarget(title))
        : 1;
    final rawSessions = json['sessions'] as List?;
    final sessions = kind != Kind.goal
        ? const <String>[]
        : rawSessions != null
        ? rawSessions.cast<String>().toList()
        : checked.isEmpty
        ? const <String>[]
        : List.filled(
            target.clamp(1, maxGoalTarget),
            checked.first.startsWith(dayKey(date).substring(0, 7))
                ? checked.first
                : dayKey(date),
          );
    bool validDate(String value) {
      final parsed = DateTime.tryParse(value);
      return parsed != null && dayKey(parsed) == value;
    }

    if (id < 1 ||
        id > 0x7fffffff ~/ 7 ||
        title.trim().isEmpty ||
        dateText != dayKey(date) ||
        date.year < 1900 ||
        date.year > 2100 ||
        target < 1 ||
        target > maxGoalTarget ||
        sessions.length > maxGoalTarget ||
        sessions.any(
          (value) =>
              !validDate(value) || !value.startsWith(dateText.substring(0, 7)),
        ) ||
        weekdays.any((value) => value < 1 || value > 7) ||
        (kind == Kind.habit && weekdays.isEmpty) ||
        (reminder != null &&
            (reminder < 0 || reminder >= 1440 || !kind.isPlan)) ||
        (kind.isMoney && (amount <= 0 || amount > 99999999999)) ||
        checked.any((value) => !validDate(value)) ||
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
      target: target,
      sessions: List.unmodifiable(sessions),
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
      } else if (row.kind == Kind.goal) {
        if (inRange(row.date)) planned += row.target;
        completed += row.sessions
            .where((value) => inRange(DateTime.parse(value)))
            .length;
      } else if (inRange(row.date)) {
        switch (row.kind) {
          case Kind.task:
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
