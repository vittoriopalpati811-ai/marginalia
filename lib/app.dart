import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'features/library/library_screen.dart';
import 'features/library/book_detail_screen.dart';
import 'features/reader/highlight_detail_screen.dart';
import 'features/search/search_screen.dart';
import 'features/social/social_screen.dart';
import 'features/social/jam_detail_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/onboarding/amazon_login_screen.dart';
import 'features/auth/auth_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  routes: [
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => _ScaffoldWithNav(child: child),
      routes: [
        GoRoute(path: '/', builder: (_, __) => const LibraryScreen()),
        GoRoute(path: '/search', builder: (_, __) => const SearchScreen()),
        GoRoute(path: '/social', builder: (_, __) => const SocialScreen()),
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      ],
    ),

    // Full-screen routes
    GoRoute(
      path: '/book/:id',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, state) {
        final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
        return BookDetailScreen(bookId: id);
      },
    ),
    GoRoute(
      path: '/highlight/:id',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, state) {
        final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
        return HighlightDetailScreen(highlightId: id);
      },
    ),
    GoRoute(
      path: '/jam/:id',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, state) {
        final id = state.pathParameters['id'] ?? '';
        final name = state.uri.queryParameters['name'] ?? 'Jam';
        return JamDetailScreen(jamId: id, jamName: name);
      },
    ),
    GoRoute(
      path: '/auth',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, __) => const AuthScreen(),
    ),
    GoRoute(
      path: '/sync/kindle',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, __) => const AmazonLoginScreen(),
    ),
  ],
);

class MarginaliaApp extends StatelessWidget {
  const MarginaliaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Marginalia',
      theme: buildMarginaliaTheme(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

// ─── Shell scaffold with bottom nav ──────────────────────────────────────────

class _ScaffoldWithNav extends StatelessWidget {
  const _ScaffoldWithNav({required this.child});

  final Widget child;

  static const _tabs = [
    (path: '/', icon: Icons.library_books_outlined, label: 'Libreria'),
    (path: '/search', icon: Icons.search, label: 'Cerca'),
    (path: '/social', icon: Icons.group_outlined, label: 'Jam'),
    (path: '/settings', icon: Icons.settings_outlined, label: 'Impostazioni'),
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final selectedIndex =
        _tabs.indexWhere((t) => t.path == location).clamp(0, _tabs.length - 1);

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: MarginaliaColors.surface,
          border: const Border(
            top: BorderSide(color: MarginaliaColors.ruleFaint, width: 1),
          ),
        ),
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: (i) => context.go(_tabs[i].path),
          destinations: _tabs
              .map((t) => NavigationDestination(icon: Icon(t.icon), label: t.label))
              .toList(),
        ),
      ),
    );
  }
}
