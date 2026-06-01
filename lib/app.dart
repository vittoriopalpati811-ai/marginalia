import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:marginalia/generated/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/theme.dart';
import 'core/providers/locale_provider.dart';
import 'core/providers/unread_messages_provider.dart';
import 'core/providers/auth_provider.dart';
import 'core/services/push_service.dart';
import 'features/paywall/paywall_screen.dart';
import 'core/providers/onboarding_provider.dart';
import 'core/providers/widget_sync_provider.dart';
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

/// Push transition: native iOS slide **with the interactive edge-swipe-back
/// gesture**.
///
/// Previously this returned a [CustomTransitionPage] wrapping a
/// [SharedAxisTransition]. It looked cinematic but it silently disabled the
/// swipe-from-the-left-edge-to-go-back gesture entirely — a [CustomTransitionPage]
/// has no `popGestureEnabled`. That is exactly the "gestures per tornare
/// indietro non funzionano sempre" bug: only the handful of screens still
/// pushed through `Navigator.push(MaterialPageRoute)` responded to the swipe,
/// so the gesture felt random.
///
/// [CupertinoPage] gives every pushed route the platform-standard horizontal
/// slide AND a fully interactive back-swipe, matching iOS HIG. Each pushed
/// screen owns an opaque [Scaffold], so there is no white-flash during the
/// parallax slide and the old `fillColor` workaround is no longer needed.
CupertinoPage<void> _pushPage(Widget child, GoRouterState state) {
  return CupertinoPage<void>(
    key: state.pageKey,
    child: child,
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

/// App-wide [MaterialApp.builder] that dismisses the soft keyboard whenever the
/// user taps an inert area of the screen.
///
/// Fixes "tastiera che non scompare quando dovrebbe": Flutter only drops focus
/// when a tap lands on another focus target, so tapping blank space used to
/// leave the keyboard up. A translucent [GestureDetector] at the very root
/// claims those otherwise-unhandled taps and unfocuses the primary focus node.
/// `HitTestBehavior.translucent` keeps every child (buttons, fields, scroll
/// views) winning the gesture arena first, so this never swallows real taps.
Widget _dismissKeyboardOnTap(BuildContext context, Widget? child) {
  final media = MediaQuery.of(context);
  // Clamp iOS Dynamic Type / Android font scaling. Without a ceiling, the
  // largest accessibility text sizes overflow fixed-height headers, chips,
  // pills and single-line rows all over the app ("non è molto responsive").
  // 1.3 still honours enlargement up to +30% for readability while keeping
  // every layout intact; 0.85 stops the tiniest setting from looking broken.
  final clampedTextScaler = media.textScaler.clamp(
    minScaleFactor: 0.85,
    maxScaleFactor: 1.3,
  );
  return MediaQuery(
    data: media.copyWith(textScaler: clampedTextScaler),
    child: GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: child,
    ),
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
  late final PushService _pushService =
      PushService(ref.read(supabaseServiceProvider));

  @override
  void initState() {
    super.initState();
    // Listen for passwordRecovery event (triggered when user opens the reset link).
    // When fired, navigate to the reset-password screen as soon as the router is ready.
    // Defensive: Supabase is an optional, offline-first layer. If it failed to
    // initialize during bootstrap, `Supabase.instance` throws — so guard the
    // auth listener to make sure a missing backend can never crash the shell.
    try {
      _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        if (data.event == AuthChangeEvent.passwordRecovery) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            router.push('/reset-password');
          });
        }
        // Register for APNs push whenever a session is active (covers the
        // initial-session event on launch AND later sign-ins). PushService is
        // idempotent and iOS-only; the native AppDelegate prompts for
        // permission, registers, and forwards the token to registerDeviceToken.
        if (data.session != null) {
          _pushService.start();
        }
      });
    } catch (error) {
      debugPrint(
          '[MarginaliaApp] auth listener not attached (Supabase unavailable): $error');
    }
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
        builder: _dismissKeyboardOnTap,
        home: const OnboardingScreen(),
      );
    }

    // Keep the iOS home-screen widgets (daily phrase + reading stats) in sync
    // with live app data for the whole authenticated session. No-op off-iOS.
    ref.watch(widgetSyncProvider);

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
      builder: _dismissKeyboardOnTap,
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

  // Phosphor Icons in Regular weight for inactive + Fill for active.
  // Thicker strokes + rounded line caps match the visual reference the
  // user provided (house with rounded outline, paper-plane-tilt, etc.)
  // and read much stronger than Material's hairline outlined glyphs.
  //
  // `label` is kept on the record but not rendered; Semantics() below
  // exposes it for VoiceOver/TalkBack.
  static final _tabs = <_Tab>[
    (path: '/home',     icon: PhosphorIconsRegular.house,           activeIcon: PhosphorIconsFill.house,           label: 'Home'),
    (path: '/',         icon: PhosphorIconsRegular.bookOpen,        activeIcon: PhosphorIconsFill.bookOpen,        label: 'Library'),
    (path: '/social',   icon: PhosphorIconsRegular.usersThree,      activeIcon: PhosphorIconsFill.usersThree,      label: 'Jam'),
    (path: '/messages', icon: PhosphorIconsRegular.paperPlaneTilt,  activeIcon: PhosphorIconsFill.paperPlaneTilt,  label: 'Messages'),
    (path: '/profile',  icon: PhosphorIconsRegular.userCircle,      activeIcon: PhosphorIconsFill.userCircle,      label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final selectedIndex =
        _tabs.indexWhere((t) => t.path == routePath).clamp(0, _tabs.length - 1);

    // Nuclear layout: previous attempts (StackFit.expand on AnimatedSwitcher,
    // 100dvh + flt-glass-pane sizing) didn't fix the navbar-floating-
    // mid-screen bug on Chrome iPhone simulator + real iOS Safari. The
    // common failure mode is that Scaffold's bottomNavigationBar slot
    // ends up sized to the route's intrinsic height rather than the
    // viewport's, leaving the nav adrift somewhere in the middle.
    //
    // Solution: don't use the bottomNavigationBar slot at all. Drop the
    // whole shell into a Stack with Positioned.fill for the body and
    // Positioned bottom:0 for the navbar. The navbar is now *physically*
    // anchored to the bottom of the available area, no matter what
    // Flutter's intrinsic-size logic decides about the body.
    // Reserved height for the overlay navbar — needed so route content
     // gets a matching bottom inset and doesn't render UNDER the bar.
     // 56 = icon block (12 pad + 28 icon + 12 pad) + 4 separator;
     // add safe-area-bottom for iPhone home indicator clearance.
    final navInset = 56 + MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          // ── Route content fills the full Scaffold area ──────────────
          // MediaQuery override adds navInset to the bottom padding so
          // any descendant that respects safe-area (SafeArea, Scaffold,
          // SliverPadding via MediaQuery.removePadding patterns) keeps
          // its content above the overlay navbar.
          Positioned.fill(
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: MediaQuery.of(context).padding.copyWith(
                  bottom: navInset,
                ),
                viewPadding: MediaQuery.of(context).viewPadding.copyWith(
                  bottom: navInset,
                ),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  fit: StackFit.expand,
                  children: [
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                ),
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: KeyedSubtree(
                  key: ValueKey(routePath),
                  child: child,
                ),
              ),
            ),
          ),

          // ── Nav bar pinned to the bottom of the viewport ────────────
          // Positioned bottom:0 GUARANTEES the bar is at the bottom of
          // the Scaffold body's painting layer, regardless of what
          // intrinsic-size logic the route's content does.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _LiquidGlassNavBar(
              selectedIndex: selectedIndex,
              tabs: _tabs,
              onTap: (i) {
                HapticFeedback.lightImpact();
                context.go(_tabs[i].path);
              },
            ),
          ),
        ],
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

class _LiquidGlassNavBar extends ConsumerStatefulWidget {
  const _LiquidGlassNavBar({
    required this.selectedIndex,
    required this.tabs,
    required this.onTap,
  });

  final int selectedIndex;
  final List<_Tab> tabs;
  final ValueChanged<int> onTap;

  @override
  ConsumerState<_LiquidGlassNavBar> createState() => _LiquidGlassNavBarState();
}

class _LiquidGlassNavBarState extends ConsumerState<_LiquidGlassNavBar>
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
            // Red dot top-left of the Messages icon when there are
            // unread conversations. Watching the provider here keeps
            // it alive across the whole shell so the badge updates
            // even when the user is not on the Messages tab.
            final isMessages = tab.path == '/messages';
            final unreadCount = isMessages
                ? ref.watch(unreadConversationsCountProvider)
                : 0;
            return Expanded(
              child: Semantics(
                // Keep the label accessible even though we no longer render it,
                // so VoiceOver/TalkBack still announce each tab by name.
                label: tab.label,
                button: true,
                selected: active,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onTap(i),
                  child: Padding(
                    // More vertical room now that text is gone, plus a bit
                    // wider hit area for the larger icons.
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: SizedBox(
                        // Fixed 28x28 box so the unread dot can sit at the
                        // icon's own top-left corner instead of the tab's.
                        width: 28,
                        height: 28,
                        child: Stack(
                          clipBehavior: Clip.none,
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
                                size: 28,
                                color: active ? activeColor : inactiveColor,
                              ),
                            ),
                            if (unreadCount > 0)
                              Positioned(
                                left: -3,
                                top:  -2,
                                child: Container(
                                  width:  10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE53935),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: surfaceColor,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
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
