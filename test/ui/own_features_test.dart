import 'package:ai_model_manager/ai_model_manager.dart' show ModelIcon;

import 'dart:io';

import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/notes_page.dart';
import 'package:fluxdo/pages/reading_stats_page.dart';
import 'package:fluxdo/services/app_lock_service.dart';
import 'package:fluxdo/storage/topic_note_store.dart';
import 'package:fluxdo/widgets/app_lock_gate.dart';
import 'package:fluxdo/widgets/common/app_mark.dart';

import 'support/ui_harness.dart';

// 0.4.0 M9：自有功能（阅读统计、我的笔记、AI 模型头像）。数据都在本机存储里，
// 用 SharedPreferences 的 mock，不请求论坛。

void main() {
  setUpAll(loadUiFonts);

  group('阅读统计', () {
    for (final variant in [...UiVariant.portrait, ...UiVariant.landscape]) {
      testUi('不溢出、可访问（${variant.label}）', (tester) async {
        await pumpUi(tester, const ReadingStatsPage(), variant: variant);
        await tester.pump(const Duration(milliseconds: 300));
        expectNoUiException(tester);
        expectReadableBody(tester, variant);
        expect(find.text('阅读统计'), findsOneWidget);
        expect(find.text('今天'), findsWidgets);
        await uiShot(tester, 'm9_stats_${variant.label}');
        await expectUiAccessibility(tester, textContrast: false);
      });
    }

    testUi('今天的柱用 brand，其余用 avatar/fill，柱宽 24', (tester) async {
      await pumpUi(tester, const ReadingStatsPage());
      await tester.pump(const Duration(milliseconds: 300));
      final colors = tester
          .element(find.byType(ReadingStatsPage))
          .tokens
          .colors;
      final bars = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.constraints?.maxWidth == 24)
          .toList();
      expect(bars.length, 7);
      final fills = bars
          .map((c) => (c.decoration! as BoxDecoration).color)
          .toList();
      expect(fills.last, colors.brandPrimary);
      expect(fills.take(6).every((c) => c == colors.avatarFill), isTrue);
    });
  });

  group('我的笔记', () {
    Future<void> seed() async {
      await TopicNoteStore.save(
        TopicNote(
          topicId: 1,
          title: '【DP】Chase Sapphire Reserve 新开卡奖励',
          text: '总笔记',
          floorNotes: const {742: '这一楼说的 5/24 规则', 751: '补充'},
          updatedAt: DateTime(2026, 10, 30),
        ),
      );
      await TopicNoteStore.save(
        TopicNote(
          topicId: 2,
          title: '没有楼层的旧笔记',
          text: '旧笔记内容',
          updatedAt: DateTime(2026, 10, 29),
        ),
      );
    }

    for (final variant in [...UiVariant.portrait, ...UiVariant.landscape]) {
      testUi('有笔记时不溢出（${variant.label}）', (tester) async {
        await pumpUi(
          tester,
          const NotesPage(),
          variant: variant,
          settle: false,
        );
        await tester.runAsync(seed);
        await tester.pump(const Duration(milliseconds: 500));
        expectNoUiException(tester);
        expectReadableBody(tester, variant);
        expect(find.text('我的笔记'), findsOneWidget);
        await uiShot(tester, 'm9_notes_${variant.label}');
        await tester.pumpWidget(const SizedBox());
      });
    }

    testUi('空态给出怎么记笔记', (tester) async {
      await pumpUi(tester, const NotesPage());
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('还没有笔记'), findsOneWidget);
    });
  });

  group('模型头像', () {
    testUi('34 方块、首字母、读屏不读', (tester) async {
      await pumpUi(
        tester,
        const Scaffold(
          body: Center(
            child: ModelIcon(providerName: 'OpenAI', modelName: 'gpt-4o'),
          ),
        ),
      );
      expect(tester.getSize(find.byType(ModelIcon)), const Size(34, 34));
      expect(find.text('G'), findsOneWidget);
    });

    testUi('没有模型名时取服务商首字母，都没有显示 ?', (tester) async {
      await pumpUi(
        tester,
        const Scaffold(
          body: Column(
            children: [
              ModelIcon(providerName: 'deepseek', modelName: ''),
              ModelIcon(providerName: '', modelName: ''),
            ],
          ),
        ),
      );
      expect(find.text('D'), findsOneWidget);
      expect(find.text('?'), findsOneWidget);
    });
  });

  // 计划 §M9 要复核的真机问题里，能用 widget 测试守住的部分
  group('device-issues 复核', () {
    tearDown(() => AppLockService.instance.debugSetState());

    testUi('D-013 隐私遮罩：只有图标，没有文字和按钮，且屏蔽底下页面的语义', (tester) async {
      AppLockService.instance.debugSetState(enabled: true, obscured: true);
      await pumpUi(
        tester,
        const Scaffold(body: Stack(children: [Text('底下的页面'), AppLockGate()])),
      );
      expect(find.byType(AppMark), findsOneWidget);
      expect(find.text('美卡论坛已锁定'), findsNothing);
      expect(find.text('解锁'), findsNothing);
      expect(find.byType(BlockSemantics), findsWidgets);
    });

    testUi('D-013 锁屏：标题、说明和 48 高「解锁」按钮', (tester) async {
      AppLockService.instance.debugSetState(enabled: true, locked: true);
      await pumpUi(
        tester,
        const Scaffold(body: Stack(children: [AppLockGate()])),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('美卡论坛已锁定'), findsOneWidget);
      expect(find.text('解锁'), findsOneWidget);
      final button = tester.getSize(find.byType(FilledButton));
      expect(button.height, greaterThanOrEqualTo(48));
      await tester.pumpWidget(const SizedBox());
    });

    testUi('D-007 启动页 / 欢迎页 / 锁屏图标是静态的，没有持续动画', (tester) async {
      await pumpUi(
        tester,
        const Scaffold(body: Center(child: AppMark())),
        settle: false,
      );
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    test('D-019 / D-020 登录、引导、预热、锁屏和认证文案里没有 linux.do 字样', () {
      final files = [
        'lib/pages/login_page.dart',
        'lib/pages/onboarding_page.dart',
        'lib/widgets/preheat_gate.dart',
        'lib/widgets/app_lock_gate.dart',
        'lib/widgets/auth/login_form.dart',
        'lib/widgets/auth/webview_login_dialog.dart',
        'lib/pages/webview_login_page.dart',
        'lib/l10n/modules/auth/auth_zh.arb',
        'lib/l10n/modules/auth/auth_zh_TW.arb',
        'lib/l10n/modules/auth/auth_zh_HK.arb',
        'lib/l10n/modules/auth/auth_en.arb',
      ];
      for (final f in files) {
        final text = File(f).readAsStringSync().toLowerCase();
        // 只看代码和文案：注释和上游标识符（hCaptcha sitekey 常量名）不算界面文字
        final visible = text
            .split(String.fromCharCode(10))
            .where((l) => !l.trim().startsWith("//"))
            .join(" ")
            .replaceAll("_klinuxdohcaptchasitekey", "");
        expect(visible.contains('linux.do'), isFalse, reason: f);
        expect(visible.contains('linuxdo'), isFalse, reason: f);
      }
    });
  });
}
