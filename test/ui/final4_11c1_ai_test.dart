import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:dio/io.dart' show IOHttpClientAdapter;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ui_harness.dart';

// 第 11 批 · 11c-1（补充稿 39 / 42）：AI 会话记录空态、高级设置。
// 快捷词管理（40 / 41）并入 43 一起做，测试在 final4_c2_prompts_test.dart。
// 数据全在 SharedPreferences 的 mock 里，不请求任何模型服务。

Future<(SharedPreferences, List<Override>)> _aiStore({
  Map<String, Object> values = const {},
  List<PromptPreset> builtIns = const [],
  bool withAdapter = true,
}) async {
  SharedPreferences.setMockInitialValues(values);
  final prefs = await SharedPreferences.getInstance();
  return (
    prefs,
    <Override>[
      aiSharedPreferencesProvider.overrideWithValue(prefs),
      builtInPresetsProvider.overrideWithValue(builtIns),
      if (withAdapter)
        aiDioAdapterFactoryProvider.overrideWithValue(IOHttpClientAdapter.new),
    ],
  );
}

void main() {
  setUpAll(loadUiFonts);

  group('39 AI · 会话记录 · 空', () {
    testUi('空态：48 图标 + 标题 + 说明，没有清空按钮', (tester) async {
      final (_, overrides) = await _aiStore();
      await pumpUi(tester, const AiChatHistoryPage(), overrides: overrides);
      expect(find.text('会话记录'), findsOneWidget);
      expect(find.text('暂无会话记录'), findsOneWidget);
      expect(find.text('和 AI 助手的对话会保存在这里'), findsOneWidget);
      final icon = tester.widget<Icon>(find.byIcon(AppIcons.chatBubble));
      expect(icon.size, 48);
      // 没有记录时导航右上不放「清除所有对话」
      expect(
        find.descendant(
          of: find.byType(AppNavBar),
          matching: find.byIcon(AppIcons.delete),
        ),
        findsNothing,
      );
      expectNoUiException(tester);
    });

    testUi('有记录时不显示空态，右上出现清除；清除后回到空态', (tester) async {
      final (prefs, overrides) = await _aiStore();
      await AiChatStorageService(prefs).saveSessionMessages(1, 's1', [
        AiChatMessage(
          id: 'm1',
          role: ChatRole.user,
          content: '你好',
          createdAt: DateTime(2026, 10, 30),
        ),
      ], topicTitle: '示例话题');
      await pumpUi(tester, const AiChatHistoryPage(), overrides: overrides);
      expect(find.text('示例话题'), findsOneWidget);
      expect(find.text('暂无会话记录'), findsNothing);

      final clear = find.descendant(
        of: find.byType(AppNavBar),
        matching: find.byIcon(AppIcons.delete),
      );
      expect(clear, findsOneWidget);
      await tester.tap(clear);
      await tester.pumpAndSettle();
      await tester.tap(find.text('清除全部'));
      await tester.pumpAndSettle();
      expect(find.text('暂无会话记录'), findsOneWidget);
      expect(find.text('和 AI 助手的对话会保存在这里'), findsOneWidget);
    });
  });

  group('42 AI · 高级设置', () {
    Finder switchTile(String title) => find.ancestor(
      of: find.text(title),
      matching: find.byType(SwitchListTile),
    );

    bool tileValue(WidgetTester tester, String title) =>
        tester.widget<SwitchListTile>(switchTile(title)).value;

    testUi('两条开关 + 页脚说明，默认都是关闭', (tester) async {
      final (_, overrides) = await _aiStore();
      await pumpUi(
        tester,
        const AiAdvancedSettingsPage(),
        overrides: overrides,
      );
      expect(find.text('高级设置'), findsOneWidget);
      expect(find.text('跟随应用网络配置'), findsOneWidget);
      expect(find.text('AI 请求使用应用的代理等网络设置'), findsOneWidget);
      expect(find.text('图像生成渐进帧'), findsOneWidget);
      expect(find.text('先返回模糊预览图，再返回最终图'), findsOneWidget);
      expect(
        find.text(
          '图像生成渐进帧仅支持 gpt-image 系列，需要 OpenAI 已验证 organization；未验证的账号开启后会生成失败。',
        ),
        findsOneWidget,
      );
      expect(tileValue(tester, '跟随应用网络配置'), isFalse);
      expect(tileValue(tester, '图像生成渐进帧'), isFalse);
      expectNoUiException(tester);
    });

    testUi('切换开关：状态翻转并写进存储，再切回关闭', (tester) async {
      final (prefs, overrides) = await _aiStore();
      await pumpUi(
        tester,
        const AiAdvancedSettingsPage(),
        overrides: overrides,
      );

      await tester.tap(switchTile('图像生成渐进帧'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tileValue(tester, '图像生成渐进帧'), isTrue);
      expect(prefs.getBool('ai_partial_images'), isTrue);
      // 另一条不受影响
      expect(tileValue(tester, '跟随应用网络配置'), isFalse);
      expect(prefs.getBool('ai_use_app_network'), isNull);

      await tester.tap(switchTile('跟随应用网络配置'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tileValue(tester, '跟随应用网络配置'), isTrue);
      expect(prefs.getBool('ai_use_app_network'), isTrue);

      await tester.tap(switchTile('图像生成渐进帧'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tileValue(tester, '图像生成渐进帧'), isFalse);
      expect(prefs.getBool('ai_partial_images'), isFalse);
    });

    testUi('存储里已开启的开关，进页面就是开着的', (tester) async {
      final (_, overrides) = await _aiStore(
        values: {'ai_use_app_network': true, 'ai_partial_images': true},
      );
      await pumpUi(
        tester,
        const AiAdvancedSettingsPage(),
        overrides: overrides,
      );
      expect(tileValue(tester, '跟随应用网络配置'), isTrue);
      expect(tileValue(tester, '图像生成渐进帧'), isTrue);
    });

    testUi('应用没有提供网络适配器时，「跟随应用网络配置」点不动', (tester) async {
      final (prefs, overrides) = await _aiStore(withAdapter: false);
      await pumpUi(
        tester,
        const AiAdvancedSettingsPage(),
        overrides: overrides,
      );
      await tester.tap(switchTile('跟随应用网络配置'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tileValue(tester, '跟随应用网络配置'), isFalse);
      expect(prefs.getBool('ai_use_app_network'), isNull);
    });
  });
}
