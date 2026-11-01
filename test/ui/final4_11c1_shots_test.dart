import 'dart:convert';
import 'dart:io';

import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/app_logs_page.dart';
import 'package:fluxdo/pages/diagnostics_page.dart';
import 'package:fluxdo/pages/my_browser_page.dart';
import 'package:fluxdo/pages/reading_settings_page.dart';
import 'package:fluxdo/services/log/log_writer.dart';
import 'package:dio/io.dart' show IOHttpClientAdapter;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/final4_11c1_support.dart';
import 'support/ui_harness.dart';

// 第 11 批 · 11c-1 出图（补充稿 33–42）。设 SHOTS_DIR 才落盘（约定放到
// shots/final4），不设置时只做「不抛异常」的检查。全部用假服务，不联网。
// 浅 / 深各一张：`编号_名称_light.png` / `编号_名称_dark.png`。

const _light = UiVariant(Brightness.light, 1.0, UiDevice.pro);
const _dark = UiVariant(Brightness.dark, 1.0, UiDevice.pro);

/// 测试环境没有 SF Mono / Menlo，等宽字会画成方块；出图时借系统自带的等宽字体
/// 顶上 token 里的第一个等宽字体名（只影响截图，找不到字体文件就不管）
Future<void> _loadMonoStandIn() async {
  for (final path in const [
    r'C:\Windows\Fonts\consola.ttf',
    '/System/Library/Fonts/Menlo.ttc',
  ]) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    final loader = FontLoader('SF Mono')
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
    return;
  }
}

void main() {
  setUpAll(() async {
    await loadUiFonts();
    await _loadMonoStandIn();
  });

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

  // —— 36 / 37：应用日志（示例数据，写进临时目录）——
  group('应用日志', () {
    late Directory sandbox;

    setUp(() async {
      sandbox = Directory.systemTemp.createTempSync('logs_shots_');
      await LogWriter.initForTesting(Directory(p.join(sandbox.path, 'logs')));
      final file = await LogWriter.getLogFile();
      final entries = <Map<String, Object?>>[
        {
          'timestamp': '示例时间',
          'level': 'error',
          'type': 'network',
          'tag': 'Net',
          'message': '示例数据：connection timeout，请求未在限定时间内完成。',
          'errorType': 'DioException',
          'stackTrace':
              '#0  <sample frame> (package:app/…)\n'
              '#1  <sample frame> (package:dio/…)\n'
              '#2  <sample frame> (dart:async/…)\n'
              '#3  <sample frame> (dart:async/…)',
          'appVersion': '示例版本',
        },
        {
          'timestamp': '示例时间',
          'level': 'info',
          'type': 'cf_challenge',
          'message': '=== CF Challenge Log Started ===',
        },
        {
          'timestamp': '示例时间',
          'level': 'info',
          'type': 'cf_challenge',
          'message': 'CF Challenge passed',
        },
      ];
      file.writeAsStringSync('${entries.map(jsonEncode).join('\n')}\n');
    });

    tearDown(() async {
      await LogWriter.resetForTesting();
      sandbox.deleteSync(recursive: true);
    });

    Future<void> openLogs(WidgetTester tester, UiVariant variant) async {
      await tester.runAsync(() async {
        await pumpUi(
          tester,
          const AppLogsPage(),
          variant: variant,
          settle: false,
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump(const Duration(milliseconds: 300));
    }

    for (final (variant, suffix) in [(_light, 'light'), (_dark, 'dark')]) {
      testUi('36 应用日志 · 搜索（$suffix）', (tester) async {
        await openLogs(tester, variant);
        await tester.tap(find.byIcon(AppIcons.search));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.enterText(find.byType(TextField), 'CF Challenge');
        await tester.pump(const Duration(milliseconds: 300));
        // 类型选「CF 验证」，和稿里最后一个高亮胶囊一致
        await tester.tap(find.text('全部'));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('CF 验证'));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 400));
        expectNoUiException(tester);
        await uiShot(tester, '36_应用日志搜索_$suffix');
      });

      testUi('37 应用日志 · 错误详情（$suffix）', (tester) async {
        await openLogs(tester, variant);
        await tester.tap(find.text('[Net] DioException').first);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('错误详情'), findsOneWidget);
        expectNoUiException(tester);
        await uiShot(tester, '37_应用日志错误详情_$suffix');
      });
    }
  });

  // —— 38：网页浏览首页 ——
  for (final (variant, suffix) in [(_light, 'light'), (_dark, 'dark')]) {
    testUi('38 网页浏览（$suffix）', (tester) async {
      final (_, overrides) = await fakeStore();
      await pumpUi(
        tester,
        const MyBrowserPage(),
        variant: variant,
        overrides: overrides,
      );
      expectNoUiException(tester);
      await uiShot(tester, '38_网页浏览_$suffix');
    });
  }

  // —— 39–42：AI（示例数据）——
  group('AI', () {
    PromptPreset image(
      int i,
      String name,
      String icon,
      String ratio, [
      List<String> tags = const [],
    ]) => PromptPreset(
      id: 'img_$i',
      type: PromptType.image,
      name: name,
      iconRaw: icon,
      promptTemplate: 't',
      aspectRatio: ratio,
      tags: tags,
      sortOrder: i,
      builtIn: true,
    );
    PromptPreset text(int i, String name, String icon) => PromptPreset(
      id: 'txt_$i',
      type: PromptType.text,
      name: name,
      iconRaw: icon,
      promptTemplate: 't',
      sortOrder: i,
      builtIn: true,
    );

    final builtIns = [
      image(0, '示例图像一', 'image_outlined', '16:9', ['封面']),
      image(1, '示例图像二', 'brush_outlined', '1:1', ['插画']),
      image(2, '示例图像三', 'emoji_emotions_outlined', '4:3', ['漫画', '幽默']),
      image(3, '示例图像四', 'share_outlined', '1:1', ['分享']),
      image(4, '示例图像五', 'draw_outlined', '16:9', ['信息图', '手绘']),
      image(5, '示例图像六', 'crop_square_outlined', '1:1', ['极简']),
      image(6, '示例图像七', 'palette_outlined', '4:3', ['水彩']),
      text(0, '示例文本一', 'summarize_outlined'),
      text(1, '示例文本二', 'translate_outlined'),
      text(2, '示例文本三', 'format_list_bulleted'),
      text(3, '示例文本四', 'lightbulb_outlined'),
    ];

    Future<List<Override>> aiOverrides() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      return [
        aiSharedPreferencesProvider.overrideWithValue(prefs),
        builtInPresetsProvider.overrideWithValue(builtIns),
        aiDioAdapterFactoryProvider.overrideWithValue(IOHttpClientAdapter.new),
      ];
    }

    for (final (variant, suffix) in [(_light, 'light'), (_dark, 'dark')]) {
      testUi('39 AI · 会话记录 · 空（$suffix）', (tester) async {
        await pumpUi(
          tester,
          const AiChatHistoryPage(),
          variant: variant,
          overrides: await aiOverrides(),
        );
        expectNoUiException(tester);
        await uiShot(tester, '39_AI会话记录空_$suffix');
      });

      testUi('40 AI · 快捷词管理 · 图像（$suffix）', (tester) async {
        await pumpUi(
          tester,
          const PromptPresetsPage(),
          variant: variant,
          overrides: await aiOverrides(),
        );
        expectNoUiException(tester);
        await uiShot(tester, '40_AI快捷词管理图像_$suffix');
      });

      testUi('41 AI · 快捷词管理 · 文本（$suffix）', (tester) async {
        await pumpUi(
          tester,
          const PromptPresetsPage(initialType: PromptType.text),
          variant: variant,
          overrides: await aiOverrides(),
        );
        expectNoUiException(tester);
        await uiShot(tester, '41_AI快捷词管理文本_$suffix');
      });

      testUi('42 AI · 高级设置（$suffix）', (tester) async {
        await pumpUi(
          tester,
          const AiAdvancedSettingsPage(),
          variant: variant,
          overrides: await aiOverrides(),
        );
        expectNoUiException(tester);
        await uiShot(tester, '42_AI高级设置_$suffix');
      });
    }
  });
}
