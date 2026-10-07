import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:securecalc/src/app.dart';
import 'package:securecalc/src/core/config/app_config.dart';
import 'package:securecalc/src/core/config/environment.dart';

void main() {
  testWidgets('App renders calculator page successfully', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);

    AppConfig.initialize(Environment.dev);

    await tester.pumpWidget(const SynqChatApp());

    expect(find.text('AC'), findsOneWidget);
  });
}
