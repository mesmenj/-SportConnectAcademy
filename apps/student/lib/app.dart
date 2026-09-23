import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/theme/app_theme.dart';
import 'core/localization/app_language.dart';
import 'core/navigation/app_access_controller.dart';
import 'data/firebase_profile_repository.dart';
import 'features/auth/onboarding_screen.dart';
import 'features/home/home_screen.dart';
import 'features/booking/booking_screen.dart';
import 'features/calendar/calendar_screen.dart';
import 'features/tournaments/tournaments_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/coach/coach_home_screen.dart';

final _root = GlobalKey<NavigatorState>();
final _shell = GlobalKey<NavigatorState>();

final router = GoRouter(
  navigatorKey: _root,
  initialLocation: '/welcome',
  redirect: (context, state) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (AppAccessController.guestAccessGranted) {
        return state.matchedLocation == '/coach' ? '/welcome' : null;
      }
      return state.matchedLocation == '/welcome' ? null : '/welcome';
    }
    final profile = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final active = profile.data()?['status'] == 'active';
    final role = profile.data()?['role']?.toString();
    final isCoach = role == 'coach' && active;
    final isParentOrStudent = ['parent', 'student'].contains(role) && active;
    if (isCoach && state.matchedLocation != '/coach') return '/coach';
    if (!isCoach && state.matchedLocation == '/coach') return '/welcome';
    if (isParentOrStudent && state.matchedLocation == '/welcome') {
      return '/home';
    }
    return null;
  },
  routes: [
    GoRoute(path: '/welcome', builder: (_, __) => const OnboardingScreen()),
    GoRoute(path: '/coach', builder: (_, __) => const CoachHomeScreen()),
    StatefulShellRoute.indexedStack(
      builder: (_, __, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(
          navigatorKey: _shell,
          routes: [
            GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/booking',
              builder: (_, __) => const BookingScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/calendar',
              builder: (_, __) => const CalendarScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/tournaments',
              builder: (_, __) => const TournamentsScreen(),
            ),
          ],
        ),
        // Branche conservée sans écran dans l’index historique afin que les
        // anciennes sessions/hot reloads ne décalent jamais l’onglet Profil.
        StatefulShellBranch(
          routes: [GoRoute(path: '/messages', redirect: (_, __) => '/profile')],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/profile',
              builder: (_, __) => const ProfileScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);

class SportAApp extends StatefulWidget {
  const SportAApp({super.key});

  @override
  State<SportAApp> createState() => _SportAAppState();
}

class _SportAAppState extends State<SportAApp>
    with WidgetsBindingObserver {
  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      router.refresh();
      if (user != null) {
        unawaited(
          FirebaseProfileRepository().updatePreferredLanguage().catchError(
            (_) {},
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    AppLanguageController.refreshFromSystem();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLanguage>(
    valueListenable: AppLanguageController.language,
    builder: (_, language, __) => MaterialApp.router(
      title: 'SportA',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: language == AppLanguage.english
          ? const Locale('en')
          : const Locale('fr'),
      supportedLocales: const [Locale('en'), Locale('fr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: router,
    ),
  );
}

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: shell,
    bottomNavigationBar: SafeArea(
      top: false,
      child: NavigationBar(
        selectedIndex: shell.currentIndex <= 3 ? shell.currentIndex : 4,
        onDestinationSelected: (i) {
          final branchIndex = i == 4 ? 5 : i;
          shell.goBranch(
            branchIndex,
            initialLocation: branchIndex == shell.currentIndex,
          );
        },
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: tr('Accueil'),
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle),
            label: tr('Réserver'),
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: tr('Calendrier'),
          ),
          NavigationDestination(
            icon: Icon(Icons.emoji_events_outlined),
            selectedIcon: Icon(Icons.emoji_events),
            label: tr('Tournois'),
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: tr('Profil'),
          ),
        ],
      ),
    ),
  );
}
