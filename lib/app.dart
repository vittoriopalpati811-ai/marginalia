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
import 'features/stats/stats_screen.dart';
import 'features/onboarding/amazon_login_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/auth/auth_screen.dart';
import 'features/auth/reset_password_screen.dart';
import 'features/messages/messages_screen.dart';
import 'features/messages/chat_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

// ─── Transition helpers ───────────────────────────────────────────────────────

/// Push transition: cinematic horizontal shared axis with deep easeOutQuart.
/// Background fillColor matches the scaffold to avoid the white-flash that
/// occurs when Material's default fill leaks through during the transition.
/// Airbnb-style: motion settles into rest rather than bouncing.
CustomTransitionPage<void> _pushPage(Widget child, GoRouterState state) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      // Wrap the Material curves to deepen them
      final eased = CurvedAnimation(
          parent: animation, curve: Curves.easeOutQuart);
      final easedSecondary = CurvedAnimation(
          parent: secondaryAnimation, curve: Curves.easeOutQuart);
      return SharedAxisTransition(
        animation: eased,
        secondaryAnimation: easedSecondary,
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
        GoRoute(path: '/social',   builder: (_, __) => const SocialScreen()),
        GoRoute(path: '/messages', builder: (_, __) => const MessagesScreen()),
        GoRoute(path: '/profile',  builder: (_, __) => const MyProfileScreen()),
      ],
    ),

    // Search — full-screen push (no nav bar; accessed from Jam header)
    GoRoute(
      path: '/search',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (_, state) => _pushPage(const SearchScreen(), state),
    ),

    // Chat screen (full-screen push)
    GoRoute(
      path: '/chat/:id',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (_, state) {
        final id   = state.pathParameters['id'] ?? '';
        final name = state.uri.queryParameters['name'] ?? 'Message';
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
      path: '/stats',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (_, state) => _pushPage(const StatsScreen(), state),
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
    (path: '/home',     icon: Icons.home_outlined,         activeIcon: Icons.home_rounded,     label: 'Home'),
    (path: '/',         icon: Icons.auto_stories_outlined, activeIcon: Icons.auto_stories,     label: 'Library'),
    (path: '/social',   icon: Icons.people_outline,        activeIcon: Icons.people_rounded,   label: 'Jam'),
    (path: '/messages', icon: Icons.send_outlined,         activeIcon: Icons.send_rounded,     label: 'Messages'),
    (path: '/profile',  icon: Icons.person_outline,        activeIcon: Icons.person_rounded,   label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final selectedIndex =
        _tabs.indexWhere((t) => t.path == routePath).clamp(0, _tabs.length - 1);

    return Scaffold(
      // Airbnb-clean: bottom nav is now a solid bar with a top hairline,
      // not a floating pill — content does NOT extend behind it.
      extendBody: false,
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
      bottomNavigationBar: _LiquidGlassNavBar(
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

// ─── Liquid glass nav bar ─────────────────────────────────────────────────────

typedef _Tab = ({String path, IconData icon, IconData activeIcon, String label});

class _LiquidGlassNavBar extends StatefulWidget {
  const _LiquidGlassNavBar({
    required this.selectedIndex,
    required this.tabs,
    required this.onTap,
  });

  final int selectedIndex;
  final List<_Tab> tabs;
  final ValueChanged<int> onTap;

  @override
  State<_LiquidGlassNavBar> createState() => _LiquidGlassNavBarState();
}

class _LiquidGlassNavBarState extends State<_LiquidGlassNavBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounceCtrl;
  late final Animation<double> _bounceAnim;

  @override
  void initState() {
    super.initState();
    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    // Quick compress → overshoot → settle
    _bounceAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.94)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 18,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.94, end: 1.03)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 32,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.03, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 50,
      ),
    ]).animate(_bounceCtrl);
  }

  @override
  void didUpdateWidget(_LiquidGlassNavBar old) {
    super.didUpdateWidget(old);
    if (old.selectedIndex != widget.selectedIndex) {
      _bounceCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _bounceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottom = MediaQuery.of(context).padding.bottom;

    // ── Airbnb-clean bottom nav ─────────────────────────────────────────
    // Flat surface with a single hairline divider at the top, 5 evenly-
    // spaced tab items below. No glass, no pill, no border ornamentation.
    // Active state: filled icon + primary color + bold label. Inactive:
    // outline icon + muted color + medium label.
    final activeColor   = isDark ? Colors.white : MarginaliaColors.ink;
    final inactiveColor = isDark
        ? const Color(0xFF8E8E93)
        : MarginaliaColors.inkMuted;
    final surfaceColor  = isDark
        ? const Color(0xFF1B1F1B)
        : Colors.white;
    final ruleColor     = isDark
        ? Colors.white.withAlpha(20)
        : MarginaliaColors.ruleFaint;

    return AnimatedBuilder(
      animation: _bounceAnim,
      builder: (context, child) => Transform.scale(
        scale: _bounceAnim.value,
        alignment: Alignment.bottomCenter,
        child: child,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: surfaceColor,
          border: Border(top: BorderSide(color: ruleColor, width: 0.5)),
        ),
        padding: EdgeInsets.only(top: 6, bottom: bottom + 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(widget.tabs.length, (i) {
            final active = i == widget.selectedIndex;
            final tab    = widget.tabs[i];
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onTap(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, anim) => ScaleTransition(
                          scale: Tween<double>(begin: 0.82, end: 1.0).animate(
                              CurvedAnimation(
                                  parent: anim, curve: Curves.easeOutCubic)),
                          child: FadeTransition(opacity: anim, child: child),
                        ),
                        child: Icon(
                          active ? tab.activeIcon : tab.icon,
                          key: ValueKey('${tab.path}_$active'),
                          size: 24,
                          color: active ? activeColor : inactiveColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        style: GoogleFonts.manrope(
                          fontSize: 10.5,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: active ? activeColor : inactiveColor,
                          letterSpacing: 0,
                        ),
                        child: Text(tab.label),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// Old _GlassBorderPainter removed as part of the Airbnb-clean nav redesign.

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
