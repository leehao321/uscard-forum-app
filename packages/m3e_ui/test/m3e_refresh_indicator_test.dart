import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_ui/m3e_ui.dart';

void main() {
  testWidgets('顶部拖动不重建列表子树(树形状稳定)', (tester) async {
    final controller = ScrollController();
    final listKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: M3eRefreshIndicator(
            onRefresh: () async {},
            child: ListView.builder(
              key: listKey,
              controller: controller,
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: 100,
              itemBuilder: (_, i) => SizedBox(height: 40, child: Text('$i')),
            ),
          ),
        ),
      ),
    );
    final elementBefore = listKey.currentContext!;

    // 在顶部轻拖(触发 drag 状态翻转)再松手取消。
    await tester.drag(find.byType(ListView), const Offset(0, 30));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // 树形状稳定:同一个 Element,列表未被拆掉重建。
    expect(listKey.currentContext, same(elementBefore));

    // 先滚下去,再在中途来回拖,位置不能被重置。
    controller.jumpTo(400);
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -50));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(controller.offset, greaterThan(300));
    expect(listKey.currentContext, same(elementBefore));
  });

  testWidgets('完整下拉刷新流程', (tester) async {
    var refreshed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: M3eRefreshIndicator(
            onRefresh: () async => refreshed++,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [for (var i = 0; i < 20; i++) SizedBox(height: 40, child: Text('$i'))],
            ),
          ),
        ),
      ),
    );
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200)); // snap
    await tester.pump(const Duration(seconds: 1)); // refresh 完成
    await tester.pumpAndSettle();
    expect(refreshed, 1);
    expect(tester.takeException(), isNull);
  });

  group('展示层（Figma 下拉刷新态：24pt 圆环，列表下移一条 48 高悬停带）', () {
    Widget host(
      ThemeData theme,
      Future<void> Function() onRefresh, {
      GlobalKey<M3eRefreshIndicatorState>? refreshKey,
    }) => MaterialApp(
      theme: theme,
      home: Scaffold(
        body: M3eRefreshIndicator(
          key: refreshKey,
          onRefresh: onRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              for (var i = 0; i < 20; i++)
                SizedBox(height: 40, child: Text('row$i')),
            ],
          ),
        ),
      ),
    );

    // 圆环指示器（排除 Material 自己可能带的其他进度条）
    final ring = find.byWidgetPredicate(
      (w) => w is CircularProgressIndicator && w.strokeWidth == 2,
    );

    testWidgets('下拉显示 24pt 圆环，不再是系统菊花也不是 M3E 圆片', (tester) async {
      await tester.pumpWidget(
        host(ThemeData(platform: TargetPlatform.iOS), () async {}),
      );
      expect(ring, findsNothing);

      final g = await tester.startGesture(
        tester.getCenter(find.byType(ListView)),
      );
      await g.moveBy(const Offset(0, 120));
      await tester.pump();
      expect(ring, findsOneWidget);
      expect(tester.getSize(ring), const Size(24, 24));
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(find.byType(LoadingSpinner), findsNothing);

      await g.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(ring, findsNothing);
    });

    testWidgets('刷新回调只触发一次；刷新中圆环居中在 48 高悬停带里、列表下移 48，完成后回位', (
      tester,
    ) async {
      final completer = Completer<void>();
      var refreshed = 0;
      await tester.pumpWidget(
        host(ThemeData(platform: TargetPlatform.iOS), () {
          refreshed++;
          return completer.future;
        }),
      );
      final rowTop = tester.getTopLeft(find.text('row0')).dy;
      await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200)); // snap
      // 等松手后的回弹走完（刷新还没结束，转圈动画不会静止，不能 pumpAndSettle）
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(refreshed, 1);
      expect(ring, findsOneWidget);
      // 圆环 24 直径，居中在顶部 48 高的悬停带里
      expect(tester.getSize(ring), const Size(24, 24));
      expect(tester.getCenter(ring).dy, closeTo(24, 0.5));
      // 列表内容整体下移一条悬停带，指示器不压在行上
      expect(tester.getTopLeft(find.text('row0')).dy, closeTo(rowTop + 48, 0.5));

      completer.complete();
      await tester.pumpAndSettle();
      expect(ring, findsNothing);
      expect(tester.getTopLeft(find.text('row0')).dy, closeTo(rowTop, 0.5));
      expect(refreshed, 1);
    });

    testWidgets('关闭 M3E 开关也是同一个圆环', (tester) async {
      await tester.pumpWidget(
        host(
          ThemeData(
            platform: TargetPlatform.iOS,
            extensions: const [M3eFlags(enabled: false)],
          ),
          () async {},
        ),
      );
      final g = await tester.startGesture(
        tester.getCenter(find.byType(ListView)),
      );
      await g.moveBy(const Offset(0, 120));
      await tester.pump();
      expect(ring, findsOneWidget);
      expect(find.byType(RefreshIndicator), findsNothing);
      await g.up();
      await tester.pumpAndSettle();
    });

    testWidgets('Android 与 iOS 一样：同一个圆环，没有 M3E 圆片、没有原生 RefreshIndicator', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(ThemeData(platform: TargetPlatform.android), () async {}),
      );
      expect(find.byType(RefreshIndicator), findsNothing);
      final g = await tester.startGesture(
        tester.getCenter(find.byType(ListView)),
      );
      await g.moveBy(const Offset(0, 120));
      await tester.pump();
      expect(ring, findsOneWidget);
      expect(tester.getSize(ring), const Size(24, 24));
      expect(find.byType(LoadingSpinner), findsNothing);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      await g.up();
      await tester.pumpAndSettle();
    });

    testWidgets('GlobalKey.show() 可编程触发，刷新期间同样下移并显示圆环', (tester) async {
      final key = GlobalKey<M3eRefreshIndicatorState>();
      final completer = Completer<void>();
      var refreshed = 0;
      await tester.pumpWidget(
        host(ThemeData(platform: TargetPlatform.iOS), () {
          refreshed++;
          return completer.future;
        }, refreshKey: key),
      );
      final rowTop = tester.getTopLeft(find.text('row0')).dy;
      final future = key.currentState!.show();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      expect(refreshed, 1);
      expect(ring, findsOneWidget);
      expect(tester.getTopLeft(find.text('row0')).dy, closeTo(rowTop + 48, 0.5));
      completer.complete();
      await future;
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('row0')).dy, closeTo(rowTop, 0.5));
      expect(refreshed, 1);
    });
  });
}
