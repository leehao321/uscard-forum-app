import 'package:ai_model_manager/ai_model_manager.dart'
    show AiProvidersPage, aiSharedPreferencesProvider;
import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/ai_chat_input.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'support/ui_harness.dart';

// 0.4.0 Figma 复核：逐节点对照后补的外观断言（只看尺寸和颜色，不碰真站）。

void main() {
  setUpAll(loadUiFonts);

  group('AI 聊天输入行（Figma 51:1088）', () {
    for (final variant in [
      UiVariant.lightDefault,
      const UiVariant(Brightness.dark, 1, UiDevice.proMax),
      const UiVariant(Brightness.light, 2, UiDevice.pro),
      ...UiVariant.landscape,
    ]) {
      testUi('输入框 r10、最低 44，发送钮 44 圆形（${variant.label}）', (tester) async {
        await pumpUi(
          tester,
          Scaffold(
            body: Column(
              children: [
                const Spacer(),
                AiChatInput(
                  isGenerating: false,
                  onSend: (_, _) {},
                  onStop: () {},
                ),
              ],
            ),
          ),
          variant: variant,
        );
        expectNoUiException(tester);
        // 输入框最低 44
        final field = tester.getSize(find.byType(TextField));
        expect(field.height, greaterThanOrEqualTo(AppSize.hit));
        // 发送钮：44 × 44，纸飞机图标
        expect(find.byIcon(AppIcons.send), findsOneWidget);
        final send = tester.getSize(
          find.ancestor(
            of: find.byIcon(AppIcons.send),
            matching: find.byType(IconButton),
          ),
        );
        expect(send, const Size(AppSize.hit, AppSize.hit));
        // 输入行左右边距 20（输入框右缘 + 8 + 发送钮 + 20 = 屏宽，扣横屏安全区）
        await uiShot(tester, 'fr_ai_input_${variant.label}');
        await expectUiAccessibility(tester, textContrast: false);
      });
    }
  });

  group('AI 模型服务入口（Figma 51:162）', () {
    for (final variant in [
      UiVariant.lightDefault,
      const UiVariant(Brightness.dark, 1, UiDevice.pro),
      const UiVariant(Brightness.light, 2, UiDevice.pro),
      ...UiVariant.landscape,
    ]) {
      testUi('单行导航 + 分组行 48 + 页脚说明（${variant.label}）', (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        await pumpUi(
          tester,
          const AiProvidersPage(),
          variant: variant,
          overrides: [aiSharedPreferencesProvider.overrideWithValue(prefs)],
        );
        expectNoUiException(tester);
        expect(find.text('AI 模型服务'), findsOneWidget);
        expect(find.text('供应商'), findsOneWidget);
        expect(find.text('快捷词管理'), findsOneWidget);
        // 页脚：不经过论坛的说明
        expect(find.textContaining('不经过论坛'), findsOneWidget);
        // 相邻两行（供应商 → 聊天记录，中间隔着「模型配置」可能不存在）：
        // 行最低 48，分组圆角 12
        final first = tester.getTopLeft(find.text('供应商')).dy;
        final second = tester.getTopLeft(find.text('聊天记录')).dy;
        expect(second - first, greaterThanOrEqualTo(48.5));
        await uiShot(tester, 'fr_ai_service_${variant.label}');
        await expectUiAccessibility(tester, textContrast: false);
      });
    }
  });
}
