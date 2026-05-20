import 'package:animations/animations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'core/providers/onboarding_provider.dart';
import 'features/social/home_tab.dart';
import 'features/library/library_screen.dart';
import 'features/library/book_detail_screen.dart';
import 'features/reader/highlight_detail_screen.dart';
import 'features/search/search_screen.dart';
import 'features/social/social_screen.dart';
import 'features/social/jam_detail_screen.dart';
import 'features/profile/user_profile_screen.dart';
import 'features/profile/my_profile_screen.dart';
import 'features/profile/edit_profile_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/onboarding/amazon_login_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/auth/auth_screen.dart';
import 'features/messages/messages_screen.dart';
import 'features/messages/chat_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

// ─── Transition helpers ───────────────────────────────────────────────────────

/// Push transition: shared axis horizontal (slide + fade, Material motion spec).
CustomTransitionPage<void> _pushPage(Widget child, GoRouterState state) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return SharedAxisTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        transitionType: SharedAxisTransitionType.horizontal,
        fillColor: MarginaliaColors.background,
        child: child,
      );
    },
  );
}

/// Modal transition: slide from bottom + fade (for auth, settings overlays).
CustomTransitionPage<void> _modalPage(Widget child, GoRouterState state) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 340),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final slide = Tween<Offset>(
        begin: const Offset(0.0, 0.06),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ));
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: SlideTransition(position: slide, child: child),
      );
    },
  );
}

// ─── Router ───────────────────────────────────────────────────────────────────

final router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/home',
  routes: [
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => _ScaffoldWithNav(
        routePath: state.uri.path,
        child: defaultTargetPlatform != TargetPlatform.iOS &&
                defaultTargetPlatform != TargetPlatform.android
            ? Column(
                children: [
                  const _DevStatusBar(),
                  Expanded(child: child),
                ],
              )
            : child,
      ),
      routes: [
        GoRoute(path: '/home',     builder: (_, __) => const HomeTab()),
        GoRoute(path: '/',         builder: (_, __) => const LibraryScreen()),
        GoRoute(path: '/search',   builder: (_, __) => const SearchScreen()),
        GoRoute(path: '/social',   builder: (_, __) => const SocialScreen()),
        GoRoute(path: '/messages', builder: (_, __) => const MessagesScreen()),
        GoRoute(path: '/profile',  builder: (_, __) => const MyProfileScreen()),
      ],
    ),

    // Chat screen (full-screen push)
    GoRoute(
      path: '/chat/:id',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (_, state) {
        final id   = state.pathParameters['id'] ?? '';
        final name = state.uri.queryParameters['name'] ?? 'Messaggio';
        return _pushPage(
            ChatScreen(conversationId: id, conversationName: name), state);
      },
    ),

    // Full-screen push routes — horizontal shared axis
    GoRoute(
      path: '/book/:id',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (_, state) {
        final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
        return _pushPage(BookDetailScreen(bookId: id), state);
      },
    ),
    GoRoute(
      path: '/highlight/:id',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (_, state) {
        final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
        return _pushPage(HighlightDetailScreen(highlightId: id), state);
      },
    ),
    GoRoute(
      path: '/jam/:id',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (_, state) {
        final id = state.pathParameters['id'] ?? '';
        final name = state.uri.queryParameters['name'] ?? 'Jam';
        return _pushPage(JamDetailScreen(jamId: id, jamName: name), state);
      },
    ),
    GoRoute(
      path: '/user/:id',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (_, state) {
        final id = state.pathParameters['id'] ?? '';
        return _pushPage(UserProfileScreen(userId: id), state);
      },
    ),
    GoRoute(
      path: '/account',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (_, state) => _modalPage(const SettingsScreen(), state),
    ),
    GoRoute(
      path: '/edit-profile',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (_, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return _pushPage(
          EditProfileScreen(
            initialProfile:  extra?['profile']  as Map<String, dynamic>?,
            initialGradient: extra?['gradient'] as String? ?? 'sepia',
            initialPattern:  extra?['pattern']  as String? ?? 'none',
            onSaved:         extra?['onSaved']  as VoidCallback? ?? () {},
          ),
          state,
        );
      },
    ),

    // Modal routes — fade + subtle slide up
    GoRoute(
      path: '/auth',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (_, state) => _modalPage(const AuthScreen(), state),
    ),
    GoRoute(
      path: '/sync/kindle',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (_, state) => _modalPage(const AmazonLoginScreen(), state),
    ),
  ],
);

// ─── App ─────────────────────────────────────────────────────────────────────

class MarginaliaApp extends ConsumerWidget {
  const MarginaliaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboardingComplete = ref.watch(onboardingCompleteProvider);

    // Before onboarding is done, show a standalone MaterialApp with the
    // onboarding screen. Once the user completes it the provider flips to true
    // and Flutter rebuilds the router-based shell immediately.
    if (!onboardingComplete) {
      return MaterialApp(
        title: 'Marginalia',
        theme: buildMarginaliaTheme(),
        debugShowCheckedModeBanner: false,
        home: const OnboardingScreen(),
      );
    }

    return MaterialApp.router(
      title: 'Marginalia',
      theme: buildMarginaliaTheme(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

// ─── Shell scaffold with floating nav ────────────────────────────────────────

class _ScaffoldWithNav extends StatefulWidget {
  const _ScaffoldWithNav({
    required this.child,
    required this.routePath,
  });

  final Widget child;
  final String routePath;

  @override
  State<_ScaffoldWithNav> createState() => _ScaffoldWithNavState();
}

class _ScaffoldWithNavState extends State<_ScaffoldWithNav>
    with SingleTickerProviderStateMixin {

  static const _tabs = [
    (path: '/home',     icon: Icons.home_outlined,         activeIcon: Icons.home_rounded,          label: ''),
    (path: '/',         icon: Icons.auto_stories_outlined, activeIcon: Icons.auto_stories,          label: ''),
    (path: '/search',   icon: Icons.search_outlined,       activeIcon: Icons.search_rounded,        label: ''),
    (path: '/social',   icon: Icons.people_outline,        activeIcon: Icons.people_rounded,        label: ''),
    (path: '/messages', icon: Icons.send_outlined,         activeIcon: Icons.send_rounded,          label: ''),
    (path: '/profile',  icon: Icons.person_outline,        activeIcon: Icons.person_rounded,        label: ''),
  ];

  late final AnimationController _navCtrl;
  late final Animation<Offset> _navSlide;
  bool _navVisible = true;

  @override
  void initState() {
    super.initState();
    _navCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _navSlide = _navCtrl.drive(
      Tween(begin: Offset.zero, end: const Offset(0, 2.5))
          .chain(CurveTween(curve: Curves.easeInOutCubic)),
    );
  }

  @override
  void didUpdateWidget(_ScaffoldWithNav old) {
    super.didUpdateWidget(old);
    // Always show nav when switching tabs
    if (old.routePath != widget.routePath) _showNav();
  }

  @override
  void dispose() {
    _navCtrl.dispose();
    super.dispose();
  }

  void _showNav() {
    if (!_navVisible) {
      _navVisible = true;
      _navCtrl.reverse();
    }
  }

  void _hideNav() {
    if (_navVisible) {
      _navVisible = false;
      _navCtrl.forward();
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      final pixels = notification.metrics.pixels;
      // Always reveal at the very top
      if (pixels <= 0) {
        _showNav();
        return false;
      }
      if (delta > 5)       _hideNav();
      else if (delta < -5) _showNav();
    } else if (notification is ScrollEndNotification) {
      // Snap: reveal if close to top after fling
      if (notification.metrics.pixels <= 60) _showNav();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex =
        _tabs.indexWhere((t) => t.path == widget.routePath).clamp(0, _tabs.length - 1);

    return Scaffold(
      extendBody: true,
      // Tab transitions: fade between screens
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: child,
          ),
          child: KeyedSubtree(
            key: ValueKey(widget.routePath),
            child: widget.child,
          ),
        ),
      ),
      bottomNavigationBar: SlideTransition(
        position: _navSlide,
        child: _FloatingNavBar(
          selectedIndex: selectedIndex,
          tabs: _tabs,
          onTap: (i) {
            HapticFeedback.lightImpact();
            context.go(_tabs[i].path);
          },
        ),
      ),
    );
  }
}

// ─── Dev status bar (shows on Windows/web to simulate iOS status bar) ─────────

class _DevStatusBar extends StatelessWidget {
  const _DevStatusBar();

  @override
  Widget build(BuildContext context) {
    final now = TimeOfDay.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    return Container(
      height: 44,
      color: MarginaliaColors.background,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Text(
            '$h:$m',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: MarginaliaColors.ink,
              letterSpacing: -0.3,
            ),
          ),
          const Spacer(),
          const Icon(Icons.signal_cellular_alt, size: 14, color: MarginaliaColors.inkMuted),
          const SizedBox(width: 4),
          const Icon(Icons.wifi, size: 14, color: MarginaliaColors.inkMuted),
          const SizedBox(width: 4),
          const Icon(Icons.battery_full, size: 14, color: MarginaliaColors.inkMuted),
        ],
      ),
    );
  }
}

// ─── Floating pill nav bar ────────────────────────────────────────────────────

typedef _Tab = ({String path, IconData icon, IconData activeIcon, String label});

class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({
    required this.selectedIndex,
    required this.tabs,
    required this.onTap,
  });

  final int selectedIndex;
  final List<_Tab> tabs;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 16),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: MarginaliaColors.primary,
          borderRadius: BorderRadius.circular(32),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40261E1D),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
            BoxShadow(
              color: Color(0x18261E1D),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            final tabWidth = constraints.maxWidth / tabs.length;

            return Stack(
              alignment: Alignment.centerLeft,
              children: [
                // ── Pill indicatore animato ──────────────────────────────
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeInOutCubic,
                  left: tabWidth * selectedIndex + 8,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeInOutCubic,
                    width: tabWidth - 16,
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1EEE7).withAlpha(36),
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),

                // ── Tab items ────────────────────────────────────────────
                Row(
                  children: List.generate(tabs.length, (i) {
                    final active = i == selectedIndex;
                    final tab = tabs[i];
                    return Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onTap(i),
                        child: SizedBox(
                          height: 64,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                transitionBuilder: (child, anim) =>
                                    ScaleTransition(scale: anim, child: child),
                                child: Icon(
                                  active ? tab.activeIcon : tab.icon,
                                  key: ValueKey(active),
                                  size: active ? 26 : 24,
                                  color: active
                                      ? const Color(0xFFF1EEE7)
                                      : const Color(0xFFF1EEE7).withAlpha(100),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
