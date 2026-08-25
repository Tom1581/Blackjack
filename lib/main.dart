import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/audio/sound_service.dart';
import 'core/strategy/strategy_coach.dart';
import 'core/supabase/supabase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Best effort only. Single-player must open even with no network, so a
  // backend that will not come up disables online play rather than the app.
  await AppSupabase.tryInitialize();
  await SoundService.load();
  await StrategyCoach.load();
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
}
