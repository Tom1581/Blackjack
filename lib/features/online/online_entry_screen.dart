import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/card_model.dart';
import '../../core/supabase/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../table/widgets/card_widget.dart';
import 'lobby/table_directory.dart';
import 'online_controller.dart';
import 'online_providers.dart';
import 'online_table_screen.dart';
import 'widgets/felt_background.dart';

/// Entry point for online play: pick a name, then host a new table or join an
/// existing one by its room code.
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

  /// Live list of tables other people are hosting right now.
  LobbyBrowser? _browser;
  List<TableListing>? _tables;

  /// Whether a table this player hosts is advertised in the lobby, or is
  /// invite-only by room code.
  ///
  /// Defaults to invite-only. The host device deals, and on the real transport
  /// a modified client can still claim to be another player, so a table of
  /// strangers is not something to opt people into by accident. Listing
  /// publicly stays one tap away.
  bool _listPublicly = false;

  /// A reconnect attempt is in flight after the backend failed to come up.
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final id = await loadOrCreatePlayerId();
    final name = await loadPlayerName();
    var authenticatedId = id;
    // Browsing uses the same private Realtime authorization as a table. A
    // test transport has no live Supabase client, so retain the local id when
    // this best-effort sign-in cannot run in a hermetic widget test.
    if (AppSupabase.isReady) {
      try {
        authenticatedId = await ref.read(onlineRoomAccessProvider).identify();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _playerId = authenticatedId;
      if (name.isNotEmpty) _nameCtrl.text = name;
    });
    _startBrowsing();
  }

  /// Watch the lobby. Presence carries each host's listing, so tables appear
  /// and vanish on their own with no database and nothing to clean up.
  void _startBrowsing() {
    final id = _playerId;
    if (id == null || _browser != null || !AppSupabase.isReady) return;
    final browser = LobbyBrowser(ref.read(transportFactoryProvider)(id));
    _browser = browser;
    browser.stream.listen((tables) {
      if (mounted) setState(() => _tables = tables);
    });
    browser.start().catchError((_) {
      // A lobby we cannot reach just shows as empty; hosting and joining by
      // code both still work.
      if (mounted) setState(() => _tables = const []);
    });
  }

  Future<void> _stopBrowsing() async {
    final browser = _browser;
    _browser = null;
    if (mounted) setState(() => _tables = null);
    await browser?.stop();
  }

  @override
  void dispose() {
    _browser?.stop();
    _browser = null;
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  String get _name => _nameCtrl.text.trim();

  Future<void> _open({required bool host, required String roomCode}) async {
    if (_playerId == null || _busy || !AppSupabase.isReady) return;
    if (_name.isEmpty) {
      setState(() => _error = 'Enter a name first');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await savePlayerName(_name);
    try {
      final access = ref.read(onlineRoomAccessProvider);
      final authenticatedId = await access.identify();
      if (host) {
        await access.create(
          roomCode: roomCode,
          displayName: _name,
          listed: _listPublicly,
        );
      } else {
        await access.join(roomCode: roomCode, displayName: _name);
      }
      _playerId = authenticatedId;
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = host
              ? 'Could not create this table. Please try again.'
              : 'That table is unavailable or full.';
        });
      }
      return;
    }
    // Browsing and playing do not need to happen at once — drop the lobby
    // connection while at the table and pick it back up on the way out.
    await _stopBrowsing();
    final factory = ref.read(transportFactoryProvider);
    final controller = OnlineController(
      transport: factory(_playerId!),
      isHost: host,
      roomCode: roomCode,
      playerName: _name,
      lobbyTransport: host ? factory(_playerId!) : null,
      listPublicly: _listPublicly,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    final outcome = await Navigator.of(context).push<OnlineExit>(
      MaterialPageRoute(
        builder: (_) => OnlineTableScreen(controller: controller),
      ),
    );
    if (!mounted) return;
    if (outcome == OnlineExit.retryHost) {
      _retryWithNewCode();
    } else {
      _startBrowsing();
    }
  }

  void _joinListed(TableListing listing) {
    HapticFeedback.mediumImpact();
    _open(host: false, roomCode: listing.code);
  }

  void _createTable() {
    HapticFeedback.mediumImpact();
    _open(host: true, roomCode: generateRoomCode());
  }

  /// The table screen pops with this when the code it tried to host turned out
  /// to be in use. Collisions are vanishingly rare, but when one happens the
  /// player should just get a fresh code rather than an error to puzzle over.
  void _retryWithNewCode() {
    if (!mounted) return;
    _createTable();
  }

  void _joinTable() {
    HapticFeedback.mediumImpact();
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.length < roomCodeLength) {
      setState(() => _error = 'Enter the $roomCodeLength-character room code');
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
                    if (!AppSupabase.isReady)
                      Expanded(child: _offlinePanel())
                    else
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
                              _openTablesPanel(),
                              const SizedBox(height: 16),
                              _orRow(),
                              const SizedBox(height: 16),
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

  /// Online needs the backend; the rest of the app does not. If it never came
  /// up, say so plainly and offer the one action that helps.
  Widget _offlinePanel() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off,
                color: AppColors.gold.withValues(alpha: 0.8), size: 40),
            const SizedBox(height: 16),
            const Text(
              'Online play is unavailable',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'We could not reach the game service. Check your connection and '
              'try again — single-player works either way.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 13.5,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: 220,
              child: _GoldButton(
                label: _retrying ? 'RECONNECTING…' : 'TRY AGAIN',
                icon: Icons.refresh,
                onTap: _retrying ? null : _retryBackend,
              ),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Back to single player',
                style: TextStyle(
                  color: AppColors.gold.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _retryBackend() async {
    setState(() => _retrying = true);
    final ok = await AppSupabase.tryInitialize();
    if (!mounted) return;
    setState(() => _retrying = false);
    if (ok) _startBrowsing();
  }

  Widget _openTablesPanel() {
    final tables = _tables;
    const maxRows = 6;
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.table_restaurant,
                  color: AppColors.gold.withValues(alpha: 0.9), size: 18),
              const SizedBox(width: 8),
              const Text(
                'OPEN TABLES',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              if (tables != null)
                Text(
                  tables.isEmpty ? 'none yet' : '${tables.length} live',
                  style: TextStyle(
                    color: AppColors.gold.withValues(alpha: 0.8),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (tables == null)
            const _LobbyLoading()
          else if (tables.isEmpty)
            Text(
              'Nobody is hosting right now. Start a table below and it will '
              'show up here for everyone else.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 12,
                height: 1.4,
              ),
            )
          else ...[
            for (final t in tables.take(maxRows)) ...[
              _TableRow(
                listing: t,
                onJoin: _busy ? null : () => _joinListed(t),
              ),
              if (t != tables.take(maxRows).last) const SizedBox(height: 8),
            ],
            if (tables.length > maxRows)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  '+${tables.length - maxRows} more open — join by code, or '
                  'start your own.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 11.5,
                  ),
                ),
              ),
          ],
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
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => setState(() => _listPublicly = !_listPublicly),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                SizedBox(
                  height: 26,
                  width: 40,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Switch(
                      value: _listPublicly,
                      activeThumbColor: AppColors.wood,
                      activeTrackColor: AppColors.gold,
                      onChanged: (v) => setState(() => _listPublicly = v),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _listPublicly
                        ? 'Listed in the lobby — anyone can join'
                        : 'Invite only — friends with the code',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
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
            maxLength: roomCodeLength,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 7,
            ),
            textAlign: TextAlign.center,
            decoration: _fieldDecoration('ABCDE'),
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
            color: Colors.white.withValues(alpha: 0.55),
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

/// One advertised table in the lobby list.
class _TableRow extends StatelessWidget {
  final TableListing listing;
  final VoidCallback? onJoin;

  const _TableRow({required this.listing, this.onJoin});

  @override
  Widget build(BuildContext context) {
    final joinable = listing.isJoinable;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: joinable
              ? AppColors.gold.withValues(alpha: 0.28)
              : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Opacity(
        opacity: joinable ? 1 : 0.55,
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surface,
                border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.5), width: 1.2),
              ),
              alignment: Alignment.center,
              child: Text(
                listing.hostName.isEmpty
                    ? '?'
                    : listing.hostName.substring(0, 1).toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "${listing.hostName}'s table",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${listing.code}  ·  ${listing.seated}/${listing.maxSeats}'
                    '  ·  ${listing.inProgress ? 'in play' : 'taking bets'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!joinable)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.25)),
                ),
                child: Text(
                  'FULL',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              )
            else
              GestureDetector(
                onTap: onJoin,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFFFE680), AppColors.gold],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'JOIN',
                    style: TextStyle(
                      color: AppColors.wood,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LobbyLoading extends StatelessWidget {
  const _LobbyLoading();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(AppColors.gold),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Looking for open tables…',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 12,
            fontWeight: FontWeight.w600,
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
                  colors: [
                    Color(0xFFFFE680),
                    AppColors.gold,
                    Color(0xFFB8860B)
                  ],
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
