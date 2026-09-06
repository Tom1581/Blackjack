import 'package:blackjack_app/features/table/table_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the betting table fits a compact desktop window',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 620));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: TableScreen()),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
