import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/local_notification_service.dart'
    show navigatorKey;
import 'package:fluxdo/services/toast_service.dart';

import 'support/ui_harness.dart';

// 0.4.0 M2：v2 Toast（设计说明 §4）。44 高胶囊，13 字；在工具栏上方
// 16（默认按 64 高工具栏 + 底部安全区估算）；出现时朗读，不抢焦点。

Future<void> _pump(WidgetTester tester, Brightness brightness) async {
  final view = tester.view;
  view.devicePixelRatio = 3;
  view.physicalSize = UiDevice.proMax.size * 3;
  final p = UiDevice.proMax.padding * 3;
  final fake = FakeViewPadding(
    left: p.left,
    top: p.top,
    right: p.right,
    bottom: p.bottom,
  );
  view.padding = fake;
  view.viewPadding = fake;
  view.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(view.reset);
  addTearDown(view.platformDispatcher.clearAllTestValues);
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      theme: uiTheme(Brightness.light),
      darkTheme: uiTheme(Brightness.dark),
      home: const Scaffold(body: SizedBox.expand()),
    ),
  );
}

void main() {
  setUpAll(loadUiFonts);

  for (final b in Brightness.values) {
    testUi('Toast：44 高胶囊、13 字，在工具栏上方 16；出现时朗读（${b.name}）', (tester) async {
      await _pump(tester, b);
      ToastService.showSuccess('链接已复制');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final capsule = find.ancestor(
        of: find.text('链接已复制'),
        matching: find.byType(CapsuleSurface),
      );
      expect(capsule, findsOneWidget);
      final rect = tester.getRect(capsule);
      expect(rect.height, 44);
      // 底部安全区 34 + 工具栏 64 + 16
      expect(956 - rect.bottom, closeTo(34 + 64 + 16, 0.5));
      final text = tester.widget<Text>(find.text('链接已复制'));
      expect(text.style!.fontSize, 13);
      expect(
        tester.takeAnnouncements().map((a) => a.message),
        contains('链接已复制'),
      );
      expectNoUiException(tester);

      // 3 秒后自动消失
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('链接已复制'), findsNothing);
    });
  }

  testUi('下载进度占着底部槽位时，普通提示上移让位', (tester) async {
    await _pump(tester, Brightness.light);
    final handle = ToastService.showDownload('report.pdf');
    await tester.pump(const Duration(milliseconds: 300));
    handle.updateProgress(0.5);
    ToastService.showInfo('已加入稍后阅读');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final download = tester.getRect(find.text('report.pdf'));
    final info = tester.getRect(find.text('已加入稍后阅读'));
    expect(info.center.dy, lessThan(download.center.dy - 40));
    expect(find.text('50%'), findsOneWidget);
    handle.complete('已保存');
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('已保存'), findsNothing);
  });
}
