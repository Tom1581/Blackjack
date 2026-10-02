import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../online/online_providers.dart';

/// One name and one look for the player everywhere: the home screen, online
/// tables, the leaderboards and the challenges they send.
///
/// The name lives where it always has (`online_player_name`, read by
/// [loadPlayerName]), so online tables and every leaderboard pick up a change
/// with no change of their own. The avatar colour is worked out from the name,
/// so every device draws the same player the same way without the online
/// protocol carrying anything new.
class PlayerIdentity {
  const PlayerIdentity._();

  /// The limit online tables and the leaderboards already enforce.
  static const maxLength = 12;

  static Future<String> load() async => clean(await loadPlayerName());

  static Future<String> save(String name) async {
    final cleaned = clean(name);
    await savePlayerName(cleaned);
    return cleaned;
  }

  /// Trimmed, inner runs of spaces collapsed, and at most [maxLength].
  static String clean(String name) {
    final collapsed = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    return collapsed.length > maxLength
        ? collapsed.substring(0, maxLength).trimRight()
        : collapsed;
  }

  static String initial(String name) {
    final cleaned = clean(name);
    return cleaned.isEmpty ? '?' : cleaned.characters.first.toUpperCase();
  }

  /// Distinct on the dark felt, none of them gold — gold marks "you".
  static const palette = [
    Color(0xFF5AB0FF),
    Color(0xFFB58CFF),
    Color(0xFF5FD4A0),
    Color(0xFFFF8A65),
    Color(0xFFFFC857),
    Color(0xFF4DD0E1),
    Color(0xFFF06292),
    Color(0xFFA5D66B),
  ];

  /// The same colour for the same name on every device: a fixed hash of the
  /// lower-cased name, not Dart's per-run [String.hashCode].
  static Color colorFor(String name) {
    var h = 0;
    for (final unit in clean(name).toLowerCase().codeUnits) {
      h = (h * 31 + unit) & 0x7fffffff;
    }
    return palette[h % palette.length];
  }
}

/// A round initial in the player's colour. [isMe] adds a gold ring.
class PlayerAvatar extends StatelessWidget {
  final String name;
  final double size;
  final bool isMe;

  const PlayerAvatar({
    super.key,
    required this.name,
    this.size = 32,
    this.isMe = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = PlayerIdentity.colorFor(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color.alphaBlend(color.withValues(alpha: 0.22), AppColors.bg),
        border: Border.all(
          color: isMe ? AppColors.gold : color.withValues(alpha: 0.85),
          width: isMe ? 2 : 1.3,
        ),
      ),
      child: Text(
        PlayerIdentity.initial(name),
        style: TextStyle(
          color: color,
          fontSize: size * 0.44,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

/// Ask for the player's name. Returns the saved name, or null if they backed
/// out without saving.
Future<String?> showEditNameSheet(BuildContext context, {String current = ''}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _NameSheet(current: current),
  );
}

class _NameSheet extends StatefulWidget {
  final String current;
  const _NameSheet({required this.current});

  @override
  State<_NameSheet> createState() => _NameSheetState();
}

class _NameSheetState extends State<_NameSheet> {
  late final _controller = TextEditingController(text: widget.current);
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = PlayerIdentity.clean(_controller.text);
    if (name.isEmpty || _saving) return;
    setState(() => _saving = true);
    HapticFeedback.lightImpact();
    final saved = await PlayerIdentity.save(name);
    if (mounted) Navigator.pop(context, saved);
  }

  @override
  Widget build(BuildContext context) {
    final name = PlayerIdentity.clean(_controller.text);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 18, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'YOUR NAME',
              style: TextStyle(
                color: AppColors.gold,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Shown at online tables, on the leaderboards and on the '
              'challenges you send.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                PlayerAvatar(name: name, size: 48, isMe: true),
                const SizedBox(width: 14),
                Expanded(
                  child: TextField(
                    key: const ValueKey('profile-name-field'),
                    controller: _controller,
                    autofocus: true,
                    maxLength: PlayerIdentity.maxLength,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _save(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                    decoration: InputDecoration(
                      hintText: 'e.g. Alex',
                      filled: true,
                      fillColor: Colors.black.withValues(alpha: 0.3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 50,
              child: FilledButton(
                key: const ValueKey('profile-name-save'),
                onPressed: name.isEmpty || _saving ? null : _save,
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
                child: const Text('SAVE'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
