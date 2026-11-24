import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'design.dart';
import 'editor.dart';
import 'export.dart';
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
    super.key,
  });
  final Record row;
  final DateTime day;
  final bool showDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = row.doneOn(day);
    final detail = [
      if (showDate) shortDate(row.date),
      row.kind.label,
      if (row.area != 'Личное') row.area,
    ].join(' · ');
    return Surface(
      padding: EdgeInsets.zero,
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onTap: () =>
            editRecord(context, kinds: [row.kind], date: day, record: row),
        leading: row.kind.isPlan
            ? IconButton(
                tooltip: done ? 'Отменить выполнение' : 'Отметить выполненным',
                icon: Icon(
                  done
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked,
                  color: done ? sage : bronze,
                ),
                onPressed: () async {
                  try {
                    await ref
                        .read(recordsProvider.notifier)
                        .toggle(row.id, day);
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
            if (showDate && row.notes.isNotEmpty)
              Text(row.notes, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
        trailing: row.kind.isMoney
            ? Text(
                '${row.kind == Kind.expense ? '−' : '+'}${money(row.amount)}',
                style: TextStyle(
                  color: row.kind == Kind.expense ? bronze : sage,
                ),
              )
            : Icon(
                row.hasPhoto ? Icons.image_outlined : Icons.chevron_right,
                size: 19,
                color: muted,
              ),
      ),
    );
  }
}

const planKinds = [Kind.task, Kind.habit, Kind.goal];
final archiveKinds = Kind.values
    .where((kind) => !kind.isPlan && !kind.isMoney)
    .toList();
const moneyKinds = [Kind.income, Kind.expense];

List<Record> plansFor(List<Record> rows, DateTime date) =>
    rows
        .where(
          (row) =>
              row.kind.isPlan && row.kind != Kind.goal && row.occursOn(date),
        )
        .toList()
      ..sort((a, b) => (a.reminder ?? 1440).compareTo(b.reminder ?? 1440));

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
          const Chronograph(),
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionTitle(
                  'План на сегодня',
                  action: Text(
                    '$done из ${plans.length}',
                    style: const TextStyle(
                      color: bronze,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ProgressTrack(plans.isEmpty ? 0 : done / plans.length),
              ],
            ),
          ),
          SectionTitle(
            'Задачи и привычки',
            action: IconButton.filled(
              onPressed: () =>
                  editRecord(context, kinds: planKinds, date: today),
              icon: const Icon(Icons.add),
              tooltip: 'Добавить в план',
            ),
          ),
          if (plans.isEmpty)
            const EmptyCard(
              'Добавь задачу или привычку на сегодня.',
              icon: Icons.checklist_rounded,
            ),
          for (final row in plans) RecordTile(row: row, day: today),
          OutlinedButton.icon(
            onPressed: () =>
                editRecord(context, kinds: const [Kind.journal], date: today),
            icon: const Icon(Icons.edit_note_rounded),
            label: const Text('Запись в дневник'),
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
              onPressed: () =>
                  editRecord(context, kinds: const [Kind.goal], date: day),
            ),
          ),
          if (goals.isEmpty)
            const EmptyCard(
              'Месячные цели пока не добавлены.',
              icon: Icons.flag_outlined,
            ),
          for (final row in goals)
            RecordTile(row: row, day: day, showDate: true),
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
  Period period = Period.week;
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
    cursor = switch (period) {
      Period.week => shiftDay(cursor, direction * 7),
      Period.month => DateTime(cursor.year, cursor.month + direction),
      Period.year => DateTime(cursor.year + direction),
    };
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
          const PageHeading('Прогресс'),
          Center(
            child: SegmentedButton<Period>(
              segments: [
                for (final value in Period.values)
                  ButtonSegment(value: value, label: Text(value.label)),
              ],
              selected: {period},
              showSelectedIcon: false,
              onSelectionChanged: (change) =>
                  setState(() => period = change.single),
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
                child: Text(
                  title,
                  textAlign: TextAlign.center,
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
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionTitle(
                  'План и факт',
                  action: Text(
                    '${summary.completed} / ${summary.planned}',
                    style: const TextStyle(color: bronze),
                  ),
                ),
                const SizedBox(height: 12),
                ProgressTrack(summary.ratio),
                const SizedBox(height: 10),
                Text(
                  'Выполнено ${(summary.ratio * 100).round()}%',
                  style: const TextStyle(color: muted),
                ),
              ],
            ),
          ),
          if (summary.planned != 0)
            Surface(
              child: _PeriodChart(
                rows: snapshot.records,
                period: period,
                start: start,
                end: end,
                history: historyStart,
              ),
            ),
          const SectionTitle('Сферы'),
          if (!groups.values.any((item) => item.planned > 0))
            const EmptyCard('В этом периоде нет запланированных дел.'),
          for (final entry in groups.entries.where(
            (entry) => entry.value.planned > 0,
          ))
            Surface(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(entry.key)),
                      Text(
                        '${entry.value.completed} / ${entry.value.planned}',
                        style: const TextStyle(color: muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  ProgressTrack(entry.value.ratio),
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
          Period.year => '${day.month}',
        },
        ProgressSummary.between(
          rows,
          day.isBefore(history) ? history : day,
          boundary.isAfter(end) ? end : boundary,
        ),
      ));
    }
    final max = bars.fold<int>(
      1,
      (max, entry) => entry.$2.planned > max ? entry.$2.planned : max,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'План и выполнение по времени',
          style: TextStyle(color: muted),
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
                        bars[value.toInt()].$1,
                        style: const TextStyle(fontSize: 10, color: muted),
                      ),
                    ),
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, _, _, _) => BarTooltipItem(
                    '${bars[group.x].$2.completed} из ${bars[group.x].$2.planned}',
                    const TextStyle(color: paper),
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < bars.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: bars[i].$2.completed.toDouble(),
                        color: bronze,
                        width: period == Period.year ? 10 : 17,
                        borderRadius: BorderRadius.circular(4),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: bars[i].$2.planned.toDouble(),
                          color: border,
                        ),
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
            : !row.kind.isPlan && !row.kind.isMoney,
      );
      final items =
          all
              .where(
                (row) =>
                    finance ||
                    ((filter == null || row.kind == filter) &&
                        '${row.title} ${row.notes}'.toLowerCase().contains(
                          query,
                        )),
              )
              .toList()
            ..sort((a, b) {
              final date = b.date.compareTo(a.date);
              return date == 0 ? b.id.compareTo(a.id) : date;
            });
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
            Wrap(
              spacing: 7,
              runSpacing: 3,
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
          ],
          if (items.isEmpty)
            EmptyCard(
              finance
                  ? 'В этом месяце нет операций.'
                  : 'Записи пока не найдены.',
            ),
          for (final row in items)
            RecordTile(row: row, day: row.date, showDate: true),
        ],
      );
    },
  );
}
