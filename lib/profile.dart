// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'design.dart';
import 'editor.dart';
import 'pages.dart' show WithRecords;
import 'records.dart';
import 'store.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => WithRecords(
    builder: (snapshot) => PageList(
      children: [
        const PageHeading('Профиль'),
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
                onTap: () async {
                  final name = await showDialog<String>(
                    context: context,
                    builder: (_) => _NameDialog(initial: snapshot.name),
                  );
                  if (context.mounted && name != null) {
                    await _update(
                      context,
                      ref,
                      name,
                      DateTime.parse(snapshot.history),
                    );
                  }
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.history, color: bronze),
                title: const Text('Начало истории'),
                subtitle: Text(monthTitle(DateTime.parse(snapshot.history))),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final date = await pickDay(
                    context,
                    DateTime.parse(snapshot.history),
                  );
                  if (context.mounted && date != null) {
                    await _update(context, ref, snapshot.name, date);
                  }
                },
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Future<void> _update(
    BuildContext context,
    WidgetRef ref,
    String name,
    DateTime date,
  ) async {
    try {
      await ref.read(recordsProvider.notifier).profile(name, date);
    } catch (_) {
      if (context.mounted) notify(context, 'Не удалось сохранить настройки');
    }
  }
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
      autofocus: true,
      textCapitalization: TextCapitalization.words,
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
