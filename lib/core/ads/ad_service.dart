import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

final adServiceProvider = Provider<AdService>((ref) {
  final service = AdService();
  ref.onDispose(service.dispose);
  return service;
});

class AdMobIds {
  static const androidAppId = 'ca-app-pub-1653382608147355~6374141151';
  static const androidInterstitialUnitId =
      'ca-app-pub-1653382608147355/3165067038';

  static const _androidTestInterstitialUnitId =
      'ca-app-pub-3940256099942544/1033173712';

  static String? get interstitialUnitId {
    if (kIsWeb) return null;

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return kReleaseMode
            ? androidInterstitialUnitId
            : _androidTestInterstitialUnitId;
      default:
        return null;
    }
  }

  static bool get supportsCurrentPlatform => interstitialUnitId != null;
}

class AdService {
  static const _handsBetweenInterstitials = 3;

  InterstitialAd? _interstitialAd;
  bool _initializing = false;
  bool _initialized = false;
  bool _loadingInterstitial = false;
  bool _showingInterstitial = false;
  int _completedHandsSinceAd = 0;

  Future<void> initialize() async {
    if (_initialized || _initializing || !AdMobIds.supportsCurrentPlatform) {
      return;
    }

    _initializing = true;
    try {
      await MobileAds.instance.initialize();
      _initialized = true;
      unawaited(_loadInterstitial());
    } catch (error) {
      debugPrint('Mobile Ads failed to initialize: $error');
    } finally {
      _initializing = false;
    }
  }

  void showInterstitialAfterHand() {
    if (!_initialized || !AdMobIds.supportsCurrentPlatform) return;

    _completedHandsSinceAd++;
    if (_completedHandsSinceAd < _handsBetweenInterstitials) {
      unawaited(_loadInterstitial());
      return;
    }

    final ad = _interstitialAd;
    if (ad == null || _showingInterstitial) {
      unawaited(_loadInterstitial());
      return;
    }

    _completedHandsSinceAd = 0;
    _interstitialAd = null;
    _showingInterstitial = true;

    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _showingInterstitial = false;
        unawaited(_loadInterstitial());
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('Interstitial failed to show: $error');
        ad.dispose();
        _showingInterstitial = false;
        unawaited(_loadInterstitial());
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
      unawaited(_loadInterstitial());
    }
  }

  void dispose() {
    _interstitialAd?.dispose();
    _interstitialAd = null;
  }
}
