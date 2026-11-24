import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'design.dart';
import 'editor.dart';
import 'film_camera.dart';
import 'photography.dart';
import 'records.dart';
import 'store.dart';

Future<void> openPhotoAlbum(BuildContext context, int id) => Navigator.of(
  context,
  rootNavigator: true,
).push<void>(MaterialPageRoute(builder: (_) => _PhotoAlbum(id: id)));

class _PhotoAlbum extends ConsumerStatefulWidget {
  const _PhotoAlbum({required this.id});
  final int id;

  @override
  ConsumerState<_PhotoAlbum> createState() => _PhotoAlbumState();
}

class _PhotoAlbumState extends ConsumerState<_PhotoAlbum> {
  bool _busy = false;

  Future<void> _save(Uint8List bytes, RecordsController controller) async {
    if (bytes.isEmpty || bytes.length > maxAlbumPhotoBytes) {
      throw const FormatException('Invalid photo size');
    }
    final thumbnail = await makePhotoThumbnail(bytes);
    await controller.addPhoto(widget.id, AlbumPhotoData(bytes, thumbnail));
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picks = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );
      if (picks == null || !mounted) return;
      final controller = ref.read(recordsProvider.notifier);
      var saved = 0;
      var failed = 0;
      for (final pick in picks.files) {
        if (!mounted) return;
        try {
          final path = pick.path;
          if (path == null || pick.size > maxAlbumPhotoBytes) {
            failed++;
            continue;
          }
          final file = File(path);
          if (await file.length() > maxAlbumPhotoBytes) {
            failed++;
            continue;
          }
          await _save(await file.readAsBytes(), controller);
          saved++;
        } catch (_) {
          failed++;
        }
      }
      if (mounted && failed > 0) {
        notify(
          context,
          'Добавлено $saved из ${picks.files.length}. Проверь формат и размер файлов (до 64 МБ).',
        );
      }
    } catch (_) {
      if (mounted) notify(context, 'Не удалось импортировать фотографии');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _capture() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final photo = await openFilmCamera(context, forAlbum: true);
      if (photo == null || !mounted) return;
      await _save(photo, ref.read(recordsProvider.notifier));
    } catch (_) {
      if (mounted) notify(context, 'Не удалось добавить снимок');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = ref
        .watch(recordsProvider)
        .valueOrNull
        ?.records
        .where((item) => item.id == widget.id && item.kind.isArchive)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Фотоальбом'),
        actions: [
          if (row != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Редактировать запись',
              onPressed: _busy
                  ? null
                  : () async {
                      await editRecord(
                        context,
                        record: row,
                        date: row.date,
                        kinds: [row.kind],
                      );
                      if (!mounted) return;
                      if (ref
                              .read(recordsProvider)
                              .valueOrNull
                              ?.records
                              .any((item) => item.id == widget.id) ==
                          false) {
                        Navigator.of(this.context).pop();
                      }
                    },
            ),
        ],
      ),
      body: row == null
          ? const Center(child: Text('Запись удалена'))
          : SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: PageHeading(
                      row.title,
                      subtitle:
                          '${row.kind.label} · ${shortDate(row.date)} ${row.date.year}',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 5,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _busy ? null : _import,
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: const Text('Добавить фото'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _capture,
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Снять'),
                        ),
                      ],
                    ),
                  ),
                  if (_busy) const LinearProgressIndicator(),
                  Expanded(
                    child: ref
                        .watch(albumProvider(widget.id))
                        .when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (_, _) => Center(
                            child: TextButton(
                              onPressed: () =>
                                  ref.invalidate(albumProvider(widget.id)),
                              child: const Text('Повторить загрузку фото'),
                            ),
                          ),
                          data: (photos) => photos.isEmpty
                              ? const Center(
                                  child: Text(
                                    'В альбоме пока нет фотографий',
                                    style: TextStyle(color: muted),
                                  ),
                                )
                              : GridView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    5,
                                    16,
                                    22,
                                  ),
                                  itemCount: photos.length,
                                  gridDelegate:
                                      const SliverGridDelegateWithMaxCrossAxisExtent(
                                        maxCrossAxisExtent: 160,
                                        crossAxisSpacing: 8,
                                        mainAxisSpacing: 8,
                                      ),
                                  itemBuilder: (context, index) => _AlbumTile(
                                    key: ValueKey(photos[index].id),
                                    photo: photos[index],
                                    onOpen: () =>
                                        Navigator.of(context).push<void>(
                                          MaterialPageRoute(
                                            builder: (_) => _PhotoViewer(
                                              recordId: widget.id,
                                              photos: photos,
                                              index: index,
                                            ),
                                          ),
                                        ),
                                  ),
                                ),
                        ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _AlbumTile extends ConsumerWidget {
  const _AlbumTile({required this.photo, required this.onOpen, super.key});
  final AlbumPhoto photo;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(albumThumbProvider(photo.id)).valueOrNull;
    return Surface(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onOpen,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (bytes == null)
              const _ImageUnavailable()
            else
              Image.memory(
                bytes,
                fit: BoxFit.cover,
                cacheWidth: 480,
                errorBuilder: (_, _, _) => const _ImageUnavailable(),
              ),
            if (photo.isCover)
              const Positioned(
                left: 6,
                bottom: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: ink,
                    borderRadius: BorderRadius.all(Radius.circular(7)),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Text(
                      'Обложка',
                      style: TextStyle(color: bronze, fontSize: 10),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

final _fullPhotoProvider = FutureProvider.autoDispose.family<Uint8List?, int>(
  (ref, id) => ref.watch(databaseProvider).albumImage(id),
);

class _PhotoViewer extends ConsumerStatefulWidget {
  const _PhotoViewer({
    required this.recordId,
    required this.photos,
    required this.index,
  });
  final int recordId;
  final List<AlbumPhoto> photos;
  final int index;

  @override
  ConsumerState<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends ConsumerState<_PhotoViewer> {
  late int _index = widget.index;
  late final _pages = PageController(initialPage: _index);
  bool _busy = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _chooseCover() async {
    final photo = widget.photos[_index];
    setState(() => _busy = true);
    try {
      await ref
          .read(recordsProvider.notifier)
          .chooseCover(widget.recordId, photo.id);
      if (mounted) notify(context, 'Обложка обновлена');
    } catch (_) {
      if (mounted) notify(context, 'Не удалось обновить обложку');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final photo = widget.photos[_index];
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Убрать это фото из альбома?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Убрать'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(recordsProvider.notifier)
          .removePhoto(widget.recordId, photo.id);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) notify(context, 'Не удалось убрать фото');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final persisted = ref.watch(albumProvider(widget.recordId)).valueOrNull;
    final isCover =
        persisted?.any(
          (item) => item.id == widget.photos[_index].id && item.isCover,
        ) ??
        false;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('${_index + 1} / ${widget.photos.length}'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _remove,
            tooltip: 'Убрать фото',
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: widget.photos.length,
                onPageChanged: (index) => setState(() => _index = index),
                itemBuilder: (context, index) =>
                    _FullPhoto(widget.photos[index].id),
              ),
            ),
            if (widget.photos.length > 1)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    tooltip: 'Предыдущее фото',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: _index == 0 ? null : () => _move(-1),
                  ),
                  IconButton(
                    tooltip: 'Следующее фото',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _index == widget.photos.length - 1
                        ? null
                        : () => _move(1),
                  ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OutlinedButton.icon(
                onPressed: _busy || isCover ? null : _chooseCover,
                icon: Icon(isCover ? Icons.check : Icons.photo_outlined),
                label: Text(isCover ? 'Обложка альбома' : 'Сделать обложкой'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _move(int step) {
    final duration = motion(context, 210);
    if (duration == Duration.zero) {
      _pages.jumpToPage(_index + step);
    } else {
      _pages.animateToPage(
        _index + step,
        duration: duration,
        curve: Curves.easeOut,
      );
    }
  }
}

class _FullPhoto extends ConsumerWidget {
  const _FullPhoto(this.id);
  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(_fullPhotoProvider(id))
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const _ImageUnavailable(),
        data: (bytes) => bytes == null
            ? const _ImageUnavailable()
            : InteractiveViewer(
                maxScale: 4,
                child: Center(
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    cacheWidth: 2400,
                    errorBuilder: (_, _, _) => const _ImageUnavailable(),
                  ),
                ),
              ),
      );
}

class _ImageUnavailable extends StatelessWidget {
  const _ImageUnavailable();

  @override
  Widget build(BuildContext context) =>
      const Center(child: Icon(Icons.image_outlined, color: muted));
}
