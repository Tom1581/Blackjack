import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

/// The frame every training screen shares: a back arrow, a gold title and an
/// optional badge on the right, over the app's dark felt.
class TrainingScaffold extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget child;

  const TrainingScaffold({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 18, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: AppColors.gold),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.gold,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.2,
                      ),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small outlined badge — score, timer, question number.
class TrainingBadge extends StatelessWidget {
  final String text;
  final Color color;

  const TrainingBadge(this.text, {super.key, this.color = AppColors.gold});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 58),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

/// A − value + stepper for entering a count.
class CountStepper extends StatelessWidget {
  final int value;
  final ValueChanged<int>? onChanged;

  const CountStepper({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget step(IconData icon, int delta) => Material(
          color: Colors.black.withValues(alpha: onChanged == null ? 0.1 : 0.3),
          shape: const CircleBorder(side: BorderSide(color: AppColors.goldDim)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onChanged == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onChanged!(value + delta);
                  },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Icon(icon,
                  color: onChanged == null ? Colors.white24 : AppColors.gold,
                  size: 26),
            ),
          ),
        );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        step(Icons.remove, -1),
        SizedBox(
          width: 110,
          child: Text(
            value > 0 ? '+$value' : '$value',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 44,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        step(Icons.add, 1),
      ],
    );
  }
}

/// A full-width primary button in the training style.
class TrainingButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool outlined;

  const TrainingButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Text(label)
            ],
          );
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: outlined
          ? OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(shape: shape),
              child: child,
            )
          : FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.wood,
                shape: shape,
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              child: child,
            ),
    );
  }
}

/// A result panel: headline number, a line of detail, then the actions.
class TrainingResultPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String headline;
  final String detail;
  final Color headlineColor;
  final List<Widget> children;

  const TrainingResultPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.headline,
    required this.detail,
    this.headlineColor = Colors.white,
    this.children = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.42)),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.gold, size: 38),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.gold,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            headline,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: headlineColor,
              fontSize: 46,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 22),
          ...children,
        ],
      ),
    );
  }
}

/// A row of labelled choice chips, e.g. drill length or pace.
class ChoiceRow<T> extends StatelessWidget {
  final String label;
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  const ChoiceRow({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.neutral,
            fontSize: 11,
            letterSpacing: 2,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (option, text) in options)
              ChoiceChip(
                label: Text(text),
                selected: option == value,
                onSelected: (_) => onChanged(option),
                selectedColor: AppColors.gold,
                labelStyle: TextStyle(
                  color: option == value ? AppColors.wood : Colors.white70,
                  fontWeight: FontWeight.w800,
                ),
                backgroundColor: Colors.black.withValues(alpha: 0.25),
                side: BorderSide(color: AppColors.gold.withValues(alpha: 0.35)),
                showCheckmark: false,
              ),
          ],
        ),
      ],
    );
  }
}
