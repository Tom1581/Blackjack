import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/audio/sound_service.dart';
import '../../core/models/card_model.dart';
import '../../core/onboarding/onboarding.dart';
import '../../theme/app_theme.dart';
import '../online/widgets/felt_background.dart';
import '../table/widgets/card_widget.dart';

/// The first thing a new player sees.
///
/// Three screens, skippable from the first tap, ending on a button that deals
/// a hand. The old first run dropped people straight into a lobby holding a
/// settings panel and a Hi-Lo explainer, which assumes they already know what
/// Hi-Lo is and why they should care.
class OnboardingScreen extends StatefulWidget {
  /// Called when the intro is finished or skipped.
  final VoidCallback onDone;

  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;

  static const _lastPage = 2;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    HapticFeedback.mediumImpact();
    SoundService.play(Sfx.card);
    await Onboarding.markSeen();
    widget.onDone();
  }

  void _next() {
    HapticFeedback.selectionClick();
    SoundService.play(Sfx.button);
    if (_page >= _lastPage) {
      _finish();
    } else {
      _pages.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: FeltBackground(
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _finish,
                  child: Text(
                    _page >= _lastPage ? '' : 'Skip',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pages,
                  onPageChanged: (i) => setState(() => _page = i),
                  children: const [
                    _WhatThisIsPage(),
                    _HowTheCountWorksPage(),
                    _WhatYouCanDoPage(),
                  ],
                ),
              ),
              _Dots(count: _lastPage + 1, active: _page),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: GestureDetector(
                  onTap: _next,
                  child: Container(
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFFFFE680),
                          AppColors.gold,
                          Color(0xFFB8860B),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.gold.withValues(alpha: 0.4),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Text(
                      _page >= _lastPage ? 'DEAL ME IN' : 'NEXT',
                      style: const TextStyle(
                        color: AppColors.wood,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Pages ─────────────────────────────────────────────────────────────────

class _PageShell extends StatelessWidget {
  final Widget art;
  final String title;
  final String body;
  final Widget? extra;

  const _PageShell({
    required this.art,
    required this.title,
    required this.body,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 10),
          art,
          const SizedBox(height: 26),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 25,
              height: 1.15,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14.5,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (extra != null) ...[
            const SizedBox(height: 24),
            extra!,
          ],
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _WhatThisIsPage extends StatelessWidget {
  const _WhatThisIsPage();

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      art: SizedBox(
        height: 130,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 200,
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(80),
                gradient: RadialGradient(colors: [
                  AppColors.gold.withValues(alpha: 0.22),
                  AppColors.gold.withValues(alpha: 0),
                ]),
              ),
            ),
            Transform.translate(
              offset: const Offset(-36, 0),
              child: Transform.rotate(
                angle: -0.16,
                child: const CardWidget(
                  card: CardModel(suit: Suit.spades, rank: Rank.ace),
                  width: 78,
                  animate: false,
                ),
              ),
            ),
            Transform.translate(
              offset: const Offset(36, 0),
              child: Transform.rotate(
                angle: 0.16,
                child: const CardWidget(
                  card: CardModel(suit: Suit.hearts, rank: Rank.king),
                  width: 78,
                  animate: false,
                ),
              ),
            ),
          ],
        ),
      ),
      title: 'Count cards,\nnot just chips',
      body: 'A practice table built to make basic strategy and the Hi-Lo '
          'count automatic — before you ever sit at a real one.',
    );
  }
}

class _HowTheCountWorksPage extends StatelessWidget {
  const _HowTheCountWorksPage();

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      art: const Icon(Icons.calculate_outlined,
          size: 76, color: AppColors.gold),
      title: 'The Hi-Lo count',
      body: 'Add one number per card as it comes out. When the running count '
          'climbs, the shoe is rich in tens and aces — and the edge tips '
          'toward you.',
      extra: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          _CountChip(range: '2–6', value: '+1', color: AppColors.favorable),
          SizedBox(width: 10),
          _CountChip(range: '7–9', value: '0', color: AppColors.neutral),
          SizedBox(width: 10),
          _CountChip(range: '10–A', value: '−1', color: AppColors.unfavorable),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final String range;
  final String value;
  final Color color;

  const _CountChip({
    required this.range,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            range,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _WhatYouCanDoPage extends StatelessWidget {
  const _WhatYouCanDoPage();

  @override
  Widget build(BuildContext context) {
    return const _PageShell(
      art: Icon(Icons.groups, size: 76, color: AppColors.gold),
      title: 'Practice, then\nprove it',
      body: 'Everything runs on real casino rules — dealer hits soft 17, '
          'blackjack pays 3:2.',
      extra: Column(
        children: [
          _Bullet(
            icon: Icons.style,
            text: 'Play solo with the running count on screen',
          ),
          SizedBox(height: 12),
          _Bullet(
            icon: Icons.people_alt,
            text: 'Sit five players at one table, sharing one shoe',
          ),
          SizedBox(height: 12),
          _Bullet(
            icon: Icons.emoji_events,
            text: 'Climb the weekly rankings against everyone else',
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Bullet({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.gold.withValues(alpha: 0.14),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 17, color: AppColors.gold),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 13.5,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _Dots extends StatelessWidget {
  final int count;
  final int active;

  const _Dots({required this.count, required this.active});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == active ? 22 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: i == active
                  ? AppColors.gold
                  : Colors.white.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}
