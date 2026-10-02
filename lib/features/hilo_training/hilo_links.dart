import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import 'hilo_game.dart';

/// Challenge links: `hilobj://challenge/<code>` opens the app on a friend's
/// shoe.
///
/// Most chat apps do not make a custom-scheme link tappable, so the shared
/// message links to a small web page instead ([pageBase]) whose button opens
/// the app. The code rides in the path, never in a `code` query parameter:
/// supabase_flutter treats any link carrying `code` as a sign-in callback.
class HiLoLinks {
  const HiLoLinks._();

  static const scheme = 'hilobj';
  static const host = 'challenge';

  /// The published challenge page (`docs/challenge/index.html`), e.g.
  /// `https://tom1581.github.io/Blackjack/challenge/`. Empty until the page
  /// is live; shared messages leave the link out until then.
  static const pageBase = String.fromEnvironment('HILO_CHALLENGE_PAGE');

  static Uri appLink(String code) =>
      Uri(scheme: scheme, host: host, path: '/${code.toUpperCase()}');

  /// The tappable link for a shared message, or null while there is no page.
  static String? pageLink(String code) {
    if (pageBase.isEmpty) return null;
    final base = pageBase.endsWith('/') ? pageBase : '$pageBase/';
    return '$base?c=${code.toUpperCase()}';
  }

  /// The challenge a link carries, or null if it is not a challenge link.
  static HiLoChallenge? fromUri(Uri uri) {
    if (uri.scheme == scheme && uri.host == host) {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty);
      return segments.isEmpty ? null : HiLoChallenge.decode(segments.first);
    }
    // The web page's own address, should it ever open the app directly.
    final c = uri.queryParameters['c'];
    if ((uri.scheme == 'https' || uri.scheme == 'http') && c != null) {
      return HiLoChallenge.decode(c);
    }
    return null;
  }

  /// Where incoming links come from. Tests swap it; under `flutter test` the
  /// platform plugin is not there, so nothing is listened to by default.
  @visibleForTesting
  static Stream<Uri> Function()? sourceOverride;

  /// Calls [onChallenge] for every challenge link that opens the app — the
  /// one it was launched with and any that arrive while it runs. Returns the
  /// subscription to cancel, or null when there is nothing to listen to.
  static StreamSubscription<Uri>? listen(
    void Function(HiLoChallenge challenge) onChallenge,
  ) {
    String? last;
    DateTime? lastAt;
    void handle(Uri? uri) {
      if (uri == null) return;
      // The launch link can arrive both from getInitialLink and the stream.
      final now = DateTime.now();
      if ('$uri' == last &&
          lastAt != null &&
          now.difference(lastAt!) < const Duration(seconds: 5)) {
        return;
      }
      final challenge = fromUri(uri);
      if (challenge == null) return;
      last = '$uri';
      lastAt = now;
      onChallenge(challenge);
    }

    final override = sourceOverride;
    if (override != null) return override().listen(handle);
    if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) {
      return null;
    }
    try {
      final links = AppLinks();
      links.getInitialLink().then(handle, onError: (Object e) {
        debugPrint('Hi-Lo links: no initial link ($e)');
      });
      return links.uriLinkStream.listen(handle, onError: (Object e) {
        debugPrint('Hi-Lo links: $e');
      });
    } catch (error) {
      debugPrint('Hi-Lo links unavailable: $error');
      return null;
    }
  }
}
