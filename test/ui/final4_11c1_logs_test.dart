import 'dart:convert';
import 'dart:io';

import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/app_logs_page.dart';
import 'package:fluxdo/services/log/log_writer.dart';
import 'package:fluxdo/widgets/logs/error_detail_sheet.dart';
import 'package:path/path.dart' as p;

import 'support/ui_harness.dart';

// 第 11 批 · 11c-1（补充稿 36 / 37）：应用日志的搜索模式、错误详情半屏。
// 日志写在临时目录里，剪贴板用假通道，不发任何网络请求。

/// 一条错误日志的堆栈：多行，复制时要完整带走
const stack = '#0 a (x.dart:1)\n#1 b (y.dart:2)\n#2 c (z.dart:3)';

/// 测试用日志条目：错误 / CF 验证 / 普通信息 / 警告
List<Map<String, Object?>> sampleEntries() => [
  {
    'timestamp': '2026-10-30T10:00:00.000Z',
    'level': 'error',
    'type': 'general',
    'tag': 'Net',
    'message': 'connection timeout',
    'error': 'DioException [connection timeout]',
    'errorType': 'DioException',
    'stackTrace': stack,
    'appVersion': '0.5.0',
    'foo': 'bar',
  },
  {
    'timestamp': '2026-10-30T09:30:00.000Z',
    'level': 'info',
    'type': 'cf_challenge',
    'message': 'CF Challenge passed',
  },
  {
    'timestamp': '2026-10-30T09:00:00.000Z',
    'level': 'info',
    'type': 'general',
    'message': 'Warm up finished',
  },
  {
    'timestamp': '2026-10-30T08:30:00.000Z',
    'level': 'warning',
    'type': 'general',
    'message': 'Challenge retry scheduled',
  },
];

void main() {
  setUpAll(loadUiFonts);

  late Directory sandbox;
  String? clipboard;

  setUp(() async {
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
    sandbox = Directory.systemTemp.createTempSync('logs_final4_');
    await LogWriter.initForTesting(Directory(p.join(sandbox.path, 'logs')));
    final file = await LogWriter.getLogFile();
    file.writeAsStringSync('${sampleEntries().map(jsonEncode).join('\n')}\n');
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    await LogWriter.resetForTesting();
    sandbox.deleteSync(recursive: true);
  });

  Future<void> openLogs(WidgetTester tester) async {
    await tester.runAsync(() async {
      await pumpUi(tester, const AppLogsPage(), settle: false);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> enterSearch(WidgetTester tester) async {
    await tester.tap(find.byIcon(AppIcons.search));
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('36 应用日志 · 搜索', () {
    testUi('点搜索进入搜索模式：标题换成搜索框，右上「取消」，级别筛选保留', (tester) async {
      await openLogs(tester);
      expect(find.text('应用日志'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await enterSearch(tester);
      // 输入框替换标题；返回在左、取消在右
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('应用日志'), findsNothing);
      expect(find.text('取消'), findsOneWidget);
      // 级别筛选胶囊都还在
      for (final label in ['错误', '警告', '信息', '调试']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expectNoUiException(tester);
    });

    testUi('输入关键字过滤日志，条数跟着变；清除后恢复', (tester) async {
      await openLogs(tester);
      expect(find.text('4 条'), findsOneWidget);
      await enterSearch(tester);

      await tester.enterText(find.byType(TextField), 'challenge');
      await tester.pump(const Duration(milliseconds: 300));
      // 「CF Challenge passed」「Challenge retry scheduled」两条命中（不分大小写）
      expect(find.text('CF Challenge passed'), findsWidgets);
      expect(find.text('Challenge retry scheduled'), findsWidgets);
      expect(find.text('Warm up finished'), findsNothing);
      expect(find.text('[Net] DioException'), findsNothing);
      expect(find.text('2 条'), findsOneWidget);

      // 级别筛选和搜索叠加：只看「警告」
      await tester.tap(find.text('警告'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Challenge retry scheduled'), findsWidgets);
      expect(find.text('CF Challenge passed'), findsNothing);
      expect(find.text('1 条'), findsOneWidget);

      // 关键字没有命中：给一句人话
      await tester.enterText(find.byType(TextField), 'zzzz-no-hit');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('无匹配日志'), findsOneWidget);

      // 点输入框里的清除钮：关键字清空，列表回到「仅警告」
      await tester.tap(find.byIcon(AppIcons.cancelCircle));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Challenge retry scheduled'), findsWidgets);
      expect(find.text('1 条'), findsOneWidget);
    });

    testUi('点「取消」退出搜索模式并清掉关键字', (tester) async {
      await openLogs(tester);
      await enterSearch(tester);
      await tester.enterText(find.byType(TextField), 'challenge');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('2 条'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(TextField), findsNothing);
      expect(find.text('应用日志'), findsOneWidget);
      expect(find.text('4 条'), findsOneWidget);
    });

    testUi('日志内容用系统等宽字体', (tester) async {
      await openLogs(tester);
      final style = tester
          .widget<Text>(find.text('CF Challenge passed').first)
          .style!;
      final mono = tester.element(find.byType(AppLogsPage)).tokens.text.monoUrl;
      expect(style.fontFamily, mono.fontFamily);
      expect(style.fontFamilyFallback, mono.fontFamilyFallback);
      expect(style.fontSize, 13);
    });
  });

  group('37 应用日志 · 错误详情', () {
    Future<void> openErrorDetail(WidgetTester tester) async {
      await openLogs(tester);
      await tester.tap(find.text('[Net] DioException').first);
      // 第一帧建路由，之后半屏才开始上滑
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));
    }

    testUi('错误行点开是「错误详情」半屏：类型 / 级别 / 时间 / 版本 + 说明 + 堆栈', (tester) async {
      await openErrorDetail(tester);
      expect(find.byType(AppSheetScaffold), findsOneWidget);
      expect(find.text('错误详情'), findsOneWidget);
      for (final key in ['类型', '级别', '时间', '版本']) {
        expect(find.text(key), findsOneWidget, reason: key);
      }
      expect(find.text('DioException'), findsOneWidget);
      expect(find.text('ERROR'), findsOneWidget);
      expect(find.text('0.5.0'), findsOneWidget);
      // 说明文字（消息 + 原始错误）
      expect(find.textContaining('connection timeout'), findsWidgets);
      // 堆栈完整显示，附加字段也在
      expect(find.text('堆栈'), findsOneWidget);
      expect(find.text(stack), findsOneWidget);
      expect(find.text('附加字段'), findsOneWidget);
      expect(find.text('foo: bar'), findsOneWidget);
      expect(find.text('复制错误类型和完整堆栈'), findsOneWidget);
      expectNoUiException(tester);
    });

    testUi('底部「复制」复制 = 错误类型 + 完整堆栈', (tester) async {
      await openErrorDetail(tester);
      await tester.tap(find.text('复制错误类型和完整堆栈'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(clipboard, 'DioException\n$stack');
      await tester.pump(const Duration(seconds: 4));
    });

    testUi('右上「复制」和底部复制的是同一份文字', (tester) async {
      await openErrorDetail(tester);
      // 右上头行里的复制图标是第一个（底部按钮里还有一个）
      await tester.tap(find.byIcon(AppIcons.copy).first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(clipboard, 'DioException\n$stack');
      await tester.pump(const Duration(seconds: 4));
    });

    testUi('非错误日志仍是原来的详情，不叫「错误详情」', (tester) async {
      await openLogs(tester);
      await tester.tap(find.text('Warm up finished').first);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AppSheetScaffold), findsOneWidget);
      expect(find.text('错误详情'), findsNothing);
      expect(find.text('复制错误类型和完整堆栈'), findsNothing);
    });

    test('复制内容：类型一行 + 堆栈原样；缺类型退回说明；没堆栈只复制类型', () {
      expect(
        buildErrorCopyText(errorType: 'StateError', stackTrace: stack),
        'StateError\n$stack',
      );
      // 堆栈末尾的空行不带走，中间原样
      expect(
        buildErrorCopyText(errorType: 'E', stackTrace: '#0 a\n\n#1 b\n\n'),
        'E\n#0 a\n\n#1 b',
      );
      expect(
        buildErrorCopyText(stackTrace: stack, fallbackTitle: '出错了'),
        '出错了\n$stack',
      );
      expect(buildErrorCopyText(errorType: 'E', stackTrace: '  '), 'E');
      expect(buildErrorCopyText(errorType: 'E'), 'E');
    });
  });
}
