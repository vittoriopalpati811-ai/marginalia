import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/services/widget_service.dart';
import 'core/services/subscription_service.dart';
import 'core/storage/app_startup.dart';

const _supabaseUrl = 'https://ibucvloawkfwobaelwbr.supabase.co';
const _supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlidWN2bG9hd2tmd29iYWVsd2JyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg0NDA0NDAsImV4cCI6MjA5NDAxNjQ0MH0.TDjLBCVsjoITyT_GlsVw8fOTfelvL8ld56rTMdBizmc';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Always show the status bar; never let individual routes hide it.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // Default status-bar style: dark icons on cream bg (light theme).
  // Screens with dark headers override this via AppBar.systemOverlayStyle.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.light,       // iOS
    statusBarIconBrightness: Brightness.dark,    // Android
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  await Supabase.initialize(
    url: _supabaseUrl,
    anonKey: _supabaseAnonKey,
  );

  // RevenueCat — no-op on Windows/web, active on iOS/Android.
  // Replace REVENUECAT_PUBLIC_KEY_HERE in subscription_service.dart
  // before submitting to App Store.
  await SubscriptionService.configure();

  // Init home_widget bridge (no-op on non-iOS platforms)
  await WidgetService.init();

  await launchApp();
}
