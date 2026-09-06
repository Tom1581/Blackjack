import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/audio/sound_service.dart';
import 'core/rules/rules_store.dart';
import 'core/strategy/strategy_coach.dart';
import 'core/supabase/supabase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // These are local preference reads that keep the first screen consistent
  // with the player's settings. The network-only Supabase initialization
  // deliberately starts after the first Flutter frame is available.
  await Future.wait<void>([
    SoundService.load(),
    StrategyCoach.load(),
    RulesStore.load(),
  ]);
  // Lock to portrait — best UX for card game
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // Immersive mode: hide system bars for full-screen casino feel
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
  ));
  runApp(const ProviderScope(child: BlackjackApp()));
  // Single-player must never wait for a network request during app launch.
  unawaited(AppSupabase.tryInitialize());
}
