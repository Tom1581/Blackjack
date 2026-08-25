import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

final adServiceProvider = ChangeNotifierProvider<AdService>((ref) {
  return AdService();
});

class AdMobIds {
  static const androidAppId = 'ca-app-pub-1653382608147355~6374141151';

  /// Live interstitial unit. Override at build time with
  /// `--dart-define=ADMOB_INTERSTITIAL_ANDROID=ca-app-pub-…/…`
  static const androidInterstitialUnitId = String.fromEnvironment(
    'ADMOB_INTERSTITIAL_ANDROID',
    defaultValue: 'ca-app-pub-1653382608147355/3165067038',
  );

  /// Live rewarded unit. **Create this in the AdMob console and set it here**
  /// (or via `--dart-define=ADMOB_REWARDED_ANDROID=…`). While it is empty the
  /// app simply grants the reward without an ad — nothing breaks, it just
  /// earns nothing.
  static const androidRewardedUnitId = String.fromEnvironment(
    'ADMOB_REWARDED_ANDROID',
    defaultValue: '',
  );

  // Google's public test units. Used in debug so nobody ever risks serving
  // themselves live ads while developing.
  static const _testInterstitialUnitId =
      'ca-app-pub-3940256099942544/1033173712';
  static const _testRewardedUnitId = 'ca-app-pub-3940256099942544/5224354917';

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static String? get interstitialUnitId {
    if (!_supported) return null;
    return kReleaseMode ? androidInterstitialUnitId : _testInterstitialUnitId;
  }

  static String? get rewardedUnitId {
    if (!_supported) return null;
    if (!kReleaseMode) return _testRewardedUnitId;
    // Never ship test ads to real players: with no live unit configured the
    // rewarded placements fall back to granting the reward directly.
    return androidRewardedUnitId.isEmpty ? null : androidRewardedUnitId;
  }

  static bool get supportsCurrentPlatform => interstitialUnitId != null;
}

/// When an interstitial is fetched and when it is shown.
///
/// Split out from [AdService] because it is the part that was costing money:
/// the old build preloaded an interstitial on **every app open** and only
/// showed one every third finished hand, so most sessions fetched an ad that
/// expired unseen. That produced roughly eleven ad requests per impression —
/// a ~9% show rate — which is wasted fill and looks like low-quality traffic.
class AdCadence {
  const AdCadence._();

  /// Finished hands between interstitials. Higher than it used to be on
  /// purpose: rewarded ads now carry the revenue, and interstitials cost
  /// retention every time they interrupt a round.
  static const handsBetweenInterstitials = 5;

  /// Fetch one hand early, so the ad is warm exactly when it is needed and
  /// not a moment before.
  static const preloadLead = 1;

  static bool shouldShow(int handsSinceLastAd) =>
      handsSinceLastAd >= handsBetweenInterstitials;

  static bool shouldPreload(int handsSinceLastAd) =>
      handsSinceLastAd >= handsBetweenInterstitials - preloadLead;
}

class AdService extends ChangeNotifier {
  InterstitialAd? _interstitialAd;
  RewardedAd? _rewardedAd;

  bool _initializing = false;
  bool _initialized = false;
  bool _loadingInterstitial = false;
  bool _loadingRewarded = false;
  bool _showingInterstitial = false;
  bool _showingRewarded = false;
  int _completedHandsSinceAd = 0;

  /// True when a rewarded ad is loaded and ready to play right now.
  ///
  /// Callers must check this before offering an ad, and offer something else
  /// when it is false — a button that promises an ad and shows nothing is
  /// exactly the bug this replaced.
  bool get rewardedReady => _rewardedAd != null && !_showingRewarded;

  Future<void> initialize() async {
    if (_initialized || _initializing || !AdMobIds.supportsCurrentPlatform) {
      return;
    }

    _initializing = true;
    try {
      await MobileAds.instance.initialize();
      _initialized = true;
      // Rewarded is user-initiated, so it must already be in hand when the
      // player asks. Interstitials are deliberately NOT preloaded here.
      unawaited(_loadRewarded());
    } catch (error) {
      debugPrint('Mobile Ads failed to initialize: $error');
    } finally {
      _initializing = false;
    }
  }

  // ─── Interstitials ───────────────────────────────────────────────────────

  void showInterstitialAfterHand() {
    if (!_initialized || !AdMobIds.supportsCurrentPlatform) return;

    _completedHandsSinceAd++;

    if (!AdCadence.shouldShow(_completedHandsSinceAd)) {
      if (AdCadence.shouldPreload(_completedHandsSinceAd)) {
        unawaited(_loadInterstitial());
      }
      return;
    }

    final ad = _interstitialAd;
    if (ad == null) {
      // The one warm-up request did not produce an ad. Treat this as a missed
      // placement and start a new cadence window instead of requesting on
      // every following hand while inventory is unavailable.
      _completedHandsSinceAd = 0;
      return;
    }
    if (_showingInterstitial) {
      return;
    }

    _completedHandsSinceAd = 0;
    _interstitialAd = null;
    _showingInterstitial = true;

    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _showingInterstitial = false;
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('Interstitial failed to show: $error');
        ad.dispose();
        _showingInterstitial = false;
      },
    );

    unawaited(_showInterstitial(ad));
  }

  Future<void> _loadInterstitial() async {
    final adUnitId = AdMobIds.interstitialUnitId;
    if (adUnitId == null || _loadingInterstitial || _interstitialAd != null) {
      return;
    }

    _loadingInterstitial = true;
    try {
      await InterstitialAd.load(
        adUnitId: adUnitId,
        request: const AdRequest(
          keywords: ['blackjack', 'cards', 'strategy', 'casino game'],
        ),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _interstitialAd = ad;
            _loadingInterstitial = false;
          },
          onAdFailedToLoad: (error) {
            debugPrint('Interstitial failed to load: $error');
            _loadingInterstitial = false;
          },
        ),
      );
    } catch (error) {
      debugPrint('Interstitial failed to start loading: $error');
      _loadingInterstitial = false;
    }
  }

  Future<void> _showInterstitial(InterstitialAd ad) async {
    try {
      await ad.show();
    } catch (error) {
      debugPrint('Interstitial failed to show: $error');
      ad.dispose();
      _showingInterstitial = false;
    }
  }

  // ─── Rewarded ────────────────────────────────────────────────────────────

  /// Play the rewarded ad and report whether the player actually earned the
  /// reward. Completes false if no ad was ready, the ad failed, or the player
  /// closed it early — the caller decides what to do about that.
  Future<bool> showRewarded() async {
    final ad = _rewardedAd;
    if (ad == null || _showingRewarded) return false;

    _rewardedAd = null;
    _showingRewarded = true;
    notifyListeners();
    var earned = false;
    final done = Completer<bool>();

    void finish(bool value) {
      _showingRewarded = false;
      notifyListeners();
      unawaited(_loadRewarded()); // have the next one ready
      if (!done.isCompleted) done.complete(value);
    }

    ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        finish(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('Rewarded failed to show: $error');
        ad.dispose();
        finish(false);
      },
    );

    try {
      await ad.show(onUserEarnedReward: (_, __) => earned = true);
    } catch (error) {
      debugPrint('Rewarded failed to show: $error');
      ad.dispose();
      finish(false);
    }

    // A callback that never arrives must not leave the caller waiting forever.
    return done.future.timeout(
      const Duration(seconds: 90),
      onTimeout: () {
        _showingRewarded = false;
        notifyListeners();
        unawaited(_loadRewarded());
        return earned;
      },
    );
  }

  Future<void> _loadRewarded() async {
    final adUnitId = AdMobIds.rewardedUnitId;
    if (adUnitId == null || _loadingRewarded || _rewardedAd != null) return;

    _loadingRewarded = true;
    try {
      await RewardedAd.load(
        adUnitId: adUnitId,
        request: const AdRequest(
          keywords: ['blackjack', 'cards', 'strategy', 'casino game'],
        ),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            _rewardedAd = ad;
            _loadingRewarded = false;
            notifyListeners();
          },
          onAdFailedToLoad: (error) {
            debugPrint('Rewarded failed to load: $error');
            _loadingRewarded = false;
          },
        ),
      );
    } catch (error) {
      debugPrint('Rewarded failed to start loading: $error');
      _loadingRewarded = false;
    }
  }

  @override
  void dispose() {
    _interstitialAd?.dispose();
    _interstitialAd = null;
    _rewardedAd?.dispose();
    _rewardedAd = null;
    super.dispose();
  }
}
