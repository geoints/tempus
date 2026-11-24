import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'design.dart';
import 'editor.dart';
import 'export.dart';
import 'pages.dart' show WithRecords;
import 'records.dart';
import 'store.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String error) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on SecretBoxAuthenticationError {
      if (mounted) notify(context, 'Неверный пароль или повреждённая копия');
    } on FormatException {
      if (mounted) {
        notify(context, 'Файл повреждён или его формат не поддерживается');
      }
    } catch (_) {
      if (mounted) notify(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() => _run(() async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _PasswordDialog(saving: true),
    );
    if (password == null || !mounted) return;
    final snapshot = await ref.read(recordsProvider.notifier).backupSnapshot();
    final bytes = await Backup.encode(snapshot, password);
    if (bytes.length > Backup.maxBytes) {
      if (mounted) notify(context, 'Копия превышает 128 МБ');
      return;
    }
    final suffix = DateTime.now().millisecondsSinceEpoch;
    final path = await saveFile(
      'TEMPUS-${dayKey(DateTime.now())}-$suffix.tempus',
      Uint8List.fromList(bytes),
    );
    if (mounted && path != null) notify(context, 'Резервная копия сохранена');
  }, 'Не удалось сохранить резервную копию');

  Future<void> _restore() => _run(() async {
    final selection = await FilePicker.platform.pickFiles();
    if (selection == null || !mounted) return;
    final selected = selection.files.single;
    if (selected.path == null) {
      throw const FileSystemException('File unavailable');
    }
    final file = File(selected.path!);
    if (await file.length() > Backup.maxBytes) {
      if (mounted) notify(context, 'Копия превышает 128 МБ');
      return;
    }
    final encoded = Backup.inspect(await file.readAsBytes());
    if (!mounted) return;
    final password = Backup.isEncrypted(encoded)
        ? await showDialog<String>(
            context: context,
            builder: (_) => const _PasswordDialog(saving: false),
          )
        : '';
    if (password == null || !mounted) return;
    final snapshot = await Backup.decode(encoded, password);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Восстановить данные?'),
        content: Text(
          'Копия содержит ${snapshot.records.length} записей. Она заменит данные и настройки на устройстве.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Восстановить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(recordsProvider.notifier).restore(snapshot);
    if (mounted) notify(context, 'Данные восстановлены');
  }, 'Не удалось восстановить резервную копию');

  Future<void> _name(Snapshot snapshot) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(initial: snapshot.name),
    );
    if (!mounted || name == null) return;
    await _run(
      () => ref
          .read(recordsProvider.notifier)
          .profile(name, DateTime.parse(snapshot.history)),
      'Не удалось сохранить имя',
    );
  }

  @override
  Widget build(BuildContext context) => WithRecords(
    builder: (snapshot) => PageList(
      children: [
        const PageHeading('Профиль', subtitle: 'TEMPUS'),
        Surface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.person_outline, color: bronze),
                title: Text(snapshot.name.isEmpty ? 'Имя' : snapshot.name),
                subtitle: Text(
                  snapshot.name.isEmpty
                      ? 'Настроить приветствие'
                      : 'Изменить имя',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy ? null : () => _name(snapshot),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.history, color: bronze),
                title: const Text('Начало истории'),
                subtitle: Text(monthTitle(DateTime.parse(snapshot.history))),
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy
                    ? null
                    : () async {
                        final picked = await pickDay(
                          context,
                          DateTime.parse(snapshot.history),
                        );
                        if (picked == null || !mounted) return;
                        await _run(
                          () => ref
                              .read(recordsProvider.notifier)
                              .profile(snapshot.name, picked),
                          'Не удалось изменить начало истории',
                        );
                      },
              ),
            ],
          ),
        ),
        const SectionTitle('Резервные копии'),
        Surface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.file_download_outlined,
                  color: bronze,
                ),
                title: const Text('Экспортировать данные'),
                subtitle: const Text('Записи, отметки, настройки и фото'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy ? null : _export,
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.restore, color: bronze),
                title: const Text('Восстановить из файла'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy ? null : _restore,
              ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        const EmptyCard(
          'Данные хранятся на этом устройстве. Сохраняй копии вне приложения, чтобы восстановить историю после переустановки.',
          icon: Icons.lock_outline,
        ),
      ],
    ),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial});
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Имя'),
    content: TextField(
      controller: _controller,
      maxLength: 32,
      textCapitalization: TextCapitalization.words,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Как к тебе обращаться'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
        child: const Text('Сохранить'),
      ),
    ],
  );
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.saving});
  final bool saving;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();
  final _confirmation = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _visible = false;

  @override
  void dispose() {
    _controller.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.saving ? 'Защитить копию паролем' : 'Пароль резервной копии',
    ),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.saving) ...[
              const Text(
                'Пароль понадобится для восстановления. Минимум 8 символов.',
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _controller,
              autofocus: true,
              obscureText: !_visible,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Пароль',
                suffixIcon: IconButton(
                  tooltip: _visible ? 'Скрыть пароль' : 'Показать пароль',
                  onPressed: () => setState(() => _visible = !_visible),
                  icon: Icon(
                    _visible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
              validator: (text) => (text?.length ?? 0) < (widget.saving ? 8 : 1)
                  ? 'Введи пароль'
                  : null,
            ),
            if (widget.saving) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmation,
                obscureText: !_visible,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'Повтори пароль'),
                validator: (text) =>
                    text != _controller.text ? 'Пароли не совпадают' : null,
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      if (widget.saving)
        TextButton(
          onPressed: () => Navigator.pop(context, ''),
          child: const Text('Без пароля'),
        ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, _controller.text);
          }
        },
        child: Text(widget.saving ? 'Сохранить' : 'Открыть'),
      ),
    ],
  );
}
