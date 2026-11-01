import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/diagnostics_page.dart';
import 'package:fluxdo/pages/reading_settings_page.dart';

import 'support/final4_11c1_support.dart';
import 'support/ui_harness.dart';

// 第 11 批 · 11c-1 出图（补充稿 33–42）。设 SHOTS_DIR 才落盘（约定放到
// shots/final4），不设置时只做「不抛异常」的检查。全部用假服务，不联网。
// 浅 / 深各一张：`编号_名称_light.png` / `编号_名称_dark.png`。

const _light = UiVariant(Brightness.light, 1.0, UiDevice.pro);
const _dark = UiVariant(Brightness.dark, 1.0, UiDevice.pro);

void main() {
  setUpAll(loadUiFonts);

  for (final (variant, suffix) in [(_light, 'light'), (_dark, 'dark')]) {
    testUi('33 诊断 · 高级 · 并发与限流（$suffix）', (tester) async {
      final (_, overrides) = await fakeStore();
      await pumpUi(
        tester,
        const DiagnosticsPage(),
        variant: variant,
        overrides: overrides,
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.scrollUntilVisible(
        find.byType(AppSegmented),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('自定义'));
      await tester.pumpAndSettle();
      // 滚到底，让「高级」区整块在画面里
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
      await tester.pumpAndSettle();
      expectNoUiException(tester);
      await uiShot(tester, '33_并发与限流_$suffix');
    });

    testUi('34 阅读 · 标签页打开方式（$suffix）', (tester) async {
      final (_, overrides) = await fakeStore();
      await pumpUi(
        tester,
        const ReadingSettingsPage(),
        variant: variant,
        overrides: overrides,
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('标签页打开方式'));
      await tester.pumpAndSettle();
      expectNoUiException(tester);
      await uiShot(tester, '34_标签页打开方式_$suffix');
    });
  }
}
