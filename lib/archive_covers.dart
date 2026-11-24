// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'design.dart';
import 'editor.dart';
import 'records.dart';
import 'store.dart';

class ArchiveMonth extends StatelessWidget {
  const ArchiveMonth(this.month, this.records, {super.key});

  final DateTime month;
  final List<Record> records;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: bronze,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(child: SectionTitle(monthTitle(month))),
        ],
      ),
      Container(
        margin: const EdgeInsets.only(left: 3.5, top: 8),
        padding: const EdgeInsets.only(left: 15, bottom: 5),
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: border)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const gap = 8.0;
            final largeText = MediaQuery.textScalerOf(context).scale(13) > 17;
            final columns = largeText || constraints.maxWidth < 290 ? 2 : 3;
            final width =
                (constraints.maxWidth - (columns - 1) * gap) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final row in records)
                  SizedBox(
                    width: width,
                    child: _CoverTile(row: row, key: ValueKey(row.id)),
                  ),
              ],
            );
          },
        ),
      ),
    ],
  );
}

class _CoverTile extends ConsumerWidget {
  const _CoverTile({required this.row, super.key});
  final Record row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = row.hasPhoto
        ? ref.watch(archiveCoverProvider(row.id)).valueOrNull
        : null;
    final placeholder = DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff543d2a), Color(0xff241b14)],
        ),
      ),
      child: Center(child: Icon(kindIcon(row.kind), color: bronze, size: 27)),
    );
    return Surface(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: () =>
            editRecord(context, record: row, kinds: [row.kind], date: row.date),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.16,
              child: AnimatedSwitcher(
                duration: motion(context, 240),
                layoutBuilder: (current, previous) => Stack(
                  fit: StackFit.expand,
                  children: [...previous, ?current],
                ),
                child: image == null
                    ? placeholder
                    : Image.memory(
                        image,
                        key: ObjectKey(image),
                        fit: BoxFit.cover,
                        cacheWidth: 360,
                        errorBuilder: (_, _, _) => placeholder,
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    row.kind.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: bronze, fontSize: 10),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    shortDate(row.date),
                    style: const TextStyle(color: muted, fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
