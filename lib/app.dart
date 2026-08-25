import 'package:flutter/material.dart';

import 'core/onboarding/onboarding.dart';
import 'features/lobby/lobby_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/table/table_screen.dart';
import 'theme/app_theme.dart';

class BlackjackApp extends StatelessWidget {
  const BlackjackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Blackjack — Hi-Lo',
      debugShowCheckedModeBanner: false,
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
