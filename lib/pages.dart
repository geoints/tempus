import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'archive_covers.dart';
import 'design.dart';
import 'editor.dart';
import 'export.dart';
import 'goals.dart';
import 'records.dart';
import 'store.dart';

class WithRecords extends ConsumerWidget {
  const WithRecords({required this.builder, super.key});
  final Widget Function(Snapshot data) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(recordsProvider)
      .when(
        data: builder,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Не удалось открыть данные TEMPUS'),
                TextButton(
                  onPressed: () => ref.invalidate(recordsProvider),
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
      );
}

class RecordTile extends ConsumerWidget {
  const RecordTile({
    required this.row,
    required this.day,
    this.showDate = false,
    this.grouped = false,
    super.key,
  });
  final Record row;
  final DateTime day;
  final bool showDate;
  final bool grouped;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = row.doneOn(day);
    final detail = [
      if (showDate) shortDate(row.date),
      row.kind.label,
      if (row.area != 'Личное') row.area,
      if (row.timeRange case final TimeRange range)
        '${minuteLabel(range.start)}–${minuteLabel(range.end)}',
      if (row.reminder case final int time)
        if (row.kind.isPlan)
          TimeOfDay(hour: time ~/ 60, minute: time % 60).format(context),
    ].join(' · ');
    final tile = ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onTap: () =>
          editRecord(context, kinds: [row.kind], date: day, record: row),
      leading: row.kind.isPlan
          ? IconButton(
              tooltip: done ? 'Отменить выполнение' : 'Отметить выполненным',
              icon: AnimatedSwitcher(
                duration: motion(context, 190),
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: Icon(
                  key: ValueKey(done),
                  done
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked,
                  color: done ? sage : bronze,
                ),
              ),
              onPressed: () async {
                try {
                  await ref.read(recordsProvider.notifier).toggle(row.id, day);
                  HapticFeedback.selectionClick();
                } catch (_) {
                  if (context.mounted) {
                    notify(context, 'Не удалось обновить запись');
                  }
                }
              },
            )
          : Icon(kindIcon(row.kind), color: bronze),
      title: Text(
        row.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: done ? muted : paper,
          decoration: done ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(detail, style: const TextStyle(color: muted, fontSize: 12)),
        ],
      ),
      trailing: row.kind.isMoney
          ? Text(
              '${row.kind == Kind.expense ? '−' : '+'}${money(row.amount)}',
              style: TextStyle(color: row.kind == Kind.expense ? bronze : sage),
            )
          : Icon(
              row.hasPhoto ? Icons.image_outlined : Icons.chevron_right,
              size: 19,
              color: muted,
            ),
    );
    return grouped ? tile : Surface(padding: EdgeInsets.zero, child: tile);
  }
}

const planKinds = [Kind.task, Kind.habit, Kind.goal];
final archiveKinds = Kind.values.where((kind) => kind.isArchive).toList();
const moneyKinds = [Kind.income, Kind.expense];

List<Record> plansFor(List<Record> rows, DateTime date) =>
    rows
        .where(
          (row) =>
              row.kind.isPlan && row.kind != Kind.goal && row.occursOn(date),
        )
        .toList()
      ..sort(
        (a, b) => (a.timeRange?.start ?? a.reminder ?? minutesPerDay).compareTo(
          b.timeRange?.start ?? b.reminder ?? minutesPerDay,
        ),
      );

class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WithRecords(
    builder: (data) {
      final now = DateTime.now();
      final today = dayOnly(now);
      final plans = plansFor(data.records, today);
      final done = plans.where((row) => row.doneOn(today)).length;
      final greeting = switch (now.hour) {
        < 5 => 'Доброй ночи',
        < 12 => 'Доброе утро',
        < 18 => 'Добрый день',
        _ => 'Добрый вечер',
      };
      return PageList(
        children: [
          PageHeading(
            data.name.isEmpty ? 'Сегодня' : '$greeting, ${data.name}',
            subtitle: DateFormat(
              'EEEE, d MMMM',
              'ru',
            ).format(today).toUpperCase(),
            action: IconButton.filledTonal(
              onPressed: () => context.go('/plan'),
              tooltip: 'Открыть календарь',
              icon: const Icon(Icons.calendar_month_outlined),
            ),
          ),
          const PalaceCard(),
          Surface(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(15, 8, 9, 10),
                  child: Column(
                    children: [
                      SectionTitle(
                        'План на сегодня',
                        action: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedValue(
                              '$done из ${plans.length}',
                              style: const TextStyle(
                                color: bronze,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              onPressed: () => editRecord(
                                context,
                                kinds: planKinds,
                                date: today,
                              ),
                              icon: const Icon(Icons.add),
                              tooltip: 'Добавить в план',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      ProgressTrack(plans.isEmpty ? 0 : done / plans.length),
                    ],
                  ),
                ),
                if (plans.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(15, 3, 15, 15),
                    child: Text(
                      'Добавь задачу или привычку на сегодня.',
                      style: TextStyle(color: muted),
                    ),
                  ),
                for (final row in plans) ...[
                  const Divider(),
                  RecordTile(row: row, day: today, grouped: true),
                ],
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => context.go('/plan/schedule'),
            icon: const Icon(Icons.view_timeline_outlined),
            label: const Text('Расписание по времени'),
          ),
        ],
      );
    },
  );
}

class PlanPage extends StatefulWidget {
  const PlanPage({super.key});

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  DateTime day = dayOnly(DateTime.now());
  static const week = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  void _navigate(int months) {
    final month = DateTime(day.year, day.month + months);
    if (month.year >= 1900 && month.year <= 2100) setState(() => day = month);
  }

  @override
  Widget build(BuildContext context) => WithRecords(
    builder: (data) {
      final month = DateTime(day.year, day.month);
      final leading = month.weekday - 1;
      final monthDays = DateTime(day.year, day.month + 1, 0).day;
      final plans = plansFor(data.records, day);
      final goals = data.records.where(
        (row) => row.kind == Kind.goal && row.occursOn(day),
      );
      final today = dayOnly(DateTime.now());
      return PageList(
        children: [
          PageHeading(
            'План',
            action: IconButton.filled(
              onPressed: () => editRecord(context, kinds: planKinds, date: day),
              tooltip: 'Добавить в план',
              icon: const Icon(Icons.add),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => context.go('/plan/schedule?date=${dayKey(day)}'),
            icon: const Icon(Icons.view_timeline_outlined),
            label: Text('Расписание на ${shortDate(day)}'),
          ),
          Surface(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => _navigate(-1),
                      icon: const Icon(Icons.chevron_left),
                      tooltip: 'Предыдущий месяц',
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () async {
                          final picked = await pickDay(context, day);
                          if (picked != null && mounted) {
                            setState(() => day = picked);
                          }
                        },
                        child: Text(
                          monthTitle(day),
                          style: const TextStyle(
                            fontFamily: 'TempusSerif',
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _navigate(1),
                      icon: const Icon(Icons.chevron_right),
                      tooltip: 'Следующий месяц',
                    ),
                  ],
                ),
                Row(
                  children: [
                    for (final label in week)
                      Expanded(
                        child: Center(
                          child: Text(
                            label,
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                for (var row = 0; row < (leading + monthDays + 6) ~/ 7; row++)
                  Row(
                    children: List.generate(7, (column) {
                      final value = row * 7 + column - leading + 1;
                      if (value < 1 || value > monthDays) {
                        return const Expanded(child: SizedBox());
                      }
                      final date = DateTime(day.year, day.month, value);
                      final hasPlan = data.records.any(
                        (item) =>
                            item.kind.isPlan &&
                            item.kind != Kind.goal &&
                            item.occursOn(date),
                      );
                      final isPicked = date == day;
                      return Expanded(
                        child: Semantics(
                          label: shortDate(date),
                          button: true,
                          onTap: () => setState(() => day = date),
                          selected: isPicked,
                          child: ExcludeSemantics(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => setState(() => day = date),
                              child: AnimatedContainer(
                                duration:
                                    MediaQuery.disableAnimationsOf(context)
                                    ? Duration.zero
                                    : const Duration(milliseconds: 150),
                                height: 42,
                                decoration: BoxDecoration(
                                  color: isPicked ? bronze : null,
                                  borderRadius: BorderRadius.circular(10),
                                  border: date == today
                                      ? Border.all(color: bronze)
                                      : null,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '$value',
                                      style: TextStyle(
                                        color: isPicked ? ink : paper,
                                      ),
                                    ),
                                    Container(
                                      width: 4,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: hasPlan
                                            ? (isPicked ? ink : bronze)
                                            : Colors.transparent,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                if (day != today)
                  TextButton(
                    onPressed: () => setState(() => day = today),
                    child: const Text('К сегодняшнему дню'),
                  ),
              ],
            ),
          ),
          SectionTitle(shortDate(day)),
          if (plans.isEmpty)
            const EmptyCard('На этот день пока нет задач и привычек.'),
          for (final row in plans) RecordTile(row: row, day: day),
          SectionTitle(
            'Цели месяца',
            action: IconButton(
              tooltip: 'Добавить цель',
              icon: const Icon(Icons.add),
              onPressed: () => editRecord(
                context,
                kinds: const [Kind.goal],
                date: DateTime(day.year, day.month + 1, 0),
              ),
            ),
          ),
          if (goals.isEmpty)
            const EmptyCard(
              'Месячные цели пока не добавлены.',
              icon: Icons.flag_outlined,
            ),
          if (goals.isNotEmpty) GoalGrid(goals.toList()),
        ],
      );
    },
  );
}

enum Period {
  week('Неделя'),
  month('Месяц'),
  year('Год');

  const Period(this.label);
  final String label;
}

class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key});
  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  Period period = Period.month;
  String? selectedArea;
  DateTime cursor = dayOnly(DateTime.now());
  bool exporting = false;

  (DateTime, DateTime) get range => switch (period) {
    Period.week => (
      shiftDay(cursor, 1 - cursor.weekday),
      shiftDay(cursor, 8 - cursor.weekday),
    ),
    Period.month => (
      DateTime(cursor.year, cursor.month),
      DateTime(cursor.year, cursor.month + 1),
    ),
    Period.year => (DateTime(cursor.year), DateTime(cursor.year + 1)),
  };

  void step(int direction) => setState(() {
    final next = switch (period) {
      Period.week => shiftDay(cursor, direction * 7),
      Period.month => DateTime(cursor.year, cursor.month + direction),
      Period.year => DateTime(cursor.year + direction),
    };
    if (next.year >= 1900 && next.year <= 2100) cursor = next;
  });

  @override
  Widget build(BuildContext context) => WithRecords(
    builder: (snapshot) {
      final (start, end) = range;
      final title = switch (period) {
        Period.week =>
          '${shortDate(start)} – ${shortDate(shiftDay(end, -1))}, ${start.year}',
        Period.month => monthTitle(start),
        Period.year => '${start.year}',
      };
      final history = DateTime.parse(snapshot.history);
      final historyStart = period == Period.year && history.isAfter(start)
          ? history
          : start;
      final summary = ProgressSummary.between(
        snapshot.records,
        historyStart,
        end,
      );
      final goals = snapshot.records
          .where((row) => row.kind == Kind.goal && row.occursOn(start))
          .toList();
      final chartRows = selectedArea == null
          ? snapshot.records
          : snapshot.records.where((row) => row.area == selectedArea).toList();
      final graphSummary = ProgressSummary.between(
        chartRows,
        historyStart,
        end,
      );
      final groups = {
        for (final area in areas)
          area: ProgressSummary.between(
            snapshot.records.where((r) => r.area == area).toList(),
            historyStart,
            end,
          ),
      };
      return PageList(
        children: [
          PageHeading(period == Period.year ? 'Годовой обзор' : 'Прогресс'),
          Center(
            child: SegmentedButton<Period>(
              segments: [
                for (final value in Period.values)
                  ButtonSegment(value: value, label: Text(value.label)),
              ],
              selected: {period},
              showSelectedIcon: false,
              onSelectionChanged: (change) => setState(() {
                period = change.single;
                selectedArea = null;
              }),
            ),
          ),
          Row(
            children: [
              IconButton(
                onPressed: cursor.year <= 1900 ? null : () => step(-1),
                tooltip: 'Предыдущий период',
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: AnimatedValue(
                  title,
                  style: const TextStyle(
                    fontFamily: 'TempusSerif',
                    fontSize: 17,
                  ),
                ),
              ),
              IconButton(
                onPressed: cursor.year >= 2100 ? null : () => step(1),
                tooltip: 'Следующий период',
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          _PlanFact(summary),
          if (period == Period.month) ...[
            SectionTitle(
              'Цели месяца',
              action: IconButton.filledTonal(
                tooltip: 'Добавить цель',
                icon: const Icon(Icons.add),
                onPressed: () => editRecord(
                  context,
                  kinds: const [Kind.goal],
                  date: DateTime(start.year, start.month + 1, 0),
                ),
              ),
            ),
            if (goals.isEmpty)
              const EmptyCard(
                'Добавь цель и укажи, сколько раз хочешь её выполнить.',
                icon: Icons.flag_outlined,
              )
            else ...[
              if (start.year == DateTime.now().year &&
                  start.month == DateTime.now().month)
                const Text(
                  'Коснись карточки, чтобы добавить одну отметку.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              GoalGrid(goals),
            ],
          ],
          if (summary.planned > 0 || summary.completed > 0)
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionTitle(
                    'Динамика',
                    action: PopupMenuButton<String>(
                      tooltip: 'Фильтр по сфере',
                      icon: Icon(
                        Icons.tune_rounded,
                        color: selectedArea == null ? muted : bronze,
                      ),
                      initialValue: selectedArea ?? '',
                      onSelected: (value) => setState(
                        () => selectedArea = value.isEmpty ? null : value,
                      ),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: '',
                          child: Text('Все сферы'),
                        ),
                        for (final area in areas)
                          PopupMenuItem(value: area, child: Text(area)),
                      ],
                    ),
                  ),
                  if (selectedArea != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Text(
                        selectedArea!,
                        style: const TextStyle(color: bronze),
                      ),
                    ),
                  _PeriodChart(
                    rows: chartRows,
                    period: period,
                    start: start,
                    end: end,
                    history: historyStart,
                  ),
                  if (selectedArea != null &&
                      graphSummary.planned == 0 &&
                      graphSummary.completed == 0)
                    const Text(
                      'В этой сфере пока нет записей за период.',
                      style: TextStyle(color: muted),
                    ),
                ],
              ),
            ),
          const SectionTitle('Сферы'),
          if (!groups.values.any(
            (item) => item.planned > 0 || item.completed > 0,
          ))
            const EmptyCard(
              'Здесь появятся данные по твоим сферам.',
              icon: Icons.insights_outlined,
            ),
          for (final entry in groups.entries.where(
            (entry) => entry.value.planned > 0 || entry.value.completed > 0,
          ))
            Surface(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
              child: Row(
                children: [
                  Icon(areaIcon(entry.key), color: bronze, size: 19),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.key),
                        const SizedBox(height: 6),
                        ProgressTrack(entry.value.ratio),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  AnimatedValue(
                    '${entry.value.completed} / ${entry.value.planned}',
                    style: const TextStyle(color: muted),
                  ),
                ],
              ),
            ),
          if (period == Period.year) ...[
            const SectionTitle('Ежегодная сводка'),
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Записей в летописи · ${summary.archive}'),
                  for (final kind in archiveKinds)
                    if (snapshot.records.any(
                      (row) =>
                          row.kind == kind &&
                          !row.date.isBefore(historyStart) &&
                          row.date.isBefore(end),
                    ))
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '${kind.label} · ${snapshot.records.where((row) => row.kind == kind && !row.date.isBefore(historyStart) && row.date.isBefore(end)).length}',
                          style: const TextStyle(color: muted),
                        ),
                      ),
                  const SizedBox(height: 10),
                  Text('Доход · ${money(summary.income)}'),
                  Text('Расход · ${money(summary.expense)}'),
                  Text('Баланс · ${money(summary.income - summary.expense)}'),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: exporting
                  ? null
                  : () async {
                      setState(() => exporting = true);
                      try {
                        final bytes = await yearPdf(snapshot, start.year);
                        final saved = await saveFile(
                          'TEMPUS-${start.year}.pdf',
                          bytes,
                        );
                        if (context.mounted && saved != null) {
                          notify(context, 'PDF сохранён');
                        }
                      } catch (_) {
                        if (context.mounted) {
                          notify(context, 'Не удалось подготовить PDF');
                        }
                      } finally {
                        if (mounted) setState(() => exporting = false);
                      }
                    },
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Сводка в PDF'),
            ),
          ],
        ],
      );
    },
  );
}

class _PlanFact extends StatelessWidget {
  const _PlanFact(this.summary);
  final ProgressSummary summary;

  @override
  Widget build(BuildContext context) {
    final remaining = (summary.planned - summary.completed).clamp(
      0,
      summary.planned,
    );
    final percent = summary.planned == 0
        ? '—'
        : '${(summary.ratio * 100).round()}%';
    const number = TextStyle(
      fontFamily: 'TempusSerif',
      color: paper,
      fontSize: 23,
    );
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            'План и факт',
            action: IconButton(
              tooltip: 'Как считается прогресс',
              icon: const Icon(Icons.info_outline, color: muted, size: 19),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('План и факт'),
                  content: const Text(
                    'План включает задачи, повторы привычек и количество повторов по целям на дату срока. '
                    'Выполненные задачи и привычки учитываются на запланированную дату, а отметки по целям — на дату выполнения.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Понятно'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox.square(
                dimension: 111,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: TweenAnimationBuilder<double>(
                        duration: motion(context, 470),
                        tween: Tween(end: summary.ratio.clamp(0, 1).toDouble()),
                        curve: Curves.easeOutCubic,
                        builder: (_, value, _) => CircularProgressIndicator(
                          value: value,
                          strokeWidth: 8,
                          strokeCap: StrokeCap.round,
                          backgroundColor: border,
                          color: bronze,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(11),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: AnimatedValue(
                          percent,
                          style: const TextStyle(
                            color: paper,
                            fontSize: 27,
                            fontFamily: 'TempusSerif',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 19),
              Expanded(
                child: Column(
                  children: [
                    for (final (label, value, color) in [
                      ('План', summary.planned, muted),
                      ('Факт', summary.completed, bronze),
                      ('До плана', remaining, sage),
                    ])
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                label,
                                style: const TextStyle(color: muted),
                              ),
                            ),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: AnimatedValue('$value', style: number),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (summary.planned == 0 && summary.completed == 0) ...[
            const SizedBox(height: 14),
            const Text(
              'За этот период ещё нет плана и отметок.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _PeriodChart extends StatelessWidget {
  const _PeriodChart({
    required this.rows,
    required this.period,
    required this.start,
    required this.end,
    required this.history,
  });
  final List<Record> rows;
  final Period period;
  final DateTime start;
  final DateTime end;
  final DateTime history;

  @override
  Widget build(BuildContext context) {
    final step = switch (period) {
      Period.week => (DateTime day) => shiftDay(day, 1),
      Period.month => (DateTime day) => shiftDay(day, 7),
      Period.year => (DateTime day) => DateTime(day.year, day.month + 1),
    };
    final bars = <(String, ProgressSummary)>[];
    for (var day = start; day.isBefore(end); day = step(day)) {
      final boundary = step(day);
      bars.add((
        switch (period) {
          Period.week => DateFormat('EE', 'ru').format(day),
          Period.month => '${day.day}',
          Period.year => DateFormat(
            'MMM',
            'ru',
          ).format(day).replaceAll('.', ''),
        },
        ProgressSummary.between(
          rows,
          day.isBefore(history) ? history : day,
          boundary.isAfter(end) ? end : boundary,
        ),
      ));
    }
    var max = 1;
    for (final (_, stats) in bars) {
      if (stats.planned > max) max = stats.planned;
      if (stats.completed > max) max = stats.completed;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 15,
          children: [
            for (final (label, color) in [
              ('План', const Color(0xff705039)),
              ('Факт', bronze),
            ])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 8, color: color),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 144,
          child: BarChart(
            BarChartData(
              maxY: max.toDouble() * 1.15,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                topTitles: const AxisTitles(),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (value, _) => Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        value.toInt() >= 0 && value.toInt() < bars.length
                            ? bars[value.toInt()].$1
                            : '',
                        style: const TextStyle(fontSize: 10, color: muted),
                        textScaler: TextScaler.noScaling,
                      ),
                    ),
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItem: (group, _, _, _) => BarTooltipItem(
                    '${bars[group.x].$1} · План ${bars[group.x].$2.planned} · Факт ${bars[group.x].$2.completed}',
                    const TextStyle(color: paper),
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < bars.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: 3,
                    barRods: [
                      for (final (height, color) in [
                        (bars[i].$2.planned, const Color(0xff705039)),
                        (bars[i].$2.completed, bronze),
                      ])
                        BarChartRodData(
                          toY: height.toDouble(),
                          color: color,
                          width: period == Period.year ? 6 : 10,
                          borderRadius: BorderRadius.circular(3),
                        ),
                    ],
                  ),
              ],
            ),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 260),
          ),
        ),
      ],
    );
  }
}

class ArchivePage extends StatefulWidget {
  const ArchivePage({super.key});
  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  Kind? filter;
  bool finance = false;
  String query = '';
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) => WithRecords(
    builder: (snapshot) {
      final all = snapshot.records.where(
        (row) => finance
            ? row.kind.isMoney &&
                  row.date.year == month.year &&
                  row.date.month == month.month
            : row.kind.isArchive,
      );
      final items =
          all
              .where(
                (row) =>
                    finance ||
                    ((filter == null || row.kind == filter) &&
                        row.title.toLowerCase().contains(query)),
              )
              .toList()
            ..sort((a, b) {
              final date = b.date.compareTo(a.date);
              return date == 0 ? b.id.compareTo(a.id) : date;
            });
      final byMonth = <DateTime, List<Record>>{};
      if (!finance) {
        for (final row in items) {
          final collection = DateTime(row.date.year, row.date.month);
          byMonth.putIfAbsent(collection, () => []).add(row);
        }
      }
      final totals = ProgressSummary.between(
        all.toList(),
        month,
        DateTime(month.year, month.month + 1),
      );
      return PageList(
        children: [
          PageHeading(
            finance ? 'Финансы' : 'Летопись',
            action: IconButton.filled(
              onPressed: () => editRecord(
                context,
                kinds: finance
                    ? moneyKinds
                    : filter == null
                    ? archiveKinds
                    : [filter!],
                date: finance
                    ? (DateTime.now().year == month.year &&
                              DateTime.now().month == month.month
                          ? dayOnly(DateTime.now())
                          : month)
                    : dayOnly(DateTime.now()),
              ),
              tooltip: 'Добавить запись',
              icon: const Icon(Icons.add),
            ),
          ),
          Center(
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('Летопись'),
                  icon: Icon(Icons.auto_stories_outlined),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('Финансы'),
                  icon: Icon(Icons.account_balance_wallet_outlined),
                ),
              ],
              selected: {finance},
              showSelectedIcon: false,
              onSelectionChanged: (values) =>
                  setState(() => finance = values.single),
            ),
          ),
          if (finance) ...[
            Row(
              children: [
                IconButton(
                  onPressed: month.year == 1900 && month.month == 1
                      ? null
                      : () => setState(
                          () => month = DateTime(month.year, month.month - 1),
                        ),
                  tooltip: 'Предыдущий месяц',
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(monthTitle(month), textAlign: TextAlign.center),
                ),
                IconButton(
                  onPressed: month.year == 2100 && month.month == 12
                      ? null
                      : () => setState(
                          () => month = DateTime(month.year, month.month + 1),
                        ),
                  tooltip: 'Следующий месяц',
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Баланс', style: TextStyle(color: muted)),
                  Text(
                    money(totals.income - totals.expense),
                    style: const TextStyle(
                      fontFamily: 'TempusSerif',
                      fontSize: 29,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    'Доходы  ${money(totals.income)}',
                    style: const TextStyle(color: sage),
                  ),
                  Text(
                    'Расходы  ${money(totals.expense)}',
                    style: const TextStyle(color: bronze),
                  ),
                ],
              ),
            ),
          ] else ...[
            TextFormField(
              initialValue: query,
              decoration: const InputDecoration(
                labelText: 'Поиск по летописи',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) =>
                  setState(() => query = value.trim().toLowerCase()),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                spacing: 7,
                children: [
                  ChoiceChip(
                    label: const Text('Все'),
                    selected: filter == null,
                    onSelected: (_) => setState(() => filter = null),
                  ),
                  for (final kind in archiveKinds)
                    ChoiceChip(
                      label: Text(kind.label),
                      selected: filter == kind,
                      onSelected: (_) => setState(() => filter = kind),
                    ),
                ],
              ),
            ),
          ],
          if (items.isEmpty)
            EmptyCard(
              finance
                  ? 'В этом месяце нет операций.'
                  : query.isNotEmpty || filter != null
                  ? 'Записи пока не найдены.'
                  : 'Добавь первую запись и выбери фотообложку.',
            ),
          if (finance)
            for (final row in items)
              RecordTile(row: row, day: row.date, showDate: true)
          else
            for (final entry in byMonth.entries)
              ArchiveMonth(entry.key, entry.value, key: ValueKey(entry.key)),
        ],
      );
    },
  );
}
