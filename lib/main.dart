import 'dart:async';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'design.dart';
import 'pages.dart';
import 'profile.dart';
import 'schedule.dart';
import 'store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: TempusApp()));
}

final router = GoRouter(
  initialLocation: '/today',
  routes: [
    StatefulShellRoute(
      navigatorContainerBuilder: (_, shell, children) =>
          _TabDeck(shell.currentIndex, children),
      builder: (_, _, shell) => Scaffold(
        body: SafeArea(bottom: false, child: shell),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: border)),
          ),
          child: NavigationBar(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: (index) {
              if (index != shell.currentIndex) HapticFeedback.selectionClick();
              shell.goBranch(index);
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Сегодня',
              ),
              NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined),
                label: 'План',
              ),
              NavigationDestination(
                icon: Icon(Icons.query_stats_outlined),
                label: 'Прогресс',
              ),
              NavigationDestination(
                icon: Icon(Icons.auto_stories_outlined),
                label: 'Летопись',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                label: 'Профиль',
              ),
            ],
          ),
        ),
      ),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/today', builder: (_, _) => const TodayPage()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/plan',
              builder: (_, _) => const PlanPage(),
              routes: [
                GoRoute(
                  path: 'schedule',
                  builder: (_, state) => SchedulePage(
                    key: ValueKey(state.uri.queryParameters['date']),
                    initialDate: DateTime.tryParse(
                      state.uri.queryParameters['date'] ?? '',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/progress', builder: (_, _) => const ProgressPage()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/archive', builder: (_, _) => const ArchivePage()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/profile', builder: (_, _) => const ProfilePage()),
          ],
        ),
      ],
    ),
  ],
);

class TempusApp extends ConsumerStatefulWidget {
  const TempusApp({super.key});

  @override
  ConsumerState<TempusApp> createState() => _TempusAppState();
}

class _TempusAppState extends ConsumerState<TempusApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        ref.read(recordsProvider.notifier).refreshReminders();
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'TEMPUS',
    debugShowCheckedModeBanner: false,
    theme: tempusTheme(),
    locale: const Locale('ru'),
    supportedLocales: const [Locale('ru')],
    // ignore: deprecated_member_use
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    routerConfig: router,
    builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: _Startup(child: child ?? const SizedBox.shrink()),
    ),
  );
}

class _TabDeck extends StatefulWidget {
  const _TabDeck(this.selected, this.tabs);

  final int selected;
  final List<Widget> tabs;

  @override
  State<_TabDeck> createState() => _TabDeckState();
}

class _TabDeckState extends State<_TabDeck>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 225),
    value: 1,
  );
  late final _curve = CurvedAnimation(
    parent: _motion,
    curve: Curves.easeOutCubic,
  );

  @override
  void didUpdateWidget(covariant _TabDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected == oldWidget.selected) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.value = 1;
    } else {
      _motion.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      for (var i = 0; i < widget.tabs.length; i++)
        Offstage(
          offstage: i != widget.selected,
          child: TickerMode(
            enabled: i == widget.selected,
            child: FadeTransition(
              opacity: _curve.drive(Tween(begin: .55, end: 1)),
              child: SlideTransition(
                position: _curve.drive(
                  Tween(begin: const Offset(0, .019), end: Offset.zero),
                ),
                child: widget.tabs[i],
              ),
            ),
          ),
        ),
    ],
  );
}

class _Startup extends ConsumerStatefulWidget {
  const _Startup({required this.child});
  final Widget child;

  @override
  ConsumerState<_Startup> createState() => _StartupState();
}

class _StartupState extends ConsumerState<_Startup> {
  Timer? _timer;
  bool _elapsed = false;
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(
      const Duration(milliseconds: 1620),
      () => setState(() => _elapsed = true),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(
      recordsProvider.select((state) => state.isLoading),
    );
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (!_revealed && !loading && (_elapsed || reduceMotion)) _revealed = true;
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(excluding: !_revealed, child: widget.child),
        IgnorePointer(
          ignoring: _revealed,
          child: AnimatedSwitcher(
            duration: motion(context, 385),
            reverseDuration: motion(context, 385),
            child: _revealed ? const SizedBox.shrink() : const _StartupSeal(),
          ),
        ),
      ],
    );
  }
}

class _StartupSeal extends StatelessWidget {
  const _StartupSeal();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: ink,
    child: Center(
      child: TweenAnimationBuilder<double>(
        duration: motion(context, 1720),
        tween: Tween(begin: 0, end: 1),
        curve: Curves.easeInOutSine,
        builder: (_, value, child) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TempusSeal(value),
            const SizedBox(height: 16),
            Opacity(opacity: (.15 + value).clamp(0, 1), child: child),
          ],
        ),
        child: const Text(
          'TEMPUS',
          style: TextStyle(
            color: paper,
            fontFamily: 'TempusSerif',
            fontSize: 29,
            letterSpacing: 7,
          ),
        ),
      ),
    ),
  );
}
