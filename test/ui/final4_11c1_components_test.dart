import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ui_harness.dart';

// 第 11 批 · 11c-1 新增的通用分段控件 AppSegmentedControl（补充稿 33 / 40 / 41 共用）。

void main() {
  setUpAll(loadUiFonts);

  Future<List<int>> pumpSegmented(
    WidgetTester tester, {
    int selected = 0,
    UiVariant variant = UiVariant.lightDefault,
  }) async {
    final taps = <int>[];
    await pumpUi(
      tester,
      Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: AppSegmentedControl.indexed(
              labels: const ['甲', '乙', '丙'],
              selectedIndex: selected,
              onChanged: taps.add,
            ),
          ),
        ),
      ),
      variant: variant,
    );
    return taps;
  }

  testUi('点未选中的一段回调它的序号；点已选中的一段不回调', (tester) async {
    final taps = await pumpSegmented(tester, selected: 1);
    await tester.tap(find.text('丙'));
    await tester.tap(find.text('甲'));
    await tester.tap(find.text('乙'));
    expect(taps, [2, 0]);
  });

  testUi('每一段的点击区不小于 44，整条 44 高', (tester) async {
    await pumpSegmented(tester);
    expect(tester.getSize(find.byType(AppSegmentedControl<int>)).height, 44);
    for (final label in ['甲', '乙', '丙']) {
      final hit = tester.getSize(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(GestureDetector),
        ),
      );
      expect(hit.height, greaterThanOrEqualTo(44), reason: label);
      expect(hit.width, greaterThanOrEqualTo(44), reason: label);
    }
  });

  testUi('选中段是 surface/page 的圆角块，文字 Semibold；未选中段文字 meta', (tester) async {
    await pumpSegmented(tester, selected: 2);
    final colors = tester.element(find.byType(AppSegmentedControl<int>)).tokens.colors;
    final selectedStyle = tester.widget<Text>(find.text('丙')).style!;
    final otherStyle = tester.widget<Text>(find.text('甲')).style!;
    expect(selectedStyle.fontWeight, FontWeight.w600);
    expect(selectedStyle.color, colors.textPrimary);
    expect(otherStyle.fontWeight, FontWeight.w400);
    expect(otherStyle.color, colors.textMeta);
    // 滑块在选中的那一段（第 3 段）下面，是 surface/page 的圆角块
    final pill = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('segment_thumb')),
    );
    expect((pill.decoration as BoxDecoration).color, colors.surfacePage);
  });

  testUi('朗读：每段是按钮，选中状态跟着走', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpSegmented(tester, selected: 1);
    expect(
      tester.getSemantics(find.text('乙')),
      matchesSemantics(
        label: '乙',
        isButton: true,
        isSelected: true,
        isInMutuallyExclusiveGroup: true,
        isEnabled: true,
        hasEnabledState: true,
        hasSelectedState: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  for (final variant in UiVariant.portrait) {
    testUi('不溢出（${variant.label}）', (tester) async {
      await pumpSegmented(tester, variant: variant);
      expectNoUiException(tester);
    });
  }
}
