// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'design.dart';
import 'pages.dart';
import 'profile.dart';
import 'store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: TempusApp()));
}

final router = GoRouter(
  initialLocation: '/today',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (_, _, shell) => Scaffold(
        body: SafeArea(bottom: false, child: shell),
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (index) => shell.goBranch(index),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.wb_twilight_outlined),
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
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/today', builder: (_, _) => const TodayPage()),
          ],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: '/plan', builder: (_, _) => const PlanPage())],
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
  );
}
