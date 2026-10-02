import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers the ads plugin's channel, which has no implementation under test.
///
/// Normally its calls just fail quietly, but anything that runs real async
/// work — a golden capture, `tester.runAsync` — lets the plugin's `_init`
/// reach the channel and throw MissingPluginException into the test.
void quietAdsPlugin(WidgetTester tester) {
  const channel = MethodChannel('plugins.flutter.io/google_mobile_ads');
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (_) async => null);
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
}
