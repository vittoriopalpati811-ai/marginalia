import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:animations/animations.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:scripta/generated/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/theme.dart';
import 'core/providers/locale_provider.dart';
import 'core/providers/unread_messages_provider.dart';
import 'core/providers/auth_provider.dart';
import 'core/providers/review_provider.dart';
import 'core/services/push_service.dart';
import 'core/services/local_notif_service.dart';
import 'core/providers/onboarding_provider.dart';
import 'core/providers/widget_sync_provider.dart';
import 'features/social/home_tab.dart';
import 'features/library/library_screen.dart';
import 'features/library/book_detail_screen.dart';
import 'features/reader/highlight_detail_screen.dart';
import 'features/review/review_screen.dart';
import 'features/wrapped/wrapped_screen.dart';
import 'features/search/search_screen.dart';
import 'features/social/social_screen.dart';
import 'features/social/jam_detail_screen.dart';
import 'features/social/jam_book_voting_screen.dart';
import 'features/social/jam_challenge_screen.dart';
import 'features/social/jam_poll_screen.dart';
import 'features/social/jam_review_leaderboard_screen.dart';
import 'features/social/notifications_screen.dart';
import 'features/social/feed_tab.dart';
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

/// Instant push — no slide in either direction (founder request 2026-06-11
/// for the book-detail screen: opening a book's saved phrases and returning
/// to the library must not animate). Back-swipe is not needed here; the
/// screen has its own back button.
NoTransitionPage<void> _instantPage(Widget child, GoRouterState state) {
  return NoTransitionPage<void>(
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
        return _instantPage(BookDetailScreen(bookId: id), state);
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
      path: '/jam/:id/ripasso',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (_, state) {
        final id = state.pathParameters['id'] ?? '';
        return _pushPage(JamReviewLeaderboardScreen(jamId: id), state);
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
    // Single post — full-screen push. Used by notification taps (deep link)
    // and by tapping a post in a profile timeline. Opens the post in the same
    // interactive card the feed uses (like / comment / menu all work).
    GoRoute(
      path: '/post/:id',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (_, state) {
        final id = state.pathParameters['id'] ?? '';
        return _pushPage(PostDetailScreen(postId: id), state);
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
    // Ripasso (spaced-repetition daily recall) — full-screen push with the iOS
    // slide + interactive back-swipe like every other pushed route.
    GoRoute(
      path: '/review',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (_, state) => _pushPage(const ReviewScreen(), state),
    ),
    // Reading Wrapped — a full-screen, immersive story player. Uses the modal
    // fade/slide-up (not the Cupertino push) so there is no left-edge back-swipe
    // fighting the "tap left third = previous slide" gesture.
    GoRoute(
      path: '/wrapped',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (_, state) => _modalPage(const WrappedScreen(), state),
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
  ],
);

// ─── App ─────────────────────────────────────────────────────────────────────

class ScriptaApp extends ConsumerStatefulWidget {
  const ScriptaApp({super.key});

  @override
  ConsumerState<ScriptaApp> createState() => _ScriptaAppState();
}

class _ScriptaAppState extends ConsumerState<ScriptaApp> {
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

          // Engagement nudge: schedule the daily "frase del giorno" local
          // notification (native iOS, reuses the push authorization). Fires at
          // 09:00 every morning. Idempotent — the native side reuses the
          // "daily_phrase" identifier, so re-scheduling on each session-active
          // event simply replaces the pending request.
          final isEnglish = ref.read(localeProvider).languageCode == 'en';
          LocalNotifService.scheduleDailyPhrase(
            hour: 9,
            minute: 0,
            title: 'Scripta',
            body: isEnglish
                ? 'Your phrase of the day is waiting 📖'
                : 'La tua frase di oggi ti aspetta 📖',
          );

          // Ripasso nudges: a morning reminder at 08:00 whose body carries the
          // live due count ("You have N highlights to review"), and an evening
          // reminder at 21:00 ("Did you do your review today?") that only fires
          // when today's ripasso isn't done yet. Best-effort and idempotent
          // (fixed "review_due" / "review_evening" identifiers); both are
          // computed from the local Isar state, so this works fully offline.
          _scheduleReviewReminder(isEnglish);
        } else if (data.event == AuthChangeEvent.signedOut) {
          // Stop re-registering the signed-out account's device token (the row
          // was already deleted in SupabaseService.signOut() while still
          // authenticated); resetting lets the NEXT account's start() register
          // cleanly instead of being blocked by the _started guard.
          _pushService.reset();
        }
      });
    } catch (error) {
      debugPrint(
          '[ScriptaApp] auth listener not attached (Supabase unavailable): $error');
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  /// Best-effort: (re)schedules BOTH Ripasso reminders from the local Isar
  /// state, iOS-only and fully offline. Never throws into the caller.
  ///
  ///   • Morning (08:00): "You have N highlights to review" — scheduled with a
  ///     dynamic count when something is due, cancelled when nothing is.
  ///   • Evening (21:00): "Did you do your review today?" — scheduled only when
  ///     the user has NOT yet reviewed today, cancelled once they have (the
  ///     session controller also cancels it the instant a session starts).
  Future<void> _scheduleReviewReminder(bool isEnglish) async {
    try {
      final due = await ref.read(dueCountProvider.future);
      if (due <= 0) {
        await LocalNotifService.cancelReviewReminder();
      } else {
        final body = isEnglish
            ? 'You have $due highlights to review 📖'
            : 'Hai $due highlight da ripassare 📖';
        await LocalNotifService.scheduleReviewReminder(
          hour: 8,
          minute: 0,
          title: 'Scripta',
          body: body,
        );
      }

      // Evening nudge: only when there is something to review AND today's
      // ripasso isn't done yet. Re-evaluated on every session-active event.
      final reviewState = await ref.read(reviewStateProvider.future);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final reviewedToday = reviewState.lastReviewedOn == today;
      if (due > 0 && !reviewedToday) {
        await LocalNotifService.scheduleEveningReviewReminder(
          hour: 21,
          minute: 0,
          title: 'Scripta',
          body: isEnglish
              ? 'Did you do your review today?'
              : 'Hai fatto il tuo ripasso di oggi?',
        );
      } else {
        await LocalNotifService.cancelEveningReviewReminder();
      }
    } catch (error) {
      debugPrint('[ScriptaApp] review reminder schedule skipped: $error');
    }
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
        title: 'Scripta',
        theme: buildScriptaTheme(),
        darkTheme: buildScriptaDarkTheme(),
        // Scripta is designed entirely on the warm "paper" light palette and
        // no screen implements dark-mode colours, so following the system theme
        // produced light text on light surfaces (illegible) on dark-mode phones.
        // Pin to light until a real dark theme is built across all screens.
        themeMode: ThemeMode.light,
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
      title: 'Scripta',
      theme: buildScriptaTheme(),
      darkTheme: buildScriptaDarkTheme(),
      // Pinned to LIGHT (same as the onboarding MaterialApp above): the app is
      // designed entirely on the warm "paper" light palette and no screen
      // implements real dark-mode colours, so following the system theme on a
      // dark-mode phone produced black input boxes with white text, a black
      // navbar, unreadable grey text and an invisible back arrow. Pin to light
      // until a full dark theme exists.
      themeMode: ThemeMode.light,
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

class _ScaffoldWithNavState extends State<_ScaffoldWithNav> {
  // Tab order (left → right): Library · Jam · Home (centre) · Messages · Profile.
  // Phosphor Icons in Regular weight for inactive + Fill for active.
  // `label` is kept on the record but not rendered; Semantics() exposes it.
  static final _tabs = <_Tab>[
    (path: '/',         icon: PhosphorIconsRegular.bookOpen,        activeIcon: PhosphorIconsFill.bookOpen,        label: 'Library'),
    (path: '/social',   icon: PhosphorIconsRegular.usersThree,      activeIcon: PhosphorIconsFill.usersThree,      label: 'Jam'),
    (path: '/home',     icon: PhosphorIconsRegular.house,           activeIcon: PhosphorIconsFill.house,           label: 'Home'),
    (path: '/messages', icon: PhosphorIconsRegular.paperPlaneTilt,  activeIcon: PhosphorIconsFill.paperPlaneTilt,  label: 'Messages'),
    (path: '/profile',  icon: PhosphorIconsRegular.userCircle,      activeIcon: PhosphorIconsFill.userCircle,      label: 'Profile'),
  ];

  // Drives the direction-aware MIRRORED slide between tabs: moving to a tab
  // further RIGHT slides one way, moving LEFT slides the exact mirror. Computed
  // per-build (not baked into a child) so both directions stay symmetric.
  int _prevIndex = -1;
  bool _slideReverse = false;

  @override
  Widget build(BuildContext context) {
    final routePath = widget.routePath;
    final selectedIndex =
        _tabs.indexWhere((t) => t.path == routePath).clamp(0, _tabs.length - 1);
    if (_prevIndex != -1 && selectedIndex != _prevIndex) {
      _slideReverse = selectedIndex < _prevIndex; // moving left → mirror
    }
    _prevIndex = selectedIndex;

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
     // The nav is now an ICON-ONLY FLOATING glass pill: ~50 bar height
     // (26 icon + 12 vertical padding each side + thin border) + 10 bottom
     // margin + a little breathing gap above it; add safe-area-bottom for the
     // iPhone home indicator clearance.
    final navInset = 64 + MediaQuery.of(context).padding.bottom;

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
              // Direction-aware MIRRORED slide between tabs, for both a tap and
              // a horizontal SWIPE (founder request). Moving right slides one
              // way, moving left mirrors it (PageTransitionSwitcher.reverse).
              // The fling gesture changes tab; inner horizontal lists win their
              // own drags via the gesture arena, so they keep scrolling.
              child: GestureDetector(
                onHorizontalDragEnd: (details) {
                  final v = details.primaryVelocity ?? 0;
                  if (v.abs() < 300) return; // only a deliberate fling
                  final target = (selectedIndex + (v < 0 ? 1 : -1))
                      .clamp(0, _tabs.length - 1);
                  if (target != selectedIndex) {
                    HapticFeedback.lightImpact();
                    context.go(_tabs[target].path);
                  }
                },
                child: PageTransitionSwitcher(
                  duration: const Duration(milliseconds: 320),
                  reverse: _slideReverse,
                  transitionBuilder:
                      (child, primaryAnimation, secondaryAnimation) =>
                          SharedAxisTransition(
                    animation: primaryAnimation,
                    secondaryAnimation: secondaryAnimation,
                    transitionType: SharedAxisTransitionType.horizontal,
                    fillColor: Colors.transparent,
                    child: child,
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(routePath),
                    child: widget.child,
                  ),
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
      color: ScriptaColors.background,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Text(
            '$h:$m',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: ScriptaColors.ink,
              letterSpacing: -0.3,
            ),
          ),
          const Spacer(),
          const Icon(Icons.signal_cellular_alt, size: 14, color: ScriptaColors.inkMuted),
          const SizedBox(width: 4),
          const Icon(Icons.wifi, size: 14, color: ScriptaColors.inkMuted),
          const SizedBox(width: 4),
          const Icon(Icons.battery_full, size: 14, color: ScriptaColors.inkMuted),
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
    final bottom = MediaQuery.of(context).padding.bottom;

    // ── Floating "liquid glass" pill bottom nav (iOS-style, light only) ──
    // A detached frosted-glass rounded card hovering just above the home
    // indicator, with a soft drop shadow. Five ICON-ONLY tabs (no labels).
    // The content behind the bar is blurred through a translucent white
    // surface (BackdropFilter inside a ClipRRect) so it reads as proper
    // iOS frosted glass; the selected tab is highlighted purely by colour
    // (filled icon + accent). The drop shadow and the thin border live on
    // the OUTER container, OUTSIDE the clip, so the shadow isn't blurred away.
    const selectedColor   = ScriptaColors.primaryDark; // sage accent
    const unselectedColor = ScriptaColors.inkMuted;
    const radius = 26.0;

    return AnimatedBuilder(
      animation: _bounceAnim,
      builder: (context, child) => Transform.scale(
        scale: _bounceAnim.value,
        alignment: Alignment.bottomCenter,
        child: child,
      ),
      child: Padding(
        // Float clear of the screen edges and the home indicator.
        padding: EdgeInsets.fromLTRB(14, 0, 14, bottom + 4),
        child: DecoratedBox(
          // OUTER container: carries the soft drop shadow + thin border and
          // the rounded shape. Kept outside the ClipRRect so the BackdropFilter
          // never clips away the shadow.
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: ScriptaColors.ruleFaint, width: 0.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
              BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: BackdropFilter(
              // Frost the content scrolling behind the bar.
              filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: Container(
                // Translucent glossy fill — brighter at the top so the bar
                // reads as iOS "liquid glass" (lit from above), still letting
                // the blurred backdrop show through.
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withOpacity(0.62),
                      Colors.white.withOpacity(0.40),
                    ],
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: SizedBox(
                  height: 50,
                  child: Stack(
                    children: [
                      // ── Sliding indicator ──────────────────────────────
                      // A soft sage pill that GLIDES to the selected tab's
                      // slot when the tab changes (one slot = 1/n of the
                      // row). Sits UNDER the icons.
                      Positioned.fill(
                        child: AnimatedAlign(
                          duration: const Duration(milliseconds: 340),
                          curve: Curves.easeOutBack,
                          // Alignment.x maps over the FREE space (bar width −
                          // pill width), so with a pill 1/n wide the slots sit
                          // at -1, -0.5, 0, 0.5, 1 — i.e. divide by (n−1), not
                          // n (dividing by n mis-centres every non-middle tab).
                          alignment: Alignment(
                            -1 +
                                2 *
                                    widget.selectedIndex /
                                    (widget.tabs.length - 1),
                            0,
                          ),
                          child: FractionallySizedBox(
                            widthFactor: 1 / widget.tabs.length,
                            heightFactor: 1,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 6),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: ScriptaColors.primaryDark
                                      .withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: List.generate(widget.tabs.length, (i) {
                    final active = i == widget.selectedIndex;
                    final tab    = widget.tabs[i];
                    final color  = active ? selectedColor : unselectedColor;
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
                        label: tab.label,
                        button: true,
                        selected: active,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => widget.onTap(i),
                          child: Center(
                            child: SizedBox(
                              // Fixed 26x26 box so the unread dot can sit at the
                              // icon's own top-left corner instead of the tab's.
                              width: 26,
                              height: 26,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    switchInCurve: Curves.easeOutCubic,
                                    switchOutCurve: Curves.easeInCubic,
                                    transitionBuilder: (child, anim) =>
                                        ScaleTransition(
                                      scale: Tween<double>(begin: 0.82, end: 1.0)
                                          .animate(CurvedAnimation(
                                              parent: anim,
                                              curve: Curves.easeOutCubic)),
                                      child: FadeTransition(
                                          opacity: anim, child: child),
                                    ),
                                    child: Icon(
                                      active ? tab.activeIcon : tab.icon,
                                      key: ValueKey('${tab.path}_$active'),
                                      size: 26,
                                      color: color,
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
                                            color: Colors.white,
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
                    );
                  }),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
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
