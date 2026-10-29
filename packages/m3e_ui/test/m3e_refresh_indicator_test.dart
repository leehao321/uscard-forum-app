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

  group('iOS 展示层', () {
    Widget host(ThemeData theme, Future<void> Function() onRefresh) =>
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: M3eRefreshIndicator(
              onRefresh: onRefresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  for (var i = 0; i < 20; i++)
                    SizedBox(height: 40, child: Text('$i')),
                ],
              ),
            ),
          ),
        );

    testWidgets('iOS 下拉显示 CupertinoActivityIndicator,不出现 M3E 圆片', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(ThemeData(platform: TargetPlatform.iOS), () async {}),
      );
      expect(find.byType(CupertinoActivityIndicator), findsNothing);

      final g = await tester.startGesture(
        tester.getCenter(find.byType(ListView)),
      );
      await g.moveBy(const Offset(0, 120));
      await tester.pump();
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(find.byType(LoadingSpinner), findsNothing);

      await g.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
    });

    testWidgets('iOS 刷新回调只触发一次,刷新中显示转圈,完成后收起', (tester) async {
      final completer = Completer<void>();
      var refreshed = 0;
      await tester.pumpWidget(
        host(ThemeData(platform: TargetPlatform.iOS), () {
          refreshed++;
          return completer.future;
        }),
      );
      await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200)); // snap
      await tester.pump(const Duration(milliseconds: 200));
      expect(refreshed, 1);
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);

      completer.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(refreshed, 1);
    });

    testWidgets('iOS 下关闭 M3E 开关也走 Cupertino 展示层', (tester) async {
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
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(find.byType(RefreshIndicator), findsNothing);
      await g.up();
      await tester.pumpAndSettle();
    });

    testWidgets('Android 仍是 M3E 圆片(LoadingSpinner),无 Cupertino', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(ThemeData(platform: TargetPlatform.android), () async {}),
      );
      final g = await tester.startGesture(
        tester.getCenter(find.byType(ListView)),
      );
      await g.moveBy(const Offset(0, 120));
      await tester.pump();
      expect(find.byType(LoadingSpinner), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      await g.up();
      await tester.pumpAndSettle();
    });

    testWidgets('Android 关闭 M3E 开关仍回退原生 RefreshIndicator', (tester) async {
      await tester.pumpWidget(
        host(
          ThemeData(
            platform: TargetPlatform.android,
            extensions: const [M3eFlags(enabled: false)],
          ),
          () async {},
        ),
      );
      expect(find.byType(RefreshIndicator), findsOneWidget);
    });

    testWidgets('iOS 上 GlobalKey.show() 可编程触发', (tester) async {
      final key = GlobalKey<M3eRefreshIndicatorState>();
      var refreshed = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: M3eRefreshIndicator(
              key: key,
              onRefresh: () async => refreshed++,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [for (var i = 0; i < 20; i++) Text('$i')],
              ),
            ),
          ),
        ),
      );
      final future = key.currentState!.show();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(seconds: 1));
      await future;
      await tester.pumpAndSettle();
      expect(refreshed, 1);
    });
  });
}
