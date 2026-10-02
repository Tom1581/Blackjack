import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// A full-width button whose label shrinks to fit rather than overflow — the
/// heavy capitals these screens use run wide on a 320dp phone.
class HiLoButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool outlined;

  /// The outline and label colour of an [outlined] button; the theme's
  /// otherwise.
  final Color? accent;

  const HiLoButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.outlined = false,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
    const padding = EdgeInsets.symmetric(horizontal: 14);
    final child = FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20),
            const SizedBox(width: 8),
          ],
          Text(label, maxLines: 1),
        ],
      ),
    );
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: outlined
          ? OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                shape: shape,
                padding: padding,
                foregroundColor: accent,
                side: accent == null
                    ? null
                    : BorderSide(color: accent!.withValues(alpha: 0.6)),
              ),
              child: child,
            )
          : FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.wood,
                shape: shape,
                padding: padding,
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
