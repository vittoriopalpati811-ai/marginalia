import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';

Future<void> launchApp() async {
  runApp(const ProviderScope(child: MarginaliaApp()));
}
