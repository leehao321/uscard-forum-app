import 'dart:io';

import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/category.dart';
import 'package:fluxdo/widgets/markdown_editor/composer_chrome.dart';
import 'package:fluxdo/widgets/markdown_editor/composer_header_actions.dart';
import 'package:fluxdo/widgets/markdown_editor/composer_island.dart';
import 'package:fluxdo/widgets/markdown_editor/composer_page_chrome.dart';
import 'package:fluxdo/widgets/topic/topic_editor_helpers.dart';

import 'support/ui_harness.dart';

// 0.4.0 M5：编辑器外壳换皮——头部（x、标题、预览、发送）、顶栏背景、
// 分类 / 标签胶囊、底部工具岛。编辑逻辑不动，所以这里只看外壳不溢出、
// 可访问、尺寸对。

Widget _page({required bool previewing, required bool submitting}) {
  final draft = File('test/fixtures/composer_mixed_media_draft.md')
      .readAsStringSync()
      .split('\n')
      .take(6)
      .join('\n');
  return Builder(
    builder: (context) => Scaffold(
      appBar: AppBar(
        leading: Center(
          child: AppIconButton(
            icon: AppIcons.close,
            semanticLabel: '关闭',
            onPressed: () {},
          ),
        ),
        title: ComposerTopicKindPicker(question: false, onChanged: (_) {}),
        actions: [
          ComposerHeaderActions(
            availableWidth: MediaQuery.sizeOf(context).width,
            submitLabel: '发布',
            onSubmit: () {},
            submitting: submitting,
            previewing: previewing,
            onTogglePreview: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          ComposerMetaBar(
            category: null,
            categories: const <Category>[],
            onCategorySelected: (_) {},
            selectedTags: const ['设计', '反馈'],
            allTags: const ['设计', '反馈'],
            onTagsChanged: (_) {},
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.pageMargin),
              child: Text(draft),
            ),
          ),
          const ComposerIsland(
            child: SizedBox(height: 88, child: Center(child: Text('工具条'))),
          ),
        ],
      ),
    ),
  );
}

void main() {
  setUpAll(loadUiFonts);

  for (final variant in [...UiVariant.portrait, ...UiVariant.landscape]) {
    testUi('编辑器外壳不溢出且可访问（${variant.label}）', (tester) async {
      await pumpUi(
        tester,
        _page(previewing: false, submitting: false),
        variant: variant,
      );
      expectNoUiException(tester);
      await uiShot(tester, 'editor_${variant.label}');
      final send = find.byKey(const ValueKey('composer-header-submit'));
      expect(tester.getSize(send).height, 44);
      expect(tester.getSize(send).width, greaterThanOrEqualTo(66));
      await expectUiAccessibility(tester, textContrast: false);
    });
  }

  testUi('提交中发送按钮尺寸不变', (tester) async {
    await pumpUi(tester, _page(previewing: false, submitting: false));
    final send = find.byKey(const ValueKey('composer-header-submit'));
    final idle = tester.getSize(send);
    await pumpUi(
      tester,
      _page(previewing: false, submitting: true),
      settle: false,
    );
    await tester.pump();
    expect(tester.getSize(send), idle);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testUi('顶栏背景是实心工具栏材质，收起后只剩状态栏高度', (tester) async {
    final chrome = ComposerChromeController();
    addTearDown(chrome.dispose);
    await pumpUi(
      tester,
      Scaffold(
        body: ComposerChromeScope(
          controller: chrome,
          child: const ComposerTopFade(height: 100, statusBarHeight: 62),
        ),
      ),
    );
    final bar = find.byKey(const ValueKey('composer-top-bar'));
    expect(tester.getSize(bar).height, 100);
    expect(find.byType(BarSurface), findsOneWidget);
    chrome.hide();
    await tester.pumpAndSettle();
    expect(tester.getSize(bar).height, 62 + 24);
  });
}
