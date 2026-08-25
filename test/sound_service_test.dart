import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:blackjack_app/core/audio/sound_service.dart';

void main() {
  late List<Sfx> played;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    played = [];
    SoundService.resetForTest();
    SoundService.playerOverride = played.add;
  });

  tearDown(SoundService.resetForTest);

  test('every sound points at a real asset path', () {
    for (final sfx in Sfx.values) {
      expect(sfx.file, endsWith('.wav'));
      expect(sfx.asset, 'sfx/${sfx.file}');
    }
    // The asset folder is declared in pubspec.yaml as assets/sfx/.
    expect(Sfx.values.map((s) => s.file).toSet().length, Sfx.values.length,
        reason: 'no two sounds share a file');
  });

  test('sounds play when enabled', () {
    SoundService.play(Sfx.chip);
    SoundService.play(Sfx.card);
    expect(played, [Sfx.chip, Sfx.card]);
  });

  test('muting silences everything', () async {
    await SoundService.setEnabled(false);
    played.clear();

    for (final sfx in Sfx.values) {
      SoundService.play(sfx);
    }
    expect(played, isEmpty);
    expect(SoundService.enabled, isFalse);
  });

  test('unmuting plays a tick so you hear what you just turned on', () async {
    await SoundService.setEnabled(false);
    played.clear();

    await SoundService.setEnabled(true);
    expect(SoundService.enabled, isTrue);
    expect(played, [Sfx.button]);
  });

  test('the preference survives a restart', () async {
    await SoundService.setEnabled(false);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('sfx_enabled'), isFalse);

    // A fresh launch reads it back.
    SoundService.resetForTest();
    SoundService.playerOverride = played.add;
    await SoundService.load();
    expect(SoundService.enabled, isFalse);
  });

  test('sound defaults to on for a new install', () async {
    SharedPreferences.setMockInitialValues({});
    SoundService.resetForTest();
    SoundService.playerOverride = played.add;
    await SoundService.load();
    expect(SoundService.enabled, isTrue);
  });
}
