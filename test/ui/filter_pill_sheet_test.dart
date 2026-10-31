import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ui_harness.dart';

// 筛选胶囊放在半屏里：深色下半屏底（sheetFill）就是 surface/grouped，胶囊底色
// 必须和半屏底、页面底都不同，选中态也要能看出来。

ShapeDecoration _pill(WidgetTester tester, String label) => find
    .ancestor(of: find.text(label), matching: find.byType(Container))
    .evaluate()
    .map((e) => (e.widget as Container).decoration)
    .whereType<ShapeDecoration>()
    .first;

void main() {
  setUpAll(loadUiFonts);

  for (final b in Brightness.values) {
    testUi('胶囊底色和页面底色、半屏底色不同；选中态有区别（${b.name}）', (tester) async {
      await pumpUi(
        tester,
        Scaffold(
          body: Row(
            children: [
              FilterPill(label: '未选中', onTap: () {}),
              FilterPill(label: '已选中', selected: true, onTap: () {}),
            ],
          ),
        ),
        variant: UiVariant(b, 1.0, UiDevice.proMax),
      );
      final tokens = AppTokens.of(tester.element(find.text('未选中')));
      final off = _pill(tester, '未选中').color!;
      final on = _pill(tester, '已选中').color!;
      expect(off, isNot(tokens.materials.sheetFill), reason: '胶囊和半屏同色，只剩一排散字');
      expect(off, isNot(tokens.colors.surfacePage), reason: '胶囊和页面同色');
      expect(on, isNot(off), reason: '选中态要有区别');
      expect((_pill(tester, '已选中').shape as StadiumBorder).side.color, tokens.colors.brandPrimary);
    });
  }
}
