import 'package:flutter/material.dart';
import 'features/lobby/lobby_screen.dart';
import 'theme/app_theme.dart';

class BlackjackApp extends StatelessWidget {
  const BlackjackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Blackjack — Hi-Lo',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const LobbyScreen(),
    );
  }
}
