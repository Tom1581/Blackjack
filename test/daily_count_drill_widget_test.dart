import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:blackjack_app/features/drill/daily_count_drill_screen.dart';

void main() {
  testWidgets('the daily drill fits a small phone', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: DailyCountDrillScreen()));
    await tester.pump();

    expect(find.text('DAILY COUNT DRILL'), findsOneWidget);
    expect(find.text('-1'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('+1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
