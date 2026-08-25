import 'dart:async';

import '../online_state.dart';
import '../transport/realtime_transport.dart';

/// The channel every open table announces itself on, so players can find a
/// game without being handed a room code.
///
/// Safe as a fixed name: room codes are generated from an alphabet with no
/// `O`, `I`, `0` or `1`, so no real code can ever be `LOBBY`.
const lobbyRoomCode = 'LOBBY';

/// One open table as advertised in the lobby.
class TableListing {
  final String code;
  final String hostName;
  final int seated;
  final int maxSeats;
  final OnlinePhase phase;
  final int round;

  const TableListing({
    required this.code,
    required this.hostName,
    required this.seated,
    required this.maxSeats,
    this.phase = OnlinePhase.betting,
    this.round = 0,
  });

  bool get isFull => seated >= maxSeats;

  int get openSeats {
    final open = maxSeats - seated;
    return open < 0 ? 0 : open;
  }

  /// A table you can actually sit down at right now.
  bool get isJoinable => !isFull;

  /// Cards are out, so a joiner watches until the next round.
  bool get inProgress => phase != OnlinePhase.betting;

  Map<String, dynamic> toJson() => {
        'c': code,
        'h': hostName,
        's': seated,
        'm': maxSeats,
        'p': phase.index,
        'r': round,
      };

  /// Read a listing out of a presence entry, or null if that member is just
  /// browsing rather than hosting.
  static TableListing? tryParse(Map<String, dynamic> data) {
    final code = data['c'];
    final host = data['h'];
    if (code is! String || code.isEmpty || host is! String) return null;
    final phaseIndex = data['p'];
    return TableListing(
      code: code,
      hostName: host,
      seated: (data['s'] as num?)?.toInt() ?? 0,
      maxSeats: (data['m'] as num?)?.toInt() ?? 0,
      phase: phaseIndex is int && phaseIndex >= 0 &&
              phaseIndex < OnlinePhase.values.length
          ? OnlinePhase.values[phaseIndex]
          : OnlinePhase.betting,
      round: (data['r'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TableListing &&
      other.code == code &&
      other.hostName == hostName &&
      other.seated == seated &&
      other.maxSeats == maxSeats &&
      other.phase == phase &&
      other.round == round;

  @override
  int get hashCode =>
      Object.hash(code, hostName, seated, maxSeats, phase, round);
}

/// Publishes one hosted table to the lobby, and keeps the entry current as
/// seats fill and rounds go by.
///
/// The listing lives in this client's presence entry, so it appears the moment
/// the host connects and disappears on its own the moment they leave — there
/// is no room list to keep tidy and nothing to garbage-collect.
class LobbyAnnouncer {
  final RealtimeTransport transport;

  TableListing? _published;
  bool _joined = false;
  bool _stopped = false;

  LobbyAnnouncer(this.transport);

  TableListing? get published => _published;

  /// Advertise [listing], or quietly update the existing advert. Repeating an
  /// unchanged listing does nothing, so this is safe to call on every state
  /// broadcast.
  Future<void> announce(TableListing listing) async {
    if (_stopped || listing == _published) return;
    _published = listing;
    if (!_joined) {
      _joined = true;
      await transport.join(lobbyRoomCode, listing.toJson());
    } else {
      await transport.updatePresence(listing.toJson());
    }
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _published = null;
    if (_joined) await transport.leave();
  }
}

/// Watches the lobby and reports the tables currently open.
class LobbyBrowser {
  final RealtimeTransport transport;

  final _controller = StreamController<List<TableListing>>.broadcast();
  StreamSubscription<List<PresenceMember>>? _sub;
  bool _stopped = false;

  /// Null until the first roster arrives, so the UI can tell "still looking"
  /// apart from "nothing open".
  List<TableListing>? tables;

  LobbyBrowser(this.transport);

  Stream<List<TableListing>> get stream => _controller.stream;

  Future<void> start() async {
    _sub = transport.presence.listen(_onPresence);
    await transport.join(lobbyRoomCode, const {'browsing': true});
  }

  void _onPresence(List<PresenceMember> members) {
    if (_stopped) return;
    final seen = <String, TableListing>{};
    for (final m in members) {
      final listing = TableListing.tryParse(m.data);
      // A host reconnecting can briefly appear twice; keep one entry per code.
      if (listing != null) seen[listing.code] = listing;
    }
    final list = seen.values.toList()..sort(_byMostInviting);
    tables = list;
    if (!_controller.isClosed) _controller.add(list);
  }

  /// Tables you can join come first, then the busiest ones — an empty table is
  /// the least appealing thing to sit down at.
  static int _byMostInviting(TableListing a, TableListing b) {
    if (a.isJoinable != b.isJoinable) return a.isJoinable ? -1 : 1;
    if (a.inProgress != b.inProgress) return a.inProgress ? 1 : -1;
    if (a.seated != b.seated) return b.seated.compareTo(a.seated);
    return a.code.compareTo(b.code);
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await _sub?.cancel();
    await transport.leave();
    await _controller.close();
  }
}
