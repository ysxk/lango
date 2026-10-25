import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lango/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('First launch shows connection form and validates the address', (
    tester,
  ) async {
    await tester.pumpWidget(const LangoApp());
    await tester.pumpAndSettle();

    expect(find.text('先连接，再开始。'), findsOneWidget);
    expect(find.text('连接并继续'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'not-a-server');
    await tester.ensureVisible(find.text('连接并继续'));
    await tester.tap(find.text('连接并继续'));
    await tester.pumpAndSettle();

    expect(find.textContaining('请输入完整服务地址'), findsOneWidget);
    expect(find.text('先连接，再开始。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Connection form fits a narrow phone viewport', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const LangoApp());
    await tester.pumpAndSettle();
    expect(find.text('连接并继续'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
