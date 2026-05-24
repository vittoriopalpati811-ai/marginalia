import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

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
    (path: '/home',     icon: Icons.home_outlined,         activeIcon: Icons.home_rounded,     label: 'Home'),
    (path: '/',         icon: Icons.auto_stories_outlined, activeIcon: Icons.auto_stories,     label: 'Libreria'),
    (path: '/social',   icon: Icons.people_outline,        activeIcon: Icons.people_rounded,   label: 'Jam'),
    (path: '/messages', icon: Icons.send_outlined,         activeIcon: Icons.send_rounded,     label: 'Messaggi'),
    (path: '/profile',  icon: Icons.person_outline,        activeIcon: Icons.person_rounded,   label: 'Profilo'),
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

    final glassColor = isDark
        ? const Color(0xFF18181A).withAlpha(205)
        : Colors.white.withAlpha(195);
    final activeColor = MarginaliaColors.primary;
    final inactiveColor = isDark
        ? const Color(0xFF8E8E93)
        : MarginaliaColors.inkFaint;
    final indicatorColor = isDark
        ? Colors.white.withAlpha(24)
        : MarginaliaColors.primaryFaint;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 14),
      child: AnimatedBuilder(
        animation: _bounceAnim,
        builder: (context, child) => Transform.scale(
          scale: _bounceAnim.value,
          alignment: Alignment.bottomCenter,
          child: child,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(38),
          child: LayoutBuilder(
            builder: (context, pillConstraints) {
              // iOS 26-style liquid glass: zoom the content behind the pill
              // (12% magnification centred on the pill), then blur.
              const s  = 1.12;
              final cx = pillConstraints.maxWidth  / 2;
              const cy = 33.0; // half of fixed pill height 66
              final matrix = Float64List(16)
                ..[0]  = s
                ..[5]  = s
                ..[10] = 1.0
                ..[15] = 1.0
                ..[12] = cx * (1 - s)  // translate to keep centre fixed
                ..[13] = cy * (1 - s);
              return BackdropFilter(
                filter: ImageFilter.compose(
                  // inner runs first: magnify background content
                  inner: ImageFilter.matrix(matrix),
                  // outer runs second: frosted-glass blur on magnified pixels
                  outer: ImageFilter.blur(sigmaX: 22, sigmaY: 22,
                      tileMode: TileMode.mirror),
                ),
                child: Stack(
              children: [
                // ── Glass body ─────────────────────────────────────────
                Container(
                  height: 66,
                  decoration: BoxDecoration(
                    color: glassColor,
                    borderRadius: BorderRadius.circular(38),
                    boxShadow: [
                      // Soft diffuse shadow
                      BoxShadow(
                        color: isDark
                            ? Colors.black.withAlpha(110)
                            : const Color(0xFF1C2A1C).withAlpha(32),
                        blurRadius: 36,
                        spreadRadius: -2,
                        offset: const Offset(0, 12),
                      ),
                      // Tight contact shadow
                      BoxShadow(
                        color: isDark
                            ? Colors.black.withAlpha(55)
                            : const Color(0xFF1C2A1C).withAlpha(12),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: List.generate(widget.tabs.length, (i) {
                      final active = i == widget.selectedIndex;
                      final tab = widget.tabs[i];
                      return Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => widget.onTap(i),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 260),
                                curve: Curves.easeOutCubic,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 5),
                                decoration: BoxDecoration(
                                  color: active
                                      ? indicatorColor
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(22),
                                ),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 220),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: (child, anim) =>
                                      ScaleTransition(
                                    scale: Tween<double>(begin: 0.80, end: 1.0)
                                        .animate(CurvedAnimation(
                                            parent: anim,
                                            curve: Curves.easeOutCubic)),
                                    child: FadeTransition(
                                        opacity: anim, child: child),
                                  ),
                                  child: Icon(
                                    active ? tab.activeIcon : tab.icon,
                                    key: ValueKey('${tab.path}_$active'),
                                    size: 22,
                                    color:
                                        active ? activeColor : inactiveColor,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 1),
                              AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOut,
                                style: GoogleFonts.manrope(
                                  fontSize: 9,
                                  fontWeight: active
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: active ? activeColor : inactiveColor,
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

                // ── Layer 1: Outer border (bright top, dim bottom) ──────
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _GlassBorderPainter(isDark: isDark),
                    ),
                  ),
                ),

                // ── Layer 2: Top specular highlight ─────────────────────
                Positioned.fill(
                  child: IgnorePointer(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(38),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.0, 0.22, 0.50],
                            colors: [
                              Colors.white.withAlpha(isDark ? 32 : 55),
                              Colors.white.withAlpha(isDark ? 8 : 16),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Layer 3: Bottom depth darkening ─────────────────────
                Positioned.fill(
                  child: IgnorePointer(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(38),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.55, 1.0],
                            colors: [
                              Colors.transparent,
                              Colors.black.withAlpha(isDark ? 38 : 14),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Layer 4: Centre-left internal shimmer ───────────────
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(38),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(-0.35, -0.9),
                            radius: 0.55,
                            colors: [
                              Colors.white.withAlpha(isDark ? 18 : 30),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),         // Stack
          );           // BackdropFilter (return)
        },             // LayoutBuilder builder
      ),               // LayoutBuilder
    ),                 // ClipRRect
      ),
    );
  }
}

// ─── Glass border painter (gradient: bright top arc → dim bottom arc) ─────────

class _GlassBorderPainter extends CustomPainter {
  const _GlassBorderPainter({required this.isDark});
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    const r = 38.0;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
      const Radius.circular(r),
    );

    // Top-half: bright specular rim
    final topPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: const [0.0, 0.45, 0.55, 1.0],
        colors: [
          Colors.white.withAlpha(isDark ? 55 : 120),
          Colors.white.withAlpha(isDark ? 30 : 70),
          Colors.white.withAlpha(isDark ? 12 : 30),
          Colors.white.withAlpha(isDark ? 6 : 12),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(rect, topPaint);
  }

  @override
  bool shouldRepaint(_GlassBorderPainter old) => old.isDark != isDark;
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
