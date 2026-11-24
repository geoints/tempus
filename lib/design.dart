import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import 'records.dart';

const ink = Color(0xff15110f);
const panel = Color(0xff221b16);
const border = Color(0xff49372a);
const paper = Color(0xfff4e9d8);
const muted = Color(0xffbaad9d);
const bronze = Color(0xffddb780);
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
    splashFactory: InkRipple.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: ink,
      surfaceTintColor: Colors.transparent,
    ),
    cardColor: panel,
    colorScheme: scheme,
    scaffoldBackgroundColor: ink,
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xff1c1511),
      surfaceTintColor: Colors.transparent,
      indicatorColor: const Color(0xff493322),
      height: 65,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          color: states.contains(WidgetState.selected) ? paper : muted,
        ),
      ),
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

const palacePhoto = 'assets/tempus-palace.jpg';

Duration motion(BuildContext context, int milliseconds) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

IconData areaIcon(String area) => switch (area) {
  'Отношения' => Icons.favorite_border_rounded,
  'Тренировки' => Icons.fitness_center_rounded,
  'Развитие' => Icons.auto_awesome_outlined,
  'Культурное развитие' => Icons.account_balance_outlined,
  'Чтение' => Icons.menu_book_outlined,
  'Английский' => Icons.translate_rounded,
  'Работа' => Icons.work_outline_rounded,
  _ => Icons.person_outline_rounded,
};

class AnimatedValue extends StatelessWidget {
  const AnimatedValue(this.value, {this.style, super.key});
  final String value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: motion(context, 230),
    layoutBuilder: (current, previous) => Stack(
      alignment: Alignment.center,
      children: [
        ...previous.map((child) => ExcludeSemantics(child: child)),
        ?current,
      ],
    ),
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween(begin: .93, end: 1.0).animate(animation),
        child: child,
      ),
    ),
    child: Text(value, key: ValueKey(value), style: style),
  );
}

class PalaceCard extends StatelessWidget {
  const PalaceCard({super.key});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(22),
    child: Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            palacePhoto,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
        ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, .5, 1],
                colors: [
                  Color(0x09000000),
                  Color(0x1b120a06),
                  Color(0xde120b07),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 122, 14, 14),
          child: TweenAnimationBuilder<double>(
            duration: motion(context, 540),
            tween: Tween(begin: 0, end: 1),
            curve: Curves.easeOutCubic,
            builder: (_, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 12 * (1 - value)),
                child: child,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    color: const Color(0x71321e11),
                    border: Border.all(color: const Color(0x50edc294)),
                  ),
                  child: const Column(
                    children: [
                      Text(
                        'Disciplina est libertas',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'TempusSerif',
                          fontSize: 21,
                          color: paper,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Дисциплина — это свобода',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: paper),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xff644a36)),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class TempusSeal extends StatelessWidget {
  const TempusSeal(this.progress, {super.key});
  final double progress;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _SealPainter(progress),
    size: const Size.square(104),
  );
}

class _SealPainter extends CustomPainter {
  const _SealPainter(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width * .42;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final ring = Rect.fromCircle(center: center, radius: radius);
    paint
      ..color = const Color(0xff5a3c28)
      ..strokeWidth = 1;
    canvas.drawCircle(center, radius, paint);
    canvas.drawCircle(center, radius * .78, paint);
    paint
      ..color = bronze
      ..strokeWidth = 1.4;
    canvas.drawArc(ring, -math.pi / 2, math.pi * 2 * progress, false, paint);
    for (var tick = 0; tick < 48; tick++) {
      final angle = tick * math.pi / 24 - math.pi / 2;
      final direction = Offset(math.cos(angle), math.sin(angle));
      paint.color = tick % 4 == 0 ? bronze : border;
      canvas.drawLine(
        center + direction * radius * .83,
        center + direction * radius * (tick % 4 == 0 ? .94 : .89),
        paint,
      );
    }
    paint
      ..color = bronze
      ..strokeWidth = 1.6;
    final angle = -math.pi / 2 + progress * math.pi * 2;
    canvas.drawLine(
      center,
      center + Offset(math.cos(angle), math.sin(angle)) * radius * .61,
      paint,
    );
    canvas.drawLine(
      center,
      center + Offset(-radius * .34, radius * .18),
      paint,
    );
    canvas.drawCircle(center, 2.6, paint);
  }

  @override
  bool shouldRepaint(_SealPainter oldDelegate) =>
      oldDelegate.progress != progress;
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
