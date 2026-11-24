import 'dart:async';
import 'dart:math' as math;

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'design.dart';
import 'editor.dart';
import 'pages.dart' show RecordTile, WithRecords, plansFor;
import 'records.dart';
import 'store.dart';

const _minuteHeight = 1.65;
const _hourMargin = 48.0;
const _topPadding = 12.0;

class SchedulePage extends StatefulWidget {
  const SchedulePage({this.initialDate, super.key});

  final DateTime? initialDate;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  late DateTime _day = dayOnly(widget.initialDate ?? DateTime.now());
  var _now = DateTime.now();
  bool _threeDays = false;
  ScrollController? _scroll;
  Timer? _clock;

  int get _minuteNow => _now.hour * 60 + _now.minute;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 15), (_) {
      final now = DateTime.now();
      if (now.minute != _now.minute ||
          now.hour != _now.hour ||
          now.day != _now.day) {
        setState(() => _now = now);
      }
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _scroll?.dispose();
    super.dispose();
  }

  void _select(DateTime date) {
    if (date.year < 1900 || date.year > 2100 || date == _day) return;
    HapticFeedback.selectionClick();
    setState(() => _day = date);
  }

  Future<void> _newTask(BuildContext context, DateTime date, int minute) =>
      editRecord(
        context,
        date: date,
        kinds: const [Kind.task, Kind.habit],
        initialTime: (start: minute, end: math.min(minute + 30, minutesPerDay)),
      );

  void _agenda(BuildContext context) {
    final day = _day;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => WithRecords(
        builder: (snapshot) {
          final rows = plansFor(snapshot.records, day);
          return SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .75,
              ),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(17, 0, 17, 20),
                children: [
                  PageHeading('Дела на день', subtitle: shortDate(day)),
                  const SizedBox(height: 13),
                  if (rows.isEmpty)
                    const EmptyCard('На эту дату пока нет дел.'),
                  for (final row in rows) ...[
                    RecordTile(row: row, day: day),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => WithRecords(
    builder: (snapshot) {
      final today = dayOnly(_now);
      final rows = plansFor(snapshot.records, _day);
      final timed = rows.where((row) => row.timeRange != null).toList();
      _scroll ??= ScrollController(
        initialScrollOffset:
            math.max(
              0,
              (_day == today
                  ? _minuteNow - 54
                  : (timed.firstOrNull?.timeRange?.start ?? 8 * 60) - 35),
            ) *
            _minuteHeight,
      );
      final positions = [shiftDay(_day, -1), _day, shiftDay(_day, 1)];
      final visible = _threeDays ? positions : [_day];
      final noTime = rows.length - timed.length;
      return Scaffold(
        floatingActionButton: FloatingActionButton.small(
          heroTag: 'schedule-create',
          onPressed: () =>
              _newTask(context, _day, _day == today ? _minuteNow : 9 * 60),
          tooltip: 'Добавить дело по времени',
          child: const Icon(Icons.add_rounded),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(17, 14, 12, 0),
              child: PageHeading(
                'Расписание',
                action: IconButton(
                  icon: Icon(
                    _threeDays
                        ? Icons.view_day_outlined
                        : Icons.view_column_outlined,
                  ),
                  tooltip: _threeDays
                      ? 'Показать один день'
                      : 'Показать три дня',
                  onPressed: () => setState(() => _threeDays = !_threeDays),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => _select(shiftDay(_day, -1)),
                    tooltip: 'Предыдущий день',
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        final picked = await pickDay(context, _day);
                        if (picked != null && mounted) _select(picked);
                      },
                      child: Text(
                        monthTitle(_day),
                        style: const TextStyle(
                          fontFamily: 'TempusSerif',
                          fontSize: 15,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _select(shiftDay(_day, 1)),
                    tooltip: 'Следующий день',
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: _hourMargin, right: 9),
              child: Row(
                children: [
                  for (final date in positions)
                    Expanded(
                      child: TextButton(
                        key: ValueKey(dayKey(date)),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                        ),
                        onPressed: () => _select(date),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              DateFormat('EEE', 'ru').format(date),
                              style: const TextStyle(
                                color: muted,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 4),
                            AnimatedContainer(
                              duration: motion(context, 200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: date == _day
                                    ? bronze
                                    : Colors.transparent,
                                border: date == today && date != _day
                                    ? Border.all(color: bronze)
                                    : null,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                '${date.day}',
                                style: TextStyle(
                                  color: date == _day ? ink : paper,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 1, 10, 5),
              child: Row(
                children: [
                  if (_day != today)
                    TextButton(
                      onPressed: () => _select(today),
                      child: const Text('Сегодня'),
                    ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _agenda(context),
                        icon: const Icon(Icons.list_alt_rounded, size: 17),
                        label: Text(
                          noTime > 0
                              ? 'Дела дня · $noTime без времени'
                              : 'Дела дня',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: GestureDetector(
                onHorizontalDragEnd: (event) {
                  final velocity = event.primaryVelocity ?? 0;
                  if (velocity.abs() > 75) {
                    _select(shiftDay(_day, velocity > 0 ? -1 : 1));
                  }
                },
                child: Scrollbar(
                  controller: _scroll,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.only(right: 9, bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(
                          width: _hourMargin,
                          height:
                              _topPadding + minutesPerDay * _minuteHeight + 12,
                          child: _HourLabels(),
                        ),
                        for (final date in visible)
                          Expanded(
                            child: _DayColumn(
                              key: ValueKey(dayKey(date)),
                              date: date,
                              blocks: _placeBlocks(
                                plansFor(snapshot.records, date),
                              ),
                              currentMinute: date == today ? _minuteNow : null,
                              onAdd: (minute) =>
                                  _newTask(context, date, minute),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _HourLabels extends StatelessWidget {
  const _HourLabels();

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      for (var hour = 0; hour <= 24; hour++)
        Positioned(
          top: _topPadding + hour * 60 * _minuteHeight - 7,
          left: 0,
          right: 5,
          child: Text(
            minuteLabel(hour * 60),
            textAlign: TextAlign.right,
            style: const TextStyle(color: muted, fontSize: 10),
          ),
        ),
    ],
  );
}

typedef _LayoutBlock = ({Record row, int lane, int columns});

List<_LayoutBlock> _placeBlocks(List<Record> rows) {
  final ordered = rows.where((row) => row.timeRange != null).toList()
    ..sort((a, b) {
      final order = a.timeRange!.start.compareTo(b.timeRange!.start);
      return order == 0 ? b.timeRange!.end.compareTo(a.timeRange!.end) : order;
    });
  final result = <_LayoutBlock>[];
  final group = <(Record, int)>[];
  final laneEnds = <int>[];
  var groupEnd = 0;
  void flush() {
    result.addAll(
      group.map(
        (item) => (row: item.$1, lane: item.$2, columns: laneEnds.length),
      ),
    );
    group.clear();
    laneEnds.clear();
  }

  for (final row in ordered) {
    final range = row.timeRange!;
    if (range.start >= groupEnd) {
      flush();
      groupEnd = 0;
    }
    var lane = laneEnds.indexWhere((end) => end <= range.start);
    if (lane < 0) {
      lane = laneEnds.length;
      laneEnds.add(range.end);
    } else {
      laneEnds[lane] = range.end;
    }
    groupEnd = math.max(groupEnd, range.end);
    group.add((row, lane));
  }
  flush();
  return result;
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.date,
    required this.blocks,
    required this.currentMinute,
    required this.onAdd,
    super.key,
  });

  final DateTime date;
  final List<_LayoutBlock> blocks;
  final int? currentMinute;
  final ValueChanged<int> onAdd;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: _topPadding + minutesPerDay * _minuteHeight + 12,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (event) {
                  final minute =
                      ((event.localPosition.dy - _topPadding) / _minuteHeight)
                          .floor();
                  if (minute >= 0 && minute < minutesPerDay) onAdd(minute);
                },
                child: const CustomPaint(painter: _DayGrid()),
              ),
            ),
            for (final block in blocks)
              Positioned(
                top: _topPadding + block.row.timeRange!.start * _minuteHeight,
                left:
                    block.lane * (width / block.columns) +
                    math.min(2, width / block.columns * .06),
                width:
                    width / block.columns -
                    math.min(4, width / block.columns * .12),
                height:
                    (block.row.timeRange!.end - block.row.timeRange!.start) *
                    _minuteHeight,
                child: _BlockTile(row: block.row, date: date),
              ),
            if (currentMinute case final minute?)
              Positioned(
                top: _topPadding + minute * _minuteHeight - 3,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: bronze,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const Expanded(
                        child: Divider(thickness: 1, color: bronze),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _DayGrid extends CustomPainter {
  const _DayGrid();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xff1b1511),
    );
    final line = Paint()..strokeWidth = .75;
    for (var minute = 0; minute <= minutesPerDay; minute += 15) {
      final y = _topPadding + minute * _minuteHeight;
      line.color = minute % 60 == 0 ? border : border.withValues(alpha: .35);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    line.color = border;
    canvas.drawLine(Offset.zero, Offset(0, size.height), line);
  }

  @override
  bool shouldRepaint(_DayGrid oldDelegate) => false;
}

class _BlockTile extends ConsumerWidget {
  const _BlockTile({required this.row, required this.date});

  final Record row;
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = row.timeRange!;
    final done = row.doneOn(date);
    final time = '${minuteLabel(range.start)}–${minuteLabel(range.end)}';
    final accent = done ? sage : bronze;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final labelFits = height >= 19 && width >= 28;
        final timeFits = height >= 36 && width >= 55;
        final canCheck = width >= 85 && height >= 44;
        return Semantics(
          button: true,
          label: '${row.title}, $time',
          child: Material(
            color: done ? const Color(0xff2d3227) : const Color(0xff453122),
            shape: RoundedRectangleBorder(
              side: BorderSide(
                color: accent.withValues(alpha: height < 9 ? .95 : .5),
              ),
              borderRadius: BorderRadius.circular(height < 12 ? 1 : 6),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => editRecord(
                context,
                record: row,
                kinds: [row.kind],
                date: date,
              ),
              child: labelFits
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (canCheck)
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 31,
                              height: 42,
                            ),
                            visualDensity: const VisualDensity(
                              horizontal: -2,
                              vertical: -2,
                            ),
                            tooltip: done
                                ? 'Снять отметку: ${row.title}'
                                : 'Выполнить: ${row.title}',
                            icon: Icon(
                              done
                                  ? Icons.check_box_outlined
                                  : Icons.check_box_outline_blank,
                              size: 16,
                              color: accent,
                            ),
                            onPressed: () async {
                              try {
                                await ref
                                    .read(recordsProvider.notifier)
                                    .toggle(row.id, date);
                                HapticFeedback.selectionClick();
                              } catch (_) {
                                if (context.mounted) {
                                  notify(context, 'Не удалось обновить дело');
                                }
                              }
                            },
                          ),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              canCheck ? 0 : 5,
                              height >= 27 ? 4 : 1,
                              4,
                              0,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  row.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    height: 1.15,
                                    color: done ? muted : paper,
                                    decoration: done
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                  textScaler: TextScaler.noScaling,
                                ),
                                if (timeFits)
                                  Text(
                                    time,
                                    maxLines: 1,
                                    overflow: TextOverflow.clip,
                                    style: TextStyle(
                                      color: accent,
                                      fontSize: 9,
                                      height: 1.15,
                                    ),
                                    textScaler: TextScaler.noScaling,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : null,
            ),
          ),
        );
      },
    );
  }
}
