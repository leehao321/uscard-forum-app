import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/widgets/markdown_editor/composer_island.dart';
import 'package:fluxdo/widgets/markdown_editor/editor_tools.dart';
import 'package:fluxdo/widgets/markdown_editor/markdown_toolbar.dart';
import 'package:fluxdo/widgets/markdown_editor/rich_composer/rich_editor_tools.dart';

import 'support/ui_harness.dart';

// 0.4.0 M10 收尾：编辑器工具栏的图标语义核对（设计说明 §5.3 编辑器，Figma 47:1775）。
// 每个工具的图标常量、朗读标签和点击区都在这里钉死，图标改错会直接红。

/// 工具 id → 期望的图标（Lucide 语义：加粗 bold、斜体 italic、引用 quote…）
const _expectedIcons = <String, IconData>{
  kEditorToolImage: AppIcons.image,
  'attachment': AppIcons.paperclip,
  'media': AppIcons.video,
  'heading': AppIcons.heading,
  'bold': AppIcons.textBold,
  'italic': AppIcons.textItalic,
  'strikethrough': AppIcons.textStrike,
  'bulletList': AppIcons.listBulleted,
  'numberedList': AppIcons.listNumbered,
  'link': AppIcons.link,
  'quote': AppIcons.formatQuote,
  'callout': AppIcons.callout,
  'template': AppIcons.layoutTemplate,
  'inlineCode': AppIcons.code,
  'codeBlock': AppIcons.squareCode,
  'insertBlock': AppIcons.squarePlus,
  'spoiler': AppIcons.visibilityOff,
  'encrypt': AppIcons.lock,
  'poll': AppIcons.poll,
  'toc': AppIcons.tableOfContents,
  'imageGrid': AppIcons.layoutGrid,
};

void main() {
  setUpAll(loadUiFonts);

  group('编辑器工具注册表', () {
    testUi('每个工具的图标与期望一致，没有漏登记的工具', (tester) async {
      await pumpUi(tester, const SizedBox());
      final ids = {for (final t in editorTools) t.id};
      expect(ids, _expectedIcons.keys.toSet(), reason: '新增 / 删除工具要同步核对图标');
      for (final tool in editorTools) {
        final icon = tool.icon;
        expect(icon, isA<Icon>(), reason: tool.id);
        expect(
          (icon as Icon).icon,
          _expectedIcons[tool.id],
          reason: '${tool.id} 的图标',
        );
      }
    });

    testUi('每个工具都有朗读标签，菜单工具的每一项都有文字和值', (tester) async {
      await pumpUi(tester, const SizedBox());
      final s = S.current;
      for (final tool in editorTools) {
        expect(tool.label(s).trim(), isNotEmpty, reason: tool.id);
        if (tool.hasMenu) {
          final items = tool.menuItems!(s);
          expect(items, isNotEmpty, reason: tool.id);
          for (final item in items) {
            expect(item.label.trim(), isNotEmpty, reason: tool.id);
            expect(item.value, isNotNull, reason: tool.id);
          }
        }
      }
    });

    testUi('富文本工具：三级标题各有自己的图标，没有重复的图标 + 标签', (tester) async {
      final headings = [
        for (final t in richEditorTools)
          if (t.id.startsWith('heading')) t,
      ];
      expect(headings.map((t) => t.icon).toSet().length, headings.length);
      expect(headings.map((t) => t.icon), [
        AppIcons.heading1,
        AppIcons.heading2,
        AppIcons.heading3,
      ]);
      for (final t in richEditorTools) {
        expect(t.label.trim(), isNotEmpty, reason: t.id);
      }
    });
  });

  group('编辑器格式行', () {
    for (final variant in [
      UiVariant.lightDefault,
      const UiVariant(Brightness.dark, 1, UiDevice.pro),
      const UiVariant(Brightness.light, 1.3, UiDevice.pro),
      UiVariant.landscape.first,
    ]) {
      testUi('每个外显工具的点击区 ≥ 44（${variant.label}）', (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await pumpUi(
          tester,
          Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: MarkdownToolbar(
                controller: controller,
                visibleToolIds: const [
                  'bold',
                  'italic',
                  'heading',
                  kEditorToolImage,
                  'link',
                  'bulletList',
                  'quote',
                ],
                onToggleEmoji: () {},
                onToggleTools: () {},
              ),
            ),
          ),
          variant: variant,
        );
        expectNoUiException(tester);
        final buttons = find.byWidgetPredicate(
          (w) => w is IconButton || w is AppPressable,
        );
        expect(buttons, findsWidgets);
        var checked = 0;
        for (final element in buttons.evaluate()) {
          final box = element.renderObject as RenderBox?;
          if (box == null || !box.hasSize) continue;
          // 只检查有图标的工具按钮（容器类的 AppPressable 不算）
          final hasIcon = find
              .descendant(of: find.byWidget(element.widget), matching: find.byType(Icon))
              .evaluate()
              .isNotEmpty;
          if (!hasIcon) continue;
          checked++;
          expect(
            box.size.shortestSide,
            greaterThanOrEqualTo(AppSize.hit - 0.5),
            reason: '${element.widget} 点击区',
          );
        }
        expect(checked, greaterThanOrEqualTo(7), reason: '至少检查到 7 个工具按钮');
        await uiShot(tester, 'editor_toolbar_${variant.label}');
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  });

  group('横屏通栏工具条（设计说明 §5.6，Figma 47:1775）', () {
    for (final variant in [
      const UiVariant(Brightness.light, 1, UiDevice.landscape),
      const UiVariant(Brightness.dark, 1, UiDevice.landscape),
      const UiVariant(Brightness.light, 1, UiDevice.landscapePro),
    ]) {
      testUi('背景宽 = 屏宽，按钮落在阅读列内（${variant.label}）', (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await pumpUi(
          tester,
          Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ComposerIsland(
                child: MarkdownToolbar(
                  controller: controller,
                  visibleToolIds: const [
                    'bold',
                    'italic',
                    'heading',
                    kEditorToolImage,
                    'link',
                    'bulletList',
                    'quote',
                  ],
                  onToggleEmoji: () {},
                  onToggleTools: () {},
                ),
              ),
            ),
          ),
          variant: variant,
        );
        expectNoUiException(tester);
        final size = variant.device.size;
        // 最外层那个就是通栏底色（按 key 找到的第一个）
        final surface = find.byKey(const ValueKey('composer-island-surface')).first;
        final rect = tester.getRect(surface);
        expect(rect.left, 0, reason: '底色从屏幕左缘开始');
        expect(rect.width, size.width, reason: '底色横跨整个屏宽');
        // 按钮按阅读列对齐：W = 屏宽 − 安全区 ≥ 640 时列宽 640 居中
        final safe = variant.device.padding;
        final side = (size.width - kReadableMaxWidth) / 2;
        final left = side > safe.left ? side : safe.left;
        final right = size.width - (side > safe.right ? side : safe.right);
        final icons = find.descendant(
          of: surface,
          matching: find.byType(Icon),
        );
        expect(icons, findsWidgets);
        for (final element in icons.evaluate()) {
          final r = tester.getRect(find.byWidget(element.widget));
          expect(r.left, greaterThanOrEqualTo(left - 0.5), reason: '图标不出阅读列左缘');
          expect(r.right, lessThanOrEqualTo(right + 0.5), reason: '图标不出阅读列右缘');
        }
        await uiShot(tester, 'editor_toolbar_fullbleed_${variant.label}');
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }

    testUi('竖屏保持浮岛：左右各留 8、圆角不变', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpUi(
        tester,
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ComposerIsland(
              child: MarkdownToolbar(
                controller: controller,
                visibleToolIds: const ['bold'],
              ),
            ),
          ),
        ),
      );
      final rect = tester.getRect(
        find.byKey(const ValueKey('composer-island-surface')).first,
      );
      expect(rect.left, kComposerIslandInset);
      expect(rect.width, 440 - 2 * kComposerIslandInset);
    });
  });
}
