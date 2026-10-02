import 'package:flutter/widgets.dart';

/// Tells a screen when it is back on top — the lobby re-reads the player's
/// record then, whichever screen was opened over it and by what.
final appRouteObserver = RouteObserver<ModalRoute<void>>();
