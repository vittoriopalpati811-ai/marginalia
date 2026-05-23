import 'dart:async';

import 'package:animations/animations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:marginalia/generated/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/theme.dart';
import 'core/providers/locale_provider.dart';
import 'features/paywall/paywall_screen.dart';
import 'core/providers/onboarding_provider.dart';
import 'features/social/home_tab.dart';
import 'features/library/library_screen.dart';
import 'features/library/book_detail_screen.dart';
import 'features/reader/highlight_detail_screen.dart';
import 'features/search/search_screen.dart';
import 'features/social/social_screen.dart';
import 'features/social/jam_detail_screen.dart';
import 'features/social/jam_book_voting_screen.dart';
import 'features/social/jam_challenge_screen.dart';
import 'features/social/jam_poll_screen.dart';
import 'features/social/notifications_screen.dart';
import 'features/profile/user_profile_screen.dart';
import 'features/profile/my_profile_screen.dart';
import 'features/profile/edit_profile_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/onboarding/amazon_login_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/auth/auth_screen.dart';
import 'features/auth/reset_password_screen.dart';
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
  initialLocation: '/',
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
      path: '/jam/:id/voting',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (_, state) {
        final id = state.pathParameters['id'] ?? '';
        return _pushPage(JamBookVotingScreen(jamId: id), state);
      },
    ),
    GoRoute(
      path: '/jam/:id/challenges',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (_, state) {
        final id = state.pathParameters['id'] ?? '';
        return _pushPage(JamChallengeScreen(jamId: id), state);
      },
    ),
    GoRoute(
      path: '/jam/:id/polls',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (_, state) {
        final id = state.pathParameters['id'] ?? '';
        return _pushPage(JamPollScreen(jamId: id), state);
      },
    ),
    GoRoute(
      path: '/notifications',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (_, state) =>
          _pushPage(const NotificationsScreen(), state),
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
    GoRoute(
      path: '/reset-password',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (_, state) => _modalPage(const ResetPasswordScreen(), state),
    ),
    GoRoute(
      path: '/paywall',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (_, state) => _modalPage(const PaywallScreen(), state),
    ),
  ],
);

// ─── App ─────────────────────────────────────────────────────────────────────

class MarginaliaApp extends ConsumerStatefulWidget {
  const MarginaliaApp({super.key});

  @override
  ConsumerState<MarginaliaApp> createState() => _MarginaliaAppState();
}

class _MarginaliaAppState extends ConsumerState<MarginaliaApp> {
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    // Listen for passwordRecovery event (triggered when user opens the reset link).
    // When fired, navigate to the reset-password screen as soon as the router is ready.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          router.push('/reset-password');
        });
      }
      // TODO: register APNs device token when user signs in.
      // Requires a platform plugin to retrieve the token (e.g. firebase_messaging
      // without FirebaseApp, or flutter_apns_only). Once you have the token:
      //
      //   if (data.event == AuthChangeEvent.signedIn) {
      //     final token = await YourPushPlugin.getToken();
      //     if (token != null) {
      //       ref.read(supabaseServiceProvider).registerDeviceToken(token);
      //     }
      //   }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onboardingComplete = ref.watch(onboardingCompleteProvider);
    final locale = ref.watch(localeProvider);

    // Before onboarding is done, show a standalone MaterialApp with the
    // onboarding screen. Once the user completes it the provider flips to true
    // and Flutter rebuilds the router-based shell immediately.
    if (!onboardingComplete) {
      return MaterialApp(
        title: 'Marginalia',
        theme: buildMarginaliaTheme(),
        darkTheme: buildMarginaliaDarkTheme(),
        themeMode: ThemeMode.system,
        debugShowCheckedModeBanner: false,
        locale: locale,
        localizationsDelegates: _localizationsDelegates,
        supportedLocales: _supportedLocales,
        home: const OnboardingScreen(),
      );
    }

    return MaterialApp.router(
      title: 'Marginalia',
      theme: buildMarginaliaTheme(),
      darkTheme: buildMarginaliaDarkTheme(),
      themeMode: ThemeMode.system,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: _localizationsDelegates,
      supportedLocales: _supportedLocales,
    );
  }
}

// ─── Shell scaffold with flat nav ────────────────────────────────────────────

class _ScaffoldWithNav extends StatelessWidget {
  const _ScaffoldWithNav({
    required this.child,
    required this.routePath,
  });

  final Widget child;
  final String routePath;

  static const _tabs = [
    (path: '/home',     icon: Icons.home_outlined,         activeIcon: Icons.home_rounded,          label: 'Home'),
    (path: '/',         icon: Icons.auto_stories_outlined, activeIcon: Icons.auto_stories,          label: 'Libreria'),
    (path: '/search',   icon: Icons.search_outlined,       activeIcon: Icons.search_rounded,        label: 'Cerca'),
    (path: '/social',   icon: Icons.people_outline,        activeIcon: Icons.people_rounded,        label: 'Jam'),
    (path: '/messages', icon: Icons.send_outlined,         activeIcon: Icons.send_rounded,          label: 'Messaggi'),
    (path: '/profile',  icon: Icons.person_outline,        activeIcon: Icons.person_rounded,        label: 'Profilo'),
  ];

  @override
  Widget build(BuildContext context) {
    final selectedIndex =
        _tabs.indexWhere((t) => t.path == routePath).clamp(0, _tabs.length - 1);

    return Scaffold(
      extendBody: true,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: child,
        ),
        child: KeyedSubtree(
          key: ValueKey(routePath),
          child: child,
        ),
      ),
      bottomNavigationBar: _AirbnbNavBar(
        selectedIndex: selectedIndex,
        tabs: _tabs,
        onTap: (i) {
          HapticFeedback.lightImpact();
          context.go(_tabs[i].path);
        },
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

// ─── Airbnb-style flat nav bar ────────────────────────────────────────────────

typedef _Tab = ({String path, IconData icon, IconData activeIcon, String label});

class _AirbnbNavBar extends StatelessWidget {
  const _AirbnbNavBar({
    required this.selectedIndex,
    required this.tabs,
    required this.onTap,
  });

  final int selectedIndex;
  final List<_Tab> tabs;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: MarginaliaColors.surface,
        border: Border(
          top: BorderSide(color: MarginaliaColors.rule, width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: Row(
            children: List.generate(tabs.length, (i) {
              final active = i == selectedIndex;
              final tab = tabs[i];
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Icon with animated scale switch
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, anim) {
                          final scale = Tween<double>(begin: 0.82, end: 1.0)
                              .animate(CurvedAnimation(
                            parent: anim,
                            curve: Curves.easeOutCubic,
                          ));
                          return ScaleTransition(
                            scale: scale,
                            child: FadeTransition(opacity: anim, child: child),
                          );
                        },
                        child: Icon(
                          active ? tab.activeIcon : tab.icon,
                          key: ValueKey('${tab.path}_$active'),
                          size: 24,
                          color: active
                              ? MarginaliaColors.primary
                              : MarginaliaColors.inkFaint,
                        ),
                      ),
                      const SizedBox(height: 3),
                      // Label with animated color
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        style: GoogleFonts.manrope(
                          fontSize: 9,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w500,
                          letterSpacing: active ? 0.1 : 0.0,
                          color: active
                              ? MarginaliaColors.primary
                              : MarginaliaColors.inkFaint,
                        ),
                        child: Text(tab.label),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ─── Localization config ──────────────────────────────────────────────────────

const _localizationsDelegates = [
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  AppLocalizations.delegate,
];

const _supportedLocales = [
  Locale('it'),
  Locale('en'),
];
