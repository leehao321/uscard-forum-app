import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/markdown_editor/composer_header_actions.dart';
import 'package:fluxdo/widgets/markdown_editor/composer_submit_button.dart';
import 'package:fluxdo/widgets/markdown_editor/emoji_sticker_panel.dart';

import 'support/ui_harness.dart';

// 0.4.0 收尾 B：上传没传完时「发送」置灰；表情面板顶部页内筛选。

Opacity _submitOpacity(WidgetTester tester) => tester.widget<Opacity>(
  find
      .ancestor(
        of: find.byKey(const ValueKey('composer-header-submit')),
        matching: find.byType(Opacity),
      )
      .first,
);

void main() {
  setUpAll(loadUiFonts);

  testUi('发送按钮：附件没传完压到 40% 不透明，但仍可点', (tester) async {
    var taps = 0;
    await pumpUi(
      tester,
      Scaffold(
        body: Center(
          child: ComposerSubmitButton(
            label: '发送',
            busy: false,
            dimmed: true,
            onPressed: () => taps++,
          ),
        ),
      ),
    );
    expect(_submitOpacity(tester).opacity, 0.4);
    await tester.tap(find.text('发送'));
    expect(taps, 1);
  });

  testUi('头部发送跟着上传状态变灰、传完恢复', (tester) async {
    final pending = ValueNotifier(false);
    await pumpUi(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => ComposerHeaderActions(
            availableWidth: MediaQuery.sizeOf(context).width,
            submitLabel: '发布',
            onSubmit: () {},
            previewing: false,
            onTogglePreview: () {},
            submitDimmed: pending,
          ),
        ),
      ),
    );
    expect(_submitOpacity(tester).opacity, 1);
    pending.value = true;
    await tester.pump();
    expect(_submitOpacity(tester).opacity, 0.4);
    pending.value = false;
    await tester.pump();
    expect(_submitOpacity(tester).opacity, 1);
  });

  testUi('提交中按钮不再叠加置灰', (tester) async {
    await pumpUi(
      tester,
      const Scaffold(
        body: Center(
          child: ComposerSubmitButton(
            label: '发送',
            busy: true,
            dimmed: true,
            onPressed: null,
          ),
        ),
      ),
      settle: false,
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(_submitOpacity(tester).opacity, 1);
  });

  for (final variant in [...UiVariant.portrait, ...UiVariant.landscape]) {
    testUi('表情面板：顶部「表情 · 表情包」筛选，不溢出（${variant.label}）', (tester) async {
      await pumpUi(
        tester,
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: 336,
              child: EmojiStickerPanel(
                onEmojiSelected: (_) {},
                onStickerSelected: (_) {},
                onBackspace: () {},
              ),
            ),
          ),
        ),
        variant: variant,
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expectNoUiException(tester);
      expect(find.text('表情'), findsOneWidget);
      expect(find.text('表情包'), findsOneWidget);
      // 筛选在面板最上面，高度 44
      final tabTop = tester.getTopLeft(find.text('表情')).dy;
      final panelTop = tester.getTopLeft(find.byType(EmojiStickerPanel)).dy;
      expect(tabTop - panelTop, lessThan(44));
    });
  }
}
