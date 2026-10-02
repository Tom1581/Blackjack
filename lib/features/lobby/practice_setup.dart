import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/audio/sound_service.dart';
import '../../core/rules/rule_set.dart';
import '../../core/rules/rules_store.dart';
import '../../core/settings/table_prefs.dart';
import '../../core/strategy/strategy_coach.dart';
import '../../theme/app_theme.dart';
import '../table/table_provider.dart';

// Practice Setup: everything that shapes the practice table, in one place.
//
// It used to be a long panel at the bottom of the home screen, with the
// Hi-Lo explainer further down still. The home screen now shows a one-glance
// summary card; the settings open in a sheet grouped by what they affect —
// the table, counting, coaching, the app — with the explainer next to the
// count settings it explains.

/// The home screen's summary of the practice table. Tap to change it.
class PracticeSetupCard extends ConsumerStatefulWidget {
  const PracticeSetupCard({super.key});

  @override
  ConsumerState<PracticeSetupCard> createState() => _PracticeSetupCardState();
}

class _PracticeSetupCardState extends ConsumerState<PracticeSetupCard> {
  Future<void> _open() async {
    HapticFeedback.selectionClick();
    await showPracticeSetupSheet(context);
    // Hints live outside Riverpod; pick up a change made in the sheet.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final rules = ref.watch(rulesProvider);
    final shoe = ref.watch(shoeModeProvider);
    final spots = ref.watch(spotCountProvider);
    final showCount = ref.watch(showCountProvider);
    final index = ref.watch(indexPlaysProvider);
    final betCoach = ref.watch(betCoachProvider);
    final chips = [
      spots == 1 ? '1 hand' : '$spots hands',
      showCount ? 'Count shown' : 'Count hidden',
      StrategyCoach.hintsEnabled ? 'Hints on' : 'Hints off',
      if (index) 'Index plays',
      if (betCoach) 'Bet coach',
    ];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('home-practice-setup'),
        borderRadius: BorderRadius.circular(14),
        onTap: _open,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          decoration: BoxDecoration(
            color: AppColors.wood.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.tune,
                      color: AppColors.gold.withValues(alpha: 0.8), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'PRACTICE SETUP',
                      style: TextStyle(
                        color: AppColors.gold.withValues(alpha: 0.85),
                        fontSize: 10.5,
                        letterSpacing: 2.2,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const Text(
                    'EDIT',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      color: AppColors.gold, size: 18),
                ],
              ),
              const SizedBox(height: 8),
              // The table at a glance: the preset by name, then exactly what
              // it deals.
              Text(
                rules.name,
                key: const ValueKey('home-practice-rules'),
                style: TextStyle(
                  color: rules.isUnfavourable
                      ? AppColors.unfavorable
                      : Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${shoeLabel(shoe)} · ${rules.summary}',
                key: const ValueKey('home-practice-deal'),
                style: TextStyle(
                  color: AppColors.gold.withValues(alpha: 0.85),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in chips)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12)),
                      ),
                      child: Text(
                        c,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Open the full Practice Setup.
Future<void> showPracticeSetupSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, controller) =>
          _PracticeSetupSheet(controller: controller),
    ),
  );
}

class _PracticeSetupSheet extends ConsumerWidget {
  final ScrollController controller;
  const _PracticeSetupSheet({required this.controller});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showCount = ref.watch(showCountProvider);
    return ListView(
      key: const ValueKey('practice-setup-sheet'),
      controller: controller,
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'PRACTICE SETUP',
          style: TextStyle(
            color: AppColors.gold,
            fontSize: 13,
            letterSpacing: 2.5,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'For the practice table and its coach. Online play and the '
          'training games keep their own settings.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        const _Section(
          title: 'TABLE',
          icon: Icons.casino_outlined,
          children: [
            _RulePickerRow(),
            SizedBox(height: 14),
            _Label('Shoe'),
            SizedBox(height: 8),
            _ShoeSelector(),
            SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Label('Hands per round'),
                      SizedBox(height: 2),
                      Text(
                        'Play up to 3 hands at once',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                _HandsSelector(),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Section(
          title: 'COUNTING',
          icon: Icons.calculate_outlined,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Label('Show Hi-Lo Count HUD'),
                      SizedBox(height: 2),
                      Text(
                        'Turn off to keep the count yourself, like in a casino',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Switch(
                  key: const ValueKey('setup-show-count'),
                  value: showCount,
                  onChanged: (v) {
                    HapticFeedback.selectionClick();
                    ref.read(showCountProvider.notifier).state = v;
                    TablePrefs.setShowCount(v);
                  },
                ),
              ],
            ),
            if (!showCount) ...[
              const SizedBox(height: 6),
              const _CountCheckToggleRow(),
            ],
            const SizedBox(height: 4),
            Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: const ExpansionTile(
                key: ValueKey('setup-how-hilo'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.only(bottom: 4),
                iconColor: AppColors.gold,
                collapsedIconColor: AppColors.gold,
                leading: Icon(Icons.lightbulb_outline,
                    color: AppColors.gold, size: 18),
                title: Text(
                  'How Hi-Lo counting works',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                children: [_HiLoExplainer()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const _Section(
          title: 'COACHING',
          icon: Icons.school_outlined,
          children: [
            _HintsToggleRow(),
            SizedBox(height: 6),
            _IndexPlaysToggleRow(),
            SizedBox(height: 6),
            _BetCoachRow(),
          ],
        ),
        const SizedBox(height: 12),
        const _Section(
          title: 'APP',
          icon: Icons.settings_outlined,
          children: [
            _SoundToggleRow(),
            _PrivacyPolicyRow(),
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 50,
          child: FilledButton(
            key: const ValueKey('setup-done'),
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.wood,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
            child: const Text('DONE'),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon,
                  color: AppColors.gold.withValues(alpha: 0.75), size: 15),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: AppColors.gold.withValues(alpha: 0.85),
                  fontSize: 10.5,
                  letterSpacing: 2.2,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(color: Colors.white70, fontSize: 14),
    );
  }
}

/// Which table the player is practising against. Strategy is not universal,
/// so the coach and the dealer both follow whatever is chosen here.
class _RulePickerRow extends ConsumerWidget {
  const _RulePickerRow();

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final current = ref.read(rulesProvider);
    final chosen = await showModalBottomSheet<RuleSet>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'TABLE RULES',
                style: TextStyle(
                  color: AppColors.gold.withValues(alpha: 0.85),
                  fontSize: 11,
                  letterSpacing: 2.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'The correct play changes with the house rules. Both the '
                'dealer and the coach follow whichever table you pick.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              for (final preset in RuleSet.presets) ...[
                _RuleOption(
                  rules: preset,
                  selected: preset.id == current.id,
                  onTap: () => Navigator.pop(sheetContext, preset),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 4),
              Text(
                'The number of decks is the Shoe setting; the coach uses the '
                'right chart for 2, 6 and 8 decks. Single deck is not '
                'offered.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (chosen == null || chosen.id == current.id) return;
    await RulesStore.select(chosen);
    ref.read(rulesProvider.notifier).state = chosen;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(rulesProvider);
    return GestureDetector(
      onTap: () => _pick(context, ref),
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Table rules',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  rules.name,
                  style: TextStyle(
                    color: rules.isUnfavourable
                        ? AppColors.unfavorable
                        : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  rules.summary,
                  style: TextStyle(
                    color: AppColors.gold.withValues(alpha: 0.8),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right,
              color: Colors.white.withValues(alpha: 0.5), size: 20),
        ],
      ),
    );
  }
}

class _RuleOption extends StatelessWidget {
  final RuleSet rules;
  final bool selected;
  final VoidCallback onTap;

  const _RuleOption({
    required this.rules,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.gold.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppColors.gold
                : Colors.white.withValues(alpha: 0.12),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        rules.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (rules.isUnfavourable) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: AppColors.unfavorable
                                    .withValues(alpha: 0.7)),
                          ),
                          child: const Text(
                            'BAD TABLE',
                            style: TextStyle(
                              color: AppColors.unfavorable,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    rules.blurb,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.58),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    rules.summary,
                    style: TextStyle(
                      color: AppColors.gold.withValues(alpha: 0.75),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: AppColors.gold, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Basic-strategy hints. On by default — this is a trainer, and hiding the
/// answer by default helps nobody learn it.
class _HintsToggleRow extends StatefulWidget {
  const _HintsToggleRow();

  @override
  State<_HintsToggleRow> createState() => _HintsToggleRowState();
}

class _HintsToggleRowState extends State<_HintsToggleRow> {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Basic strategy hints',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
        Switch(
          value: StrategyCoach.hintsEnabled,
          onChanged: (value) async {
            await StrategyCoach.setHintsEnabled(value);
            if (mounted) setState(() {});
          },
        ),
      ],
    );
  }
}

/// Grade against the Illustrious 18 / Fab 4 index plays.
class _IndexPlaysToggleRow extends ConsumerWidget {
  const _IndexPlaysToggleRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(indexPlaysProvider);
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Index plays (Illustrious 18)',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              SizedBox(height: 2),
              Text(
                'The coach follows the count, not just the chart. '
                '4+ deck shoes.',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),
        Switch(
          value: enabled,
          onChanged: (v) {
            ref.read(indexPlaysProvider.notifier).state = v;
            TablePrefs.setIndexPlays(v);
          },
        ),
      ],
    );
  }
}

/// Show the bet the true count calls for, in the player's own units.
class _BetCoachRow extends ConsumerWidget {
  const _BetCoachRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(betCoachProvider);
    final unit = ref.watch(betUnitProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bet spread coach',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '1 unit up to +2, then true count − 1 units (max 8)',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
            Switch(
              value: enabled,
              onChanged: (v) {
                ref.read(betCoachProvider.notifier).state = v;
                TablePrefs.setBetCoach(v);
              },
            ),
          ],
        ),
        if (enabled)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Unit',
                    style: TextStyle(color: Colors.white54, fontSize: 12.5),
                  ),
                ),
                for (final u in TablePrefs.betUnits)
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      ref.read(betUnitProvider.notifier).state = u;
                      TablePrefs.setBetUnit(u);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(left: 5),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 5),
                      decoration: BoxDecoration(
                        color: u == unit ? AppColors.gold : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: u == unit
                              ? AppColors.gold
                              : AppColors.gold.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        '\$$u',
                        style: TextStyle(
                          color: u == unit ? AppColors.wood : Colors.white54,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Quiz the running count every few rounds while the HUD is hidden.
class _CountCheckToggleRow extends ConsumerWidget {
  const _CountCheckToggleRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(countCheckEnabledProvider);
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Count check quiz',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              SizedBox(height: 2),
              Text(
                'Asks for the running count every $countCheckEvery hands',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),
        Switch(
          value: enabled,
          onChanged: (v) {
            ref.read(countCheckEnabledProvider.notifier).state = v;
            TablePrefs.setCountCheck(v);
          },
        ),
      ],
    );
  }
}

class _SoundToggleRow extends StatefulWidget {
  const _SoundToggleRow();

  @override
  State<_SoundToggleRow> createState() => _SoundToggleRowState();
}

class _SoundToggleRowState extends State<_SoundToggleRow> {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Sound effects',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
        Switch(
          value: SoundService.enabled,
          onChanged: (value) async {
            await SoundService.setEnabled(value);
            if (mounted) setState(() {});
          },
        ),
      ],
    );
  }
}

class _PrivacyPolicyRow extends StatelessWidget {
  const _PrivacyPolicyRow();

  static final Uri _privacyPolicyUri =
      Uri.parse('https://thomas1581.github.io/privacy.html');

  Future<void> _open(BuildContext context) async {
    final opened = await launchUrl(
      _privacyPolicyUri,
      mode: LaunchMode.externalApplication,
    );
    if (!context.mounted || opened) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Unable to open the privacy policy.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open privacy policy',
      child: InkWell(
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(6),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Privacy policy',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
              Icon(
                Icons.open_in_new,
                color: Colors.white54,
                size: 18,
                semanticLabel: 'Open privacy policy',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Segmented 1 / 2 / 3 selector for how many hands the player deals each round.
class _HandsSelector extends ConsumerWidget {
  const _HandsSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(spotCountProvider);

    Widget btn(int count) {
      final selected = count == current;
      return GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          ref.read(spotCountProvider.notifier).state = count;
          TablePrefs.setSpots(count);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(left: 6),
          width: 38,
          padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.gold : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? AppColors.gold
                  : AppColors.gold.withValues(alpha: 0.25),
            ),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: selected ? AppColors.wood : Colors.white54,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [btn(1), btn(2), btn(3)],
    );
  }
}

/// The shoe, spelled out — "C.S." meant nothing to someone new.
String shoeLabel(ShoeMode mode) => switch (mode) {
      ShoeMode.continuousShuffle => 'Continuous shuffle',
      ShoeMode.twoDeck => '2 decks',
      ShoeMode.sixDeck => '6 decks',
      ShoeMode.eightDeck => '8 decks',
    };

class _ShoeSelector extends ConsumerWidget {
  const _ShoeSelector();

  static const _order = [
    ShoeMode.twoDeck,
    ShoeMode.sixDeck,
    ShoeMode.eightDeck,
    ShoeMode.continuousShuffle,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(shoeModeProvider);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final mode in _order)
          GestureDetector(
            key: ValueKey('shoe-${mode.name}'),
            onTap: () {
              HapticFeedback.lightImpact();
              ref.read(shoeModeProvider.notifier).state = mode;
              TablePrefs.setShoe(mode.name);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: mode == current ? AppColors.gold : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: mode == current
                      ? AppColors.gold
                      : AppColors.gold.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                shoeLabel(mode),
                style: TextStyle(
                  color: mode == current ? AppColors.wood : Colors.white70,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HiLoExplainer extends StatelessWidget {
  const _HiLoExplainer();

  @override
  Widget build(BuildContext context) {
    final term = const TextStyle(
      color: AppColors.gold,
      fontSize: 12,
      fontWeight: FontWeight.w900,
    );
    final body = TextStyle(
      color: Colors.white.withValues(alpha: 0.75),
      fontSize: 12,
      height: 1.45,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline,
                  color: AppColors.gold.withValues(alpha: 0.8), size: 15),
              const SizedBox(width: 8),
              Text(
                'HOW HI-LO COUNTING WORKS',
                style: TextStyle(
                  color: AppColors.gold.withValues(alpha: 0.8),
                  fontSize: 10,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: const [
              _ValueChip(label: '2–6', value: '+1', color: AppColors.favorable),
              SizedBox(width: 6),
              _ValueChip(label: '7–9', value: ' 0', color: AppColors.neutral),
              SizedBox(width: 6),
              _ValueChip(
                  label: '10–A', value: '−1', color: AppColors.unfavorable),
            ],
          ),
          const SizedBox(height: 14),
          RichText(
            text: TextSpan(children: [
              TextSpan(text: 'RC ', style: term),
              TextSpan(text: '(Running Count) ', style: body),
              TextSpan(
                text:
                    'is the total of those values for every card you\'ve seen since the last shuffle.',
                style: body,
              ),
            ]),
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(children: [
              TextSpan(text: 'TC ', style: term),
              TextSpan(
                  text: '(True Count) = RC ÷ decks remaining. ', style: body),
              TextSpan(
                text:
                    'It normalizes the count for shoe size, so a 4-deck shoe and a 6-deck shoe are comparable.',
                style: body,
              ),
            ]),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.favorable.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.favorable.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.trending_up, color: AppColors.favorable, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'TC ≥ +2 → many 10s & Aces left → favors you. Bet bigger.',
                    style: TextStyle(
                      color: AppColors.favorable,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ValueChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _ValueChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
