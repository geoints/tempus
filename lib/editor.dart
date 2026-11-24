import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'design.dart';
import 'records.dart';
import 'store.dart';

Future<DateTime?> pickDay(BuildContext context, DateTime date) =>
    showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
    );

void notify(BuildContext context, String message) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(message)));

Future<void> editRecord(
  BuildContext context, {
  Record? record,
  required List<Kind> kinds,
  required DateTime date,
  TimeRange? initialTime,
}) => Navigator.of(context, rootNavigator: true).push<void>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _Editor(
      record: record,
      kinds: kinds,
      date: date,
      initialTime: initialTime,
    ),
  ),
);

class _Editor extends ConsumerStatefulWidget {
  const _Editor({
    required this.record,
    required this.kinds,
    required this.date,
    required this.initialTime,
  });

  final Record? record;
  final List<Kind> kinds;
  final DateTime date;
  final TimeRange? initialTime;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.record?.title);
  late final _target = TextEditingController(
    text: (widget.record?.target ?? 1).toString(),
  );
  late final _start = TextEditingController(
    text: _initialTime == null ? '' : minuteLabel(_initialTime!.start),
  );
  late final _end = TextEditingController(
    text: _initialTime == null ? '' : minuteLabel(_initialTime!.end),
  );
  TimeRange? get _initialTime => widget.record?.timeRange ?? widget.initialTime;
  late bool _timed = _initialTime != null;
  late final _amount = TextEditingController(
    text: widget.record == null || !widget.record!.kind.isMoney
        ? ''
        : (widget.record!.amount / 100).toString(),
  );
  late Kind _kind = widget.record?.kind ?? widget.kinds.first;
  late DateTime _date = widget.record?.date ?? widget.date;
  late String _area = widget.record?.area ?? 'Личное';
  late Set<int> _days = {...?widget.record?.weekdays};
  late int? _reminder = widget.record?.reminder;
  String? _photo;
  bool _busy = false;
  @override
  void dispose() {
    _title.dispose();
    _start.dispose();
    _end.dispose();
    _target.dispose();
    _amount.dispose();
    super.dispose();
  }

  int? _minorUnits(String input) {
    final value = input.trim().replaceAll(',', '.');
    if (!RegExp(r'^\d{1,9}(\.\d{1,2})?$').hasMatch(value)) return null;
    final pieces = value.split('.');
    final result =
        int.parse(pieces.first) * 100 +
        (pieces.length == 1 ? 0 : int.parse(pieces.last.padRight(2, '0')));
    return result > 0 ? result : null;
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) {
      return;
    }
    if (_kind == Kind.habit && _days.isEmpty) {
      notify(context, 'Выбери хотя бы один день недели');
      return;
    }
    final controller = ref.read(recordsProvider.notifier);
    setState(() => _busy = true);
    try {
      final reminder = _kind.isPlan ? _reminder : null;
      var permitted = true;
      if (reminder != null) {
        try {
          permitted = await controller.reminders.request();
        } catch (_) {
          permitted = false;
        }
      }
      await controller.save(
        Record(
          id: widget.record?.id ?? 0,
          kind: _kind,
          date: _date,
          title: _title.text.trim(),
          notes: widget.record?.notes ?? '',
          timeRange: _kind.canSchedule && _timed
              ? (start: parseMinute(_start.text)!, end: parseMinute(_end.text)!)
              : null,
          area: _area,
          checked: widget.record?.checked ?? {},
          target: _kind == Kind.goal ? int.parse(_target.text.trim()) : 1,
          sessions: widget.record?.sessions ?? const [],
          weekdays: _kind == Kind.habit ? _days : {},
          amount: _kind.isMoney ? _minorUnits(_amount.text)! : 0,
          reminder: reminder,
          photo: !_kind.isPlan && !_kind.isMoney ? _photo : null,
        ),
      );
      if (!mounted) return;
      if (!permitted) {
        notify(
          context,
          'Запись сохранена. Разреши уведомления TEMPUS в настройках Android.',
        );
      }
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) notify(context, 'Не удалось сохранить запись');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _validateStart(String? value) {
    final minute = parseMinute(value ?? '');
    return minute == null || minute == minutesPerDay ? 'Укажи время' : null;
  }

  String? _validateEnd(String? value) {
    final end = parseMinute(value ?? '');
    if (end == null) return 'Укажи время';
    final start = parseMinute(_start.text);
    return start != null && end <= start ? 'Позже начала' : null;
  }

  Future<void> _pickPhoto() async {
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (!mounted || result == null) return;
      final file = result.files.single;
      if (file.size > photoLimit) {
        notify(context, 'Максимальный размер фото — 15 МБ');
        return;
      }
      final path = file.path;
      if (path == null) throw const FileSystemException('Photo is unavailable');
      final bytes = await File(path).readAsBytes();
      if (bytes.isEmpty || bytes.length > photoLimit) {
        throw const FormatException('Unsupported image size');
      }
      if (mounted) setState(() => _photo = base64Encode(bytes));
    } catch (_) {
      if (mounted) notify(context, 'Не удалось открыть фото');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить запись?'),
        content: Text(widget.record!.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(recordsProvider.notifier).remove(widget.record!.id);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) notify(context, 'Не удалось удалить запись');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reminder = _reminder;
    final photo = _photo;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.record == null ? 'Новая запись' : 'Запись'),
          actions: [
            if (widget.record != null)
              IconButton(
                onPressed: _busy ? null : _remove,
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Удалить запись',
              ),
          ],
        ),
        body: SafeArea(
          child: Form(
            key: _form,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 660),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 15,
                    children: [
                      if (widget.record == null && widget.kinds.length > 1)
                        DropdownButtonFormField<Kind>(
                          initialValue: _kind,
                          decoration: const InputDecoration(
                            labelText: 'Тип записи',
                          ),
                          items: widget.kinds
                              .map(
                                (kind) => DropdownMenuItem(
                                  value: kind,
                                  child: Text(kind.label),
                                ),
                              )
                              .toList(),
                          onChanged: _busy
                              ? null
                              : (value) => setState(() {
                                  final previous = _kind;
                                  _kind = value!;
                                  if (previous == Kind.goal &&
                                      _kind != Kind.goal &&
                                      _date ==
                                          DateTime(
                                            widget.date.year,
                                            widget.date.month + 1,
                                            0,
                                          )) {
                                    _date = widget.date;
                                  }
                                  if (_kind == Kind.goal) {
                                    _date = DateTime(
                                      _date.year,
                                      _date.month + 1,
                                      0,
                                    );
                                  }
                                  if (_kind == Kind.habit && _days.isEmpty) {
                                    _days = {1, 2, 3, 4, 5, 6, 7};
                                  }
                                }),
                        )
                      else
                        PageHeading(_kind.label),
                      TextFormField(
                        controller: _title,
                        enabled: !_busy,
                        maxLength: 120,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Название',
                        ),
                        validator: (text) => text == null || text.trim().isEmpty
                            ? 'Введи название'
                            : null,
                      ),
                      if (_kind == Kind.goal)
                        TextFormField(
                          controller: _target,
                          enabled: !_busy,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'План на месяц · сколько раз',
                          ),
                          validator: (text) {
                            final target = int.tryParse(text?.trim() ?? '');
                            return target == null ||
                                    target < 1 ||
                                    target > maxGoalTarget
                                ? 'Введи число от 1 до $maxGoalTarget'
                                : null;
                          },
                        ),
                      DropdownButtonFormField<String>(
                        initialValue: _area,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Сфера'),
                        items: areas
                            .map(
                              (area) => DropdownMenuItem(
                                value: area,
                                child: Text(area),
                              ),
                            )
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _area = value!),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () async {
                                final date = await pickDay(context, _date);
                                if (date != null && context.mounted) {
                                  final record = widget.record;
                                  if (record != null &&
                                      record.kind == Kind.goal &&
                                      record.sessions.isNotEmpty &&
                                      !record.occursOn(date)) {
                                    notify(
                                      context,
                                      'У цели уже есть отметки за этот месяц',
                                    );
                                    return;
                                  }
                                  setState(() => _date = date);
                                }
                              },
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: Text(
                          '${switch (_kind) {
                            Kind.habit => 'Начало',
                            Kind.goal => 'Срок',
                            _ => 'Дата',
                          }} · ${shortDate(_date)} ${_date.year}',
                        ),
                      ),
                      if (_kind == Kind.habit) ...[
                        const SectionTitle('Дни повторения'),
                        Wrap(
                          spacing: 7,
                          runSpacing: 5,
                          children: List.generate(7, (index) {
                            final day = index + 1;
                            return FilterChip(
                              label: Text(
                                const [
                                  'Пн',
                                  'Вт',
                                  'Ср',
                                  'Чт',
                                  'Пт',
                                  'Сб',
                                  'Вс',
                                ][index],
                              ),
                              selected: _days.contains(day),
                              onSelected: _busy
                                  ? null
                                  : (selected) => setState(() {
                                      if (selected) {
                                        _days.add(day);
                                      } else {
                                        _days.remove(day);
                                      }
                                    }),
                            );
                          }),
                        ),
                      ],
                      if (_kind.isMoney)
                        TextFormField(
                          controller: _amount,
                          enabled: !_busy,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Сумма, ₸',
                          ),
                          validator: (text) => _minorUnits(text ?? '') == null
                              ? 'Введи положительную сумму'
                              : null,
                        ),
                      if (_kind.canSchedule) ...[
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Время в расписании'),
                          value: _timed,
                          onChanged: _busy
                              ? null
                              : (value) => setState(() {
                                  _timed = value;
                                  if (value && _start.text.isEmpty) {
                                    final now = TimeOfDay.now();
                                    final start =
                                        _date == dayOnly(DateTime.now())
                                        ? now.hour * 60 + now.minute
                                        : 9 * 60;
                                    _start.text = minuteLabel(start);
                                    _end.text = minuteLabel(
                                      (start + 30).clamp(1, minutesPerDay),
                                    );
                                  }
                                }),
                        ),
                        if (_timed)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _start,
                                  enabled: !_busy,
                                  keyboardType: TextInputType.datetime,
                                  decoration: const InputDecoration(
                                    labelText: 'Начало',
                                    hintText: '08:07',
                                  ),
                                  validator: _validateStart,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextFormField(
                                  controller: _end,
                                  enabled: !_busy,
                                  keyboardType: TextInputType.datetime,
                                  decoration: const InputDecoration(
                                    labelText: 'Конец',
                                    hintText: '08:08',
                                  ),
                                  validator: _validateEnd,
                                ),
                              ),
                            ],
                          ),
                      ],
                      if (_kind.isPlan)
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        final value = await showTimePicker(
                                          context: context,
                                          initialTime: reminder == null
                                              ? TimeOfDay.now()
                                              : TimeOfDay(
                                                  hour: reminder ~/ 60,
                                                  minute: reminder % 60,
                                                ),
                                        );
                                        if (value != null && mounted) {
                                          setState(
                                            () => _reminder =
                                                value.hour * 60 + value.minute,
                                          );
                                        }
                                      },
                                icon: const Icon(Icons.notifications_none),
                                label: Text(
                                  reminder == null
                                      ? 'Добавить напоминание'
                                      : 'Напоминание · ${TimeOfDay(hour: reminder ~/ 60, minute: reminder % 60).format(context)}',
                                ),
                              ),
                            ),
                            if (reminder != null)
                              IconButton(
                                onPressed: _busy
                                    ? null
                                    : () => setState(() => _reminder = null),
                                tooltip: 'Убрать напоминание',
                                icon: const Icon(Icons.close),
                              ),
                          ],
                        ),
                      if (_kind.isArchive && widget.record == null) ...[
                        if (photo != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(13),
                            child: Image.memory(
                              base64Decode(photo),
                              height: 230,
                              fit: BoxFit.cover,
                              cacheWidth: 1080,
                              errorBuilder: (_, _, _) => const EmptyCard(
                                'Формат фото не поддерживается',
                              ),
                            ),
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _busy ? null : _pickPhoto,
                                icon: const Icon(Icons.photo_outlined),
                                label: Text(
                                  photo == null
                                      ? 'Выбрать фотообложку'
                                      : 'Заменить обложку',
                                ),
                              ),
                            ),
                            if (photo != null)
                              IconButton(
                                onPressed: _busy
                                    ? null
                                    : () => setState(() => _photo = null),
                                tooltip: 'Убрать обложку',
                                icon: const Icon(Icons.close),
                              ),
                          ],
                        ),
                      ],
                      FilledButton.icon(
                        onPressed: _busy ? null : _save,
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check),
                        label: const Text('Сохранить'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
