import 'dart:io';

import 'package:flutter/services.dart';

/// Load the real Roboto and Material Icons fonts into the test engine.
///
/// Widget tests render text in the Ahem test font by default, where every
/// glyph is a full em wide — roughly twice as wide as Roboto. Layout checks
/// run in Ahem report overflows no phone would ever show, so the ones that
/// decide "does this fit a 360dp phone" load the fonts the app really uses.
///
/// Returns false (and loads nothing) if the fonts cannot be found, so a test
/// can skip rather than fail on an unusual SDK install.
Future<bool> loadRealFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  final dir = root == null
      ? null
      : Directory('$root/bin/cache/artifacts/material_fonts');
  if (dir == null || !dir.existsSync()) return false;

  Future<ByteData> bytes(String name) async =>
      ByteData.view(File('${dir.path}/$name').readAsBytesSync().buffer);

  final roboto = FontLoader('Roboto');
  for (final weight in [
    'Roboto-Light.ttf',
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Black.ttf',
  ]) {
    roboto.addFont(bytes(weight));
  }
  await roboto.load();

  final icons = FontLoader('MaterialIcons');
  icons.addFont(bytes('MaterialIcons-Regular.otf'));
  await icons.load();
  return true;
}
