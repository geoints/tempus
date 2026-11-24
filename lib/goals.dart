// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'design.dart';
import 'editor.dart';
import 'records.dart';
import 'store.dart';

class GoalGrid extends StatelessWidget {
  const GoalGrid(this.goals, {super.key});

  final List<Record> goals;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 9.0;
      final largeText = MediaQuery.textScalerOf(context).scale(13) > 17;
      final columns = largeText || constraints.maxWidth < 286 ? 2 : 3;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final goal in goals)
            SizedBox(
              width: width,
              child: _GoalTile(key: ValueKey(goal.id), goal: goal),
            ),
        ],
      );
    },
  );
}

class _GoalTile extends ConsumerStatefulWidget {
  const _GoalTile({required this.goal, super.key});
  final Record goal;

  @override
  ConsumerState<_GoalTile> createState() => _GoalTileState();
}

class _GoalTileState extends ConsumerState<_GoalTile> {
  bool _pressed = false;

  Future<void> _log(DateTime day) async {
    try {
      await ref.read(recordsProvider.notifier).logGoal(widget.goal.id, day);
      HapticFeedback.lightImpact();
    } catch (_) {
      if (mounted) notify(context, 'Не удалось добавить отметку');
    }
  }

  @override
  Widget build(BuildContext context) {
    final goal = widget.goal;
    final today = dayOnly(DateTime.now());
    final canLogToday = goal.occursOn(today) && goal.goalCount < maxGoalTarget;
    final complete = goal.goalCount >= goal.target;
    final color = complete ? sage : bronze;

    return AnimatedScale(
      scale: _pressed ? .965 : 1,
      duration: motion(context, 130),
      child: Material(
        color: const Color(0xff281e17),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: BorderSide(
            color: complete ? sage.withValues(alpha: .42) : border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xff35251a), Color(0xff211811)],
            ),
          ),
          child: Column(
            children: [
              InkWell(
                onTap: () =>
                    canLogToday ? _log(today) : openGoal(context, goal.id),
                onLongPress: () => openGoal(context, goal.id),
                onHighlightChanged: (pressed) =>
                    setState(() => _pressed = pressed),
                child: Semantics(
                  label: canLogToday
                      ? 'Отметить: ${goal.goalTitle}'
                      : 'Открыть цель: ${goal.goalTitle}',
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(7, 13, 7, 7),
                    child: Column(
                      children: [
                        Icon(areaIcon(goal.area), size: 22, color: color),
                        const SizedBox(height: 7),
                        Text(
                          goal.goalTitle,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, height: 1.15),
                        ),
                        const SizedBox(height: 6),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: AnimatedValue(
                            '${goal.goalCount} / ${goal.target}',
                            style: TextStyle(
                              color: color,
                              fontSize: 17,
                              fontFamily: 'TempusSerif',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ProgressTrack(goal.goalCount / goal.target),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 40,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (canLogToday)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _log(today),
                        tooltip: 'Добавить отметку: ${goal.goalTitle}',
                        icon: Icon(
                          complete
                              ? Icons.add_circle_outline
                              : Icons.add_rounded,
                          size: 19,
                          color: color,
                        ),
                      ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => openGoal(context, goal.id),
                      tooltip: 'Подробнее: ${goal.goalTitle}',
                      icon: const Icon(
                        Icons.more_horiz,
                        color: muted,
                        size: 19,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> openGoal(BuildContext context, int id) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _GoalDetails(id),
    );

class _GoalDetails extends ConsumerWidget {
  const _GoalDetails(this.id);
  final int id;

  Future<void> _logPast(
    BuildContext context,
    WidgetRef ref,
    Record goal,
    DateTime today,
  ) async {
    final start = DateTime(goal.date.year, goal.date.month);
    final end = DateTime(goal.date.year, goal.date.month + 1, 0);
    final last = end.isAfter(today) ? today : end;
    final date = await showDatePicker(
      context: context,
      initialDate: last,
      firstDate: start,
      lastDate: last,
    );
    if (date == null || !context.mounted) return;
    try {
      await ref.read(recordsProvider.notifier).logGoal(id, date);
      HapticFeedback.lightImpact();
    } catch (_) {
      if (context.mounted) notify(context, 'Не удалось добавить отметку');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goal = ref
        .watch(recordsProvider)
        .valueOrNull
        ?.records
        .where((row) => row.id == id)
        .firstOrNull;
    if (goal == null) return const SizedBox.shrink();
    final today = dayOnly(DateTime.now());
    final monthStarted = !DateTime(
      goal.date.year,
      goal.date.month,
    ).isAfter(today);
    final sessionCounts = <String, int>{};
    for (final day in goal.sessions) {
      sessionCounts.update(day, (value) => value + 1, ifAbsent: () => 1);
    }
    final dates = sessionCounts.keys.toList()..sort((a, b) => b.compareTo(a));
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .72,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
          children: [
            PageHeading(
              goal.goalTitle,
              subtitle: monthTitle(goal.date),
              action: IconButton(
                tooltip: 'Редактировать цель',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => editRecord(
                  context,
                  record: goal,
                  kinds: const [Kind.goal],
                  date: goal.date,
                ),
              ),
            ),
            const SizedBox(height: 13),
            Text(
              'Выполнено ${goal.goalCount} из ${goal.target}',
              style: const TextStyle(color: bronze),
            ),
            const SizedBox(height: 10),
            ProgressTrack(goal.goalCount / goal.target),
            const SizedBox(height: 13),
            if (monthStarted && goal.goalCount < maxGoalTarget)
              FilledButton.icon(
                icon: const Icon(Icons.event_available_outlined),
                onPressed: () => _logPast(context, ref, goal, today),
                label: const Text('Отметить на дату'),
              ),
            if (dates.isNotEmpty) ...[
              const SizedBox(height: 14),
              const SectionTitle('История отметок'),
              for (final day in dates)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(shortDate(DateTime.parse(day))),
                  subtitle: Text('Отметок · ${sessionCounts[day]}'),
                  trailing: IconButton(
                    tooltip:
                        'Убрать одну отметку за ${shortDate(DateTime.parse(day))}',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () async {
                      try {
                        await ref
                            .read(recordsProvider.notifier)
                            .undoGoal(id, day);
                      } catch (_) {
                        if (context.mounted) {
                          notify(context, 'Не удалось убрать отметку');
                        }
                      }
                    },
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
