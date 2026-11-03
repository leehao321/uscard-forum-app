import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/app_harness.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() => AiProviderAuthDelegate.openRouterLogin = null);

  Future<void> pumpPage(WidgetTester tester) => pumpApp(
    tester,
    const AiProviderEditPage(),
    overrides: [aiSharedPreferencesProvider.overrideWithValue(prefs)],
  );

  String fieldText(WidgetTester tester, String label) {
    final field = find.ancestor(
      of: find.text(label),
      matching: find.byType(TextField),
    );
    return tester.widget<TextField>(field.first).controller!.text;
  }

  final loginButton = find.byKey(const ValueKey('openrouter-login'));

  testWidgets('没注入登录能力的平台：不显示按钮，手填不受影响', (tester) async {
    await pumpPage(tester);
    expect(loginButton, findsNothing);
    expect(find.text('快捷配置'), findsOneWidget);
    expect(find.text('API Key'), findsOneWidget);
  });

  testWidgets('一键登录：Key 和地址都填好，名称没填时也填上', (tester) async {
    AiProviderAuthDelegate.openRouterLogin = () async => 'sk-or-test';
    await pumpPage(tester);

    await tester.tap(loginButton);
    await tester.pumpAndSettle();

    expect(fieldText(tester, 'API Key'), 'sk-or-test');
    expect(fieldText(tester, 'Base URL'), 'https://openrouter.ai/api/v1');
    expect(find.text('OpenRouter'), findsWidgets);
  });

  testWidgets('用户取消：什么都不改', (tester) async {
    AiProviderAuthDelegate.openRouterLogin = () async => null;
    await pumpPage(tester);
    final before = fieldText(tester, 'Base URL');

    await tester.tap(loginButton);
    await tester.pumpAndSettle();

    expect(fieldText(tester, 'API Key'), isEmpty);
    expect(fieldText(tester, 'Base URL'), before);
  });

  testWidgets('登录失败：按钮恢复可点，Key 还是空的，可以手填', (tester) async {
    AiProviderAuthDelegate.openRouterLogin = () async => throw StateError('boom');
    await pumpPage(tester);

    await tester.tap(loginButton);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(fieldText(tester, 'API Key'), isEmpty);
    expect(tester.widget<ButtonStyleButton>(loginButton).onPressed, isNotNull);
  });

  group('快捷配置', () {
    for (final (name, url) in const [
      ('OpenRouter', 'https://openrouter.ai/api/v1'),
      ('Cline', 'https://api.cline.bot/api/v1'),
      ('One-API', 'http://localhost:3000/v1'),
    ]) {
      testWidgets('$name 填好地址，类型是 OpenAI 兼容', (tester) async {
        await pumpPage(tester);
        await tester.tap(find.widgetWithText(ActionChip, name));
        await tester.pumpAndSettle();
        expect(fieldText(tester, 'Base URL'), url);
      });
    }

    testWidgets('从别的类型切过来：类型下拉也跟着变', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byType(DropdownButtonFormField<AiProviderType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AiProviderType.gemini.label).last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, 'Cline'));
      await tester.pumpAndSettle();
      expect(find.text(AiProviderType.openai.label), findsOneWidget);
      expect(find.text(AiProviderType.gemini.label), findsNothing);
    });

    testWidgets('已经填的名称不会被覆盖', (tester) async {
      await pumpPage(tester);
      await tester.enterText(find.byType(TextField).first, '我的服务');
      await tester.tap(find.widgetWithText(ActionChip, 'Cline'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, '我的服务');
    });
  });
}
