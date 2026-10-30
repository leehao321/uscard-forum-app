import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/main.dart' show buildAppThemeForTest;
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 0.4.0 界面测试底座：真实字体与图标、iOS 平台、浅色 / 深色、
// 系统字号倍数、iPhone 尺寸与安全区。任何溢出都会让用例失败。
// 设置环境变量 SHOTS_DIR 时把截图写到该目录（只放 scratchpad，不进仓库）。
//
// 用法：
//   setUpAll(loadUiFonts);
//   for (final v in UiVariant.portrait) {
//     testUi('首页（${v.label}）', (tester) async {
//       await pumpUi(tester, const HomePage(), variant: v);
//       expectNoUiException(tester);
//       await uiShot(tester, 'home_${v.label}');
//     });
//   }

/// iPhone 尺寸预设（逻辑像素），安全区按真机取值
enum UiDevice {
  /// iPhone 16 Pro Max 竖屏
  proMax(Size(440, 956), EdgeInsets.only(top: 62, bottom: 34)),

  /// iPhone 16 Pro 竖屏
  pro(Size(393, 852), EdgeInsets.only(top: 59, bottom: 34)),

  /// iPhone 16 Pro Max 横屏：可用宽 832 ≥ 640，阅读列居中
  landscape(Size(956, 440), EdgeInsets.only(left: 62, right: 62, bottom: 21)),

  /// iPhone 16 Pro 横屏：可用宽 734，仍 ≥ 640
  landscapePro(
    Size(852, 393),
    EdgeInsets.only(left: 59, right: 59, bottom: 21),
  );

  const UiDevice(this.size, this.padding);

  final Size size;
  final EdgeInsets padding;
}

/// 一组渲染条件：明暗 × 系统字号 × 尺寸
class UiVariant {
  const UiVariant(this.brightness, this.textScale, this.device);

  final Brightness brightness;
  final double textScale;
  final UiDevice device;

  String get label => '${brightness.name}_${textScale}x_${device.name}';

  static const scales = [1.0, 1.3, 2.0];

  /// 竖屏全矩阵：浅 / 深 × 1.0 / 1.3 / 2.0 × 440 / 393
  static final portrait = [
    for (final b in Brightness.values)
      for (final s in scales)
        for (final d in [UiDevice.proMax, UiDevice.pro]) UiVariant(b, s, d),
  ];

  /// 横屏：浅 / 深 × 1.0，两种宽度
  static final landscape = [
    for (final b in Brightness.values)
      for (final d in [UiDevice.landscape, UiDevice.landscapePro])
        UiVariant(b, 1.0, d),
  ];

  static const lightDefault = UiVariant(Brightness.light, 1, UiDevice.proMax);
}

/// iOS 平台下的 widget 测试（defaultTargetPlatform 自动设置并复位）
void testUi(
  String description,
  WidgetTesterCallback body, {
  bool skip = false,
}) => testWidgets(
  description,
  body,
  skip: skip,
  variant: TargetPlatformVariant.only(TargetPlatform.iOS),
);

/// 本次进程里已加载的字体 family（自检测试用）
final loadedUiFonts = <String>{};

/// 加载 MiSans 与图标字体，测试截图里才看得到真实字形
Future<void> loadUiFonts() async {
  Future<void> load(String family, String path) async {
    final bytes = await File(path).readAsBytes();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
    loadedUiFonts.add(family);
  }

  await load('MiSans', 'assets/fonts/MiSansVF.ttf');

  // 包里的字体 family 带 packages/<包名>/ 前缀
  final config = File('.dart_tool/package_config.json').readAsStringSync();
  String? packageDir(String name) {
    final root = RegExp(
      '"name":\\s*"$name",\\s*"rootUri":\\s*"([^"]*)"',
    ).firstMatch(config)?.group(1);
    if (root == null) return null;
    final uri = Uri.parse(root);
    // workspace 内的包是相对 .dart_tool 的路径
    return uri.hasScheme
        ? uri.toFilePath()
        : Directory('.dart_tool').uri.resolveUri(uri).toFilePath();
  }

  final symbols = packageDir('material_symbols_icons');
  if (symbols != null) {
    await load(
      'packages/material_symbols_icons/MaterialSymbolsRounded',
      '$symbols/lib/fonts/MaterialSymbolsRounded.ttf',
    );
  }

  final lucide = packageDir('lucide_icons_flutter');
  if (lucide != null) {
    await load('packages/lucide_icons_flutter/Lucide', '$lucide/assets/lucide.ttf');
    final fonts = Directory('$lucide/assets/build_font');
    if (fonts.existsSync()) {
      for (final file in fonts.listSync().whereType<File>()) {
        final name = file.uri.pathSegments.last;
        if (!name.endsWith('.ttf')) continue;
        // LucideVariable-w300.ttf → packages/lucide_icons_flutter/Lucide300
        final weight = RegExp(r'w(\d{3})').firstMatch(name)?.group(1) ?? '';
        await load('packages/lucide_icons_flutter/Lucide$weight', file.path);
      }
    }
  }
}

/// 测试用主题：和应用同一套 v2 装配，字体固定 MiSans（测试里没有系统字体）
ThemeData uiTheme(Brightness brightness) => buildAppThemeForTest(
  brightness,
  platform: TargetPlatform.iOS,
  themeState: ThemeState(
    mode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    fontFamily: AppFontFamily.miSans,
  ),
);

final _boundaryKey = GlobalKey(debugLabel: 'ui_harness_boundary');

/// 按 [variant] 设好尺寸、安全区、字号与明暗，挂上 [child]
///
/// [child] 作为 MaterialApp 的 home；需要 Riverpod 覆盖时传 [overrides]，
/// 需要偏好值时传 [prefs]（每次都会重置 SharedPreferences 的 mock）。
Future<void> pumpUi(
  WidgetTester tester,
  Widget child, {
  UiVariant variant = UiVariant.lightDefault,
  List<Override> overrides = const [],
  Map<String, Object> prefs = const {},
  bool settle = true,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  LocaleSettings.setLocaleSync(AppLocale.zh);

  final view = tester.view;
  const dpr = 3.0;
  view.devicePixelRatio = dpr;
  view.physicalSize = variant.device.size * dpr;
  final p = variant.device.padding * dpr;
  final fake = FakeViewPadding(
    left: p.left,
    top: p.top,
    right: p.right,
    bottom: p.bottom,
  );
  view.padding = fake;
  view.viewPadding = fake;
  view.platformDispatcher.platformBrightnessTestValue = variant.brightness;
  view.platformDispatcher.textScaleFactorTestValue = variant.textScale;
  addTearDown(view.reset);
  addTearDown(view.platformDispatcher.clearAllTestValues);

  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundaryKey,
      child: ProviderScope(
        overrides: overrides,
        child: TranslationProvider(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('zh'),
            supportedLocales: AppLocaleUtils.supportedLocales,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: uiTheme(Brightness.light),
            darkTheme: uiTheme(Brightness.dark),
            home: child,
          ),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

/// 渲染过程中没有异常（RenderFlex 溢出等都会在这里暴露）
void expectNoUiException(WidgetTester tester) {
  expect(tester.takeException(), isNull);
}

/// §9 的三条无障碍 guideline
Future<void> expectUiAccessibility(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  handle.dispose();
}

/// 设置了 SHOTS_DIR 时把当前画面存成 `<SHOTS_DIR>/<name>.png`
Future<void> uiShot(WidgetTester tester, String name) async {
  final dir = Platform.environment['SHOTS_DIR'];
  if (dir == null) return;
  final boundary =
      _boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(dir).createSync(recursive: true);
    File('$dir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}
