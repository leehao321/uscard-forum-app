import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/markdown_editor/composer_tools_anchor.dart';
import 'package:fluxdo/widgets/markdown_editor/composer_tools_panel.dart';
import 'package:fluxdo/widgets/markdown_editor/composer_workbench.dart';

import 'composer_interaction_test.dart' show pumpApp;

Future<ComposerToolsAnchor> pumpToolbar(
  WidgetTester tester, {
  required Brightness brightness,
  required Size size,
  bool reducedMotion = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final anchor = ComposerToolsAnchor();
  await pumpApp(
    tester,
    Builder(
      builder: (context) => Theme(
        data: ThemeData(brightness: brightness),
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reducedMotion,
            textScaler: const TextScaler.linear(1.5),
          ),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ComposerWorkbench(
                toolsAnchor: anchor,
                controls: const [],
                onExpandTools: () => anchor.expand([
                  ComposerToolAction(
                    id: 'bold',
                    label: '粗体',
                    icon: const Icon(Icons.format_bold),
                    run: () {},
                  ),
                ], const []),
                tools: SizedBox(
                  width: double.infinity,
                  child: ComposerCompactTools(
                    anchor: anchor,
                    child: const Icon(Icons.format_bold),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    desktop: false,
  );
  await tester.pumpAndSettle();
  return anchor;
}

void main() {
  // 0.4.0：编辑器底部工具岛用 v2 工具栏材质，不再随展开进度渐变玻璃配方；
  // 这里只守住展开 / 收起时按钮的淡出淡入、表面复用和减少动态效果。
  for (final brightness in Brightness.values) {
    for (final size in [const Size(375, 760), const Size(760, 375)]) {
      testWidgets('按钮随展开进度淡出，反向不中断 $brightness $size', (tester) async {
        final anchor = await pumpToolbar(
          tester,
          brightness: brightness,
          size: size,
        );
        final surface = find.byKey(const ValueKey('composer-island-surface'));
        final originalElement = tester.element(surface);
        double compactOpacity() => tester
            .widget<Opacity>(
              find.byKey(const ValueKey('composer-compact-visibility')),
            )
            .opacity;
        await tester.tap(find.byKey(const ValueKey('composer-tools-handle')));
        await tester.pump();
        expect(compactOpacity(), 1, reason: '按钮从原位置淡出，首帧不消失');
        await tester.pump(const Duration(milliseconds: 16));
        expect(compactOpacity(), inExclusiveRange(0, 1));
        final partial = compactOpacity();
        anchor.collapse();
        await tester.pump();
        expect(compactOpacity(), partial, reason: '收起从当前进度接续');
        anchor.reopen();
        await tester.pump();
        var previous = partial;
        for (var frame = 0; frame < 20; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(compactOpacity(), lessThanOrEqualTo(previous));
          previous = compactOpacity();
        }
        expect(compactOpacity(), 0);
        anchor.collapse();
        await tester.pump();
        for (var frame = 0; frame < 14; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(compactOpacity(), greaterThanOrEqualTo(previous));
          previous = compactOpacity();
        }
        expect(compactOpacity(), 1);
        expect(
          tester.element(surface),
          same(originalElement),
          reason: '复用单一表面',
        );
        expect(anchor.presenting, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        anchor.dispose();
      });
    }

    testWidgets('减少动态效果时直接完成展开收起 $brightness', (tester) async {
      final anchor = await pumpToolbar(
        tester,
        brightness: brightness,
        size: const Size(375, 760),
        reducedMotion: true,
      );
      await tester.tap(find.byKey(const ValueKey('composer-tools-handle')));
      await tester.pump();
      expect(
        tester
            .widget<Opacity>(
              find.byKey(const ValueKey('composer-compact-visibility')),
            )
            .opacity,
        0,
      );
      anchor.collapse();
      await tester.pump();
      expect(anchor.presenting, isFalse);
      expect(anchor.animation, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      anchor.dispose();
    });
  }
}
