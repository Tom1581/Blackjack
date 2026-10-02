import 'dart:async';

import 'package:flutter/material.dart';

import 'core/onboarding/onboarding.dart';
import 'features/hilo_training/daily_reminder.dart';
import 'features/hilo_training/hilo_links.dart';
import 'features/hilo_training/hilo_training_screen.dart';
import 'features/lobby/lobby_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/table/table_screen.dart';
import 'theme/app_theme.dart';

/// The root navigator, so a challenge link or a tapped Daily reminder can
/// open Hi-Lo Training from whatever screen the app is on.
final appNavigatorKey = GlobalKey<NavigatorState>();

class BlackjackApp extends StatefulWidget {
  const BlackjackApp({super.key});

  @override
  State<BlackjackApp> createState() => _BlackjackAppState();
}

class _BlackjackAppState extends State<BlackjackApp> {
  StreamSubscription<Uri>? _links;

  @override
  void initState() {
    super.initState();
    _links = HiLoLinks.listen(
      (challenge) => _open(HiLoTrainingScreen(initialChallenge: challenge)),
    );
    DailyReminder.onOpen = () => _open(const HiLoTrainingScreen());
    // Install the navigation callback before inspecting a notification that
    // may have launched the app, so a tap always lands in Hi-Lo Training.
    unawaited(DailyReminder.start());
  }

  @override
  void dispose() {
    _links?.cancel();
    DailyReminder.onOpen = null;
    super.dispose();
  }

  /// Push [screen] once the navigator exists — a link can arrive before the
  /// first frame.
  void _open(Widget screen, [int attempt = 0]) {
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) {
      if (attempt < 10) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _open(screen, attempt + 1));
      }
      return;
    }
    navigator.push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Blackjack — Hi-Lo',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      theme: buildAppTheme(),
      home: const FirstRunGate(),
    );
  }
}

/// Sends first-time players through the intro, and everybody else straight to
/// the lobby.
class FirstRunGate extends StatefulWidget {
  const FirstRunGate({super.key});

  @override
  State<FirstRunGate> createState() => _FirstRunGateState();
}

class _FirstRunGateState extends State<FirstRunGate> {
  /// Null while we are still reading the flag.
  bool? _seen;

  @override
  void initState() {
    super.initState();
    Onboarding.seen().then((value) {
      if (mounted) setState(() => _seen = value);
    });
  }

  void _onIntroDone() {
    setState(() => _seen = true);
    // The last button says "deal me in", so deal them in. The lobby is left
    // underneath, which is where Back goes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const TableScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final seen = _seen;
    if (seen == null) {
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.gold),
        ),
      );
    }
    if (seen) return const LobbyScreen();
    return OnboardingScreen(onDone: _onIntroDone);
  }
}
