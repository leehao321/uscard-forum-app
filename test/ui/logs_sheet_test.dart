import 'dart:convert';
import 'dart:io';

import 'package:common_ui/common_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/app_logs_page.dart';
import 'package:fluxdo/services/log/log_writer.dart';
import 'package:path/path.dart' as p;

import 'support/ui_harness.dart';

// 0.4.0 收尾 B：日志页「通用日志 / 生命周期」详情改成半屏（和请求详情同一版式）。
// 日志写在临时目录里，不发任何网络请求。

void main() {
  setUpAll(loadUiFonts);

  late Directory sandbox;

  setUp(() async {
    sandbox = Directory.systemTemp.createTempSync('logs_sheet_');
    await LogWriter.initForTesting(Directory(p.join(sandbox.path, 'logs')));
    final file = await LogWriter.getLogFile();
    final entries = [
      {
        'timestamp': '2026-10-30T10:00:00.000Z',
        'level': 'error',
        'type': 'general',
        'tag': 'Demo',
        'message': '加载失败',
        'error': 'SocketException',
        'stackTrace': '#0 main (file.dart:1)',
      },
      {
        'timestamp': '2026-10-30T09:00:00.000Z',
        'level': 'info',
        'type': 'lifecycle',
        'event': 'app_start',
        'message': '应用启动',
        'appVersion': '0.4.0',
      },
    ];
    file.writeAsStringSync('${entries.map(jsonEncode).join('\n')}\n');
  });

  tearDown(() async {
    await LogWriter.resetForTesting();
    sandbox.deleteSync(recursive: true);
  });

  testUi('通用日志详情是半屏，带复制和关闭', (tester) async {
    await tester.runAsync(() async {
      await pumpUi(tester, const AppLogsPage(), settle: false);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('加载失败'), findsWidgets);

    await tester.tap(find.textContaining('加载失败').first);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AppSheetScaffold), findsOneWidget);
    expect(find.text('[Demo]'), findsWidgets);
    expect(find.textContaining('#0 main'), findsOneWidget);
    expectNoUiException(tester);
  });

  testUi('生命周期详情是半屏', (tester) async {
    await tester.runAsync(() async {
      await pumpUi(tester, const AppLogsPage(), settle: false);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('应用启动').first);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AppSheetScaffold), findsOneWidget);
    expect(find.text('0.4.0'), findsWidgets);
    expectNoUiException(tester);
  });
}
