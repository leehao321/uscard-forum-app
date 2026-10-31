import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/floor_jump_sheet.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/reading_toolbar.dart';

import 'support/ui_harness.dart';

// 0.4.0 M4：阅读页——底部工具栏、楼层跳转半屏、楼层跳转校验。

Widget _toolbar({
  required ValueNotifier<bool> expanded,
  required ValueNotifier<int> floor,
  int total = 42,
  List<String>? log,
}) => Scaffold(
  body: Stack(
    children: [
      ReadingToolbar(
        expandedListenable: expanded,
        floorListenable: floor,
        total: total,
        isLoggedIn: true,
        bookmarked: false,
        notificationIcon: Icons.notifications_none,
        onReply: () => log?.add('reply'),
        onNotification: () => log?.add('bell'),
        onBookmark: () => log?.add('bookmark'),
        onShare: () => log?.add('share'),
        onOpenFloorJump: () => log?.add('floor'),
      ),
    ],
  ),
);

void main() {
  setUpAll(loadUiFonts);

  group('楼层跳转校验', () {
    test('只接受 1 到最高楼层的整数', () {
      expect(FloorJumpSheet.parseFloor('1', 42), 1);
      expect(FloorJumpSheet.parseFloor(' 42 ', 42), 42);
      expect(FloorJumpSheet.parseFloor('0', 42), isNull);
      expect(FloorJumpSheet.parseFloor('43', 42), isNull);
      expect(FloorJumpSheet.parseFloor('', 42), isNull);
      expect(FloorJumpSheet.parseFloor('abc', 42), isNull);
    });
  });

  group('阅读工具栏', () {
    for (final variant in [...UiVariant.portrait, ...UiVariant.landscape]) {
      testUi('展开与收起不溢出（${variant.label}）', (tester) async {
        final expanded = ValueNotifier(true);
        final floor = ValueNotifier(7);
        await pumpUi(
          tester,
          _toolbar(expanded: expanded, floor: floor),
          variant: variant,
        );
        expectNoUiException(tester);
        expect(find.byIcon(AppIcons.floor), findsOneWidget);

        expanded.value = false;
        await tester.pumpAndSettle();
        expectNoUiException(tester);
        expect(find.text('7 / 42'), findsOneWidget);
      });
    }

    testUi('收起状态机：展开 64 高、收起 44 高', (tester) async {
      final expanded = ValueNotifier(true);
      final floor = ValueNotifier(1);
      await pumpUi(tester, _toolbar(expanded: expanded, floor: floor));
      final bar = find.byType(ReadingToolbar);
      final expandedHeight = tester.getSize(bar).height;
      expect(expandedHeight, ReadingToolbar.expandedHeight + 34); // 含底部安全区

      expanded.value = false;
      await tester.pumpAndSettle();
      expect(
        tester.getSize(bar).height,
        ReadingToolbar.collapsedHeight + 34,
      );

      expanded.value = true;
      await tester.pumpAndSettle();
      expect(tester.getSize(bar).height, expandedHeight);
    });

    testUi('点击楼层按钮打开跳转、回复可点', (tester) async {
      final log = <String>[];
      await pumpUi(
        tester,
        _toolbar(
          expanded: ValueNotifier(true),
          floor: ValueNotifier(3),
          log: log,
        ),
      );
      await tester.tap(find.byIcon(AppIcons.floor));
      await tester.tap(find.text('回复'));
      expect(log, ['floor', 'reply']);
      await expectUiAccessibility(tester, textContrast: false);
    });
  });

  group('楼层跳转半屏', () {
    Widget host(List<int> jumps, {bool history = true}) => Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => showFloorJumpSheet(
              context,
              total: 42,
              current: 5,
              onJump: jumps.add,
              onBackToLastRead: () => jumps.add(-1),
              onBackToBeforeJump: history ? () => jumps.add(-2) : null,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    testUi('无效输入留在输入框并提示范围，有效输入跳转并关闭', (tester) async {
      final jumps = <int>[];
      await pumpUi(tester, host(jumps));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '99');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();
      expect(jumps, isEmpty);
      expect(find.byType(FloorJumpSheet), findsOneWidget);
      expect(find.textContaining('1'), findsWidgets);
      expect(find.textContaining('42'), findsWidgets);

      await tester.enterText(find.byType(TextField), '12');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();
      expect(jumps, [12]);
      expect(find.byType(FloorJumpSheet), findsNothing);
    });

    testUi('没有跳转历史时不显示「回到跳转前」', (tester) async {
      await pumpUi(tester, host([], history: false));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('回到上次阅读位置'), findsOneWidget);
      expect(find.text('回到跳转前'), findsNothing);
    });

    testUi('滑块对读屏支持上下轻扫 ±1 楼', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpUi(tester, host([]));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final node = tester.getSemantics(find.bySemanticsLabel('跳转到楼层').last);
      final data = node.getSemanticsData();
      expect(data.hasAction(SemanticsAction.increase), isTrue);
      expect(data.hasAction(SemanticsAction.decrease), isTrue);
      handle.dispose();
    });

    for (final variant in [...UiVariant.portrait, ...UiVariant.landscape]) {
      testUi('半屏不溢出（${variant.label}）', (tester) async {
        await pumpUi(tester, host([]), variant: variant);
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expectNoUiException(tester);
      });
    }
  });
}
