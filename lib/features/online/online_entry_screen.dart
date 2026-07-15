import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/card_model.dart';
import '../../theme/app_theme.dart';
import '../table/widgets/card_widget.dart';
import 'online_controller.dart';
import 'online_providers.dart';
import 'online_table_screen.dart';
import 'widgets/felt_background.dart';

/// Entry point for online play: pick a name, then host a new table or join an
/// existing one by its 4-letter room code.
class OnlineEntryScreen extends ConsumerStatefulWidget {
  const OnlineEntryScreen({super.key});

  @override
  ConsumerState<OnlineEntryScreen> createState() => _OnlineEntryScreenState();
}

class _OnlineEntryScreenState extends ConsumerState<OnlineEntryScreen> {
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  String? _playerId;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final id = await loadOrCreatePlayerId();
    final name = await loadPlayerName();
    if (!mounted) return;
    setState(() {
      _playerId = id;
      if (name.isNotEmpty) _nameCtrl.text = name;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  String get _name => _nameCtrl.text.trim();

  Future<void> _open({required bool host, required String roomCode}) async {
    if (_playerId == null || _busy) return;
    if (_name.isEmpty) {
      setState(() => _error = 'Enter a name first');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await savePlayerName(_name);
    final transport = ref.read(transportFactoryProvider)(_playerId!);
    final controller = OnlineController(
      transport: transport,
      isHost: host,
      roomCode: roomCode,
      playerName: _name,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OnlineTableScreen(controller: controller),
    ));
  }

  void _createTable() {
    HapticFeedback.mediumImpact();
    _open(host: true, roomCode: generateRoomCode());
  }

  void _joinTable() {
    HapticFeedback.mediumImpact();
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.length < 4) {
      setState(() => _error = 'Enter the 4-letter room code');
      return;
    }
    _open(host: false, roomCode: code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: FeltBackground(
        child: SafeArea(
          child: _playerId == null
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.gold))
              : Column(
                  children: [
                    _header(),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _Hero(),
                            const SizedBox(height: 18),
                            _label('YOUR NAME'),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _nameCtrl,
                              maxLength: 12,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                              decoration: _fieldDecoration('e.g. Alex'),
                              textInputAction: TextInputAction.done,
                            ),
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: AppColors.unfavorable,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 14),
                            _createPanel(),
                            const SizedBox(height: 16),
                            _orRow(),
                            const SizedBox(height: 16),
                            _joinPanel(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child:
                  Icon(Icons.arrow_back_ios, color: AppColors.gold, size: 20),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'PLAY ONLINE',
            style: TextStyle(
              color: AppColors.gold.withValues(alpha: 0.95),
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
              shadows: const [Shadow(color: Color(0x80D4AF37), blurRadius: 14)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _createPanel() {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.add_circle,
                  color: AppColors.gold.withValues(alpha: 0.9), size: 18),
              const SizedBox(width: 8),
              const Text(
                'HOST A NEW TABLE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'You get a room code to share. Friends join and you deal.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          _GoldButton(
            label: _busy ? 'CONNECTING…' : 'CREATE A TABLE',
            icon: Icons.casino,
            onTap: _busy ? null : _createTable,
          ),
        ],
      ),
    );
  }

  Widget _joinPanel() {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.login,
                  color: AppColors.gold.withValues(alpha: 0.9), size: 18),
              const SizedBox(width: 8),
              const Text(
                'JOIN WITH A CODE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _codeCtrl,
            maxLength: 4,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 10,
            ),
            textAlign: TextAlign.center,
            decoration: _fieldDecoration('ABCD'),
          ),
          const SizedBox(height: 8),
          _OutlineButton(
            label: 'JOIN TABLE',
            icon: Icons.arrow_forward,
            onTap: _busy ? null : _joinTable,
          ),
        ],
      ),
    );
  }

  Widget _panel({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.black.withValues(alpha: 0.35),
              Colors.black.withValues(alpha: 0.2),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: child,
      );

  Widget _orRow() => Row(
        children: [
          Expanded(child: _divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              'OR',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
          ),
          Expanded(child: _divider()),
        ],
      );

  Widget _label(String text) => Text(
        text,
        style: TextStyle(
          color: AppColors.gold.withValues(alpha: 0.8),
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 2,
        ),
      );

  Widget _divider() =>
      Container(height: 1, color: AppColors.gold.withValues(alpha: 0.25));

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.3),
            fontWeight: FontWeight.w600,
            letterSpacing: 0),
        counterText: '',
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.3),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.gold.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.gold, width: 1.5),
        ),
      );
}

// ─── Building blocks ────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 96,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 150,
                height: 90,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(60),
                  gradient: RadialGradient(colors: [
                    AppColors.gold.withValues(alpha: 0.2),
                    AppColors.gold.withValues(alpha: 0),
                  ]),
                ),
              ),
              Transform.translate(
                offset: const Offset(-30, 0),
                child: Transform.rotate(
                  angle: -0.14,
                  child: const CardWidget(
                    card: CardModel(suit: Suit.spades, rank: Rank.ace),
                    width: 62,
                    animate: false,
                  ),
                ),
              ),
              Transform.translate(
                offset: const Offset(30, 0),
                child: Transform.rotate(
                  angle: 0.14,
                  child: const CardWidget(
                    card: CardModel(suit: Suit.hearts, rank: Rank.king),
                    width: 62,
                    animate: false,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'PLAY WITH FRIENDS',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Share a table in real time — up to 5 players per table, '
          'as many tables as you like.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _GoldButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  const _GoldButton({required this.label, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: enabled
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFFE680), AppColors.gold, Color(0xFFB8860B)],
                )
              : null,
          color: enabled ? null : AppColors.goldDim.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          boxShadow: enabled
              ? [
                  BoxShadow(
                      color: AppColors.gold.withValues(alpha: 0.4),
                      blurRadius: 16,
                      spreadRadius: 1),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.wood, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.wood,
                fontSize: 15,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  const _OutlineButton({required this.label, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: AppColors.gold),
        label: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            fontSize: 14,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: AppColors.gold.withValues(alpha: 0.45)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
