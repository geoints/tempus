import 'dart:math' as math;

// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import 'records.dart';

const ink = Color(0xff171513);
const panel = Color(0xff211d19);
const border = Color(0xff3a3128);
const paper = Color(0xfff4e9d8);
const muted = Color(0xffbaad9d);
const bronze = Color(0xffdcad72);
const sage = Color(0xffa9ba92);

ThemeData tempusTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: bronze,
        brightness: Brightness.dark,
      ).copyWith(
        surface: panel,
        onSurface: paper,
        onSurfaceVariant: muted,
        primary: bronze,
        onPrimary: ink,
        secondary: sage,
        outline: border,
      );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: ink,
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: panel,
      indicatorColor: Color(0xff453323),
      height: 67,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ink,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)),
    ),
    dividerTheme: const DividerThemeData(color: border, space: 1),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

IconData kindIcon(Kind kind) => switch (kind) {
  Kind.task => Icons.checklist_rounded,
  Kind.habit => Icons.repeat_rounded,
  Kind.goal => Icons.flag_outlined,
  Kind.journal => Icons.edit_note_rounded,
  Kind.event => Icons.event_outlined,
  Kind.book => Icons.menu_book_outlined,
  Kind.theatre => Icons.theater_comedy_outlined,
  Kind.craft => Icons.handyman_outlined,
  Kind.achievement => Icons.emoji_events_outlined,
  Kind.recovery => Icons.spa_outlined,
  Kind.income => Icons.south_west_rounded,
  Kind.expense => Icons.north_east_rounded,
};

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, {this.subtitle, this.action, super.key});
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subtitle != null) ...[
              Text(
                subtitle!,
                style: const TextStyle(
                  color: bronze,
                  fontSize: 12,
                  letterSpacing: 1.3,
                ),
              ),
              const SizedBox(height: 7),
            ],
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'TempusSerif',
                fontSize: 32,
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
      ?action,
    ],
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {this.action, super.key});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontFamily: 'TempusSerif', fontSize: 21),
        ),
      ),
      ?action,
    ],
  );
}

class Surface extends StatelessWidget {
  const Surface({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Material(
    color: panel,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: border),
      borderRadius: BorderRadius.circular(16),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class PageList extends StatelessWidget {
  const PageList({required this.children, super.key});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.fromLTRB(20, 25, 20, 28),
    itemBuilder: (_, index) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 660),
        child: SizedBox(width: double.infinity, child: children[index]),
      ),
    ),
    separatorBuilder: (_, _) => const SizedBox(height: 15),
    itemCount: children.length,
  );
}

class EmptyCard extends StatelessWidget {
  const EmptyCard(this.message, {this.icon = Icons.inbox_outlined, super.key});
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Surface(
    child: Row(
      children: [
        Icon(icon, color: bronze, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(message, style: const TextStyle(color: muted)),
        ),
      ],
    ),
  );
}

class Chronograph extends StatelessWidget {
  const Chronograph({super.key});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xff281d16), Color(0xff4d3525)],
      ),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xff654936)),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _DialPainter())),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 25, 88, 25),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TEMPUS',
                  style: TextStyle(
                    color: bronze,
                    letterSpacing: 4,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Disciplina\nest libertas',
                  style: TextStyle(
                    fontFamily: 'TempusSerif',
                    fontSize: MediaQuery.sizeOf(context).width < 360 ? 25 : 31,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Дисциплина — это свобода',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _DialPainter extends CustomPainter {
  const _DialPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width - 16, size.height * .48);
    final radius = math.min(115.0, size.height * .63);
    final line = Paint()
      ..color = const Color(0xffa67a51)
      ..style = PaintingStyle.stroke;
    for (final ring in [.46, .74, .90, .96, 1.0]) {
      line.strokeWidth = ring == 1 ? 1.2 : .6;
      canvas.drawCircle(center, ring * radius, line);
    }
    for (var tick = 0; tick < 60; tick++) {
      final angle = tick * math.pi / 30;
      final point = Offset(math.cos(angle), math.sin(angle));
      line.strokeWidth = tick % 5 == 0 ? 1.3 : .55;
      canvas.drawLine(
        center + point * radius * (tick % 5 == 0 ? .78 : .84),
        center + point * radius * .89,
        line,
      );
    }
    line.strokeWidth = 2;
    canvas.drawLine(
      center,
      center + Offset(-radius * .43, -radius * .50),
      line,
    );
    canvas.drawLine(center, center + Offset(radius * .18, -radius * .72), line);
    canvas.drawCircle(center, 4, line);
  }

  @override
  bool shouldRepaint(_DialPainter oldDelegate) => false;
}

class ProgressTrack extends StatelessWidget {
  const ProgressTrack(this.ratio, {super.key});
  final double ratio;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: ratio.clamp(0, 1).toDouble()),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 330),
    curve: Curves.easeOutCubic,
    builder: (_, value, _) => LinearProgressIndicator(
      value: value,
      minHeight: 6,
      borderRadius: BorderRadius.circular(8),
      backgroundColor: border,
      color: bronze,
    ),
  );
}
