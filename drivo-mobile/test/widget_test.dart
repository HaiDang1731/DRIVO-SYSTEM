import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drivo_mobile/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const DrivoApp());
    // Loading screen should appear
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
