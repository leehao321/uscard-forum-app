import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/main.dart' show buildAppThemeForTest;
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:m3e_ui/m3e_ui.dart';

// iOS 适配层共用组件的整页渲染检查：真实字体与图标、浅色 / 深色、
// 1.0 / 1.3 倍系统字号。任何溢出（RenderFlex overflow 等）都会作为异常
// 让用例失败。设置环境变量 SHOTS_DIR 时把截图写到该目录，人工核对对齐。
// 全部是本地夹具，不碰网络。

const _seed = Color(0xFF4B73E6);
const _size = Size(390, 844);

Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final bytes = await File(path).readAsBytes();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }

  await load('MiSans', 'assets/fonts/MiSansVF.ttf');
  // Symbols 的 fontFamily 带包前缀
  final pkg = File('.dart_tool/package_config.json').readAsStringSync();
  final root = RegExp(r'"rootUri":\s*"([^"]*material_symbols_icons[^"]*)"')
      .firstMatch(pkg)!
      .group(1)!;
  final dir = Uri.parse(root).toFilePath();
  await load(
    'packages/material_symbols_icons/MaterialSymbolsRounded',
    '$dir/lib/fonts/MaterialSymbolsRounded.ttf',
  );
}

ThemeData _theme(Brightness brightness) => buildAppThemeForTest(
  ColorScheme.fromSeed(seedColor: _seed, brightness: brightness),
  ThemeState(
    mode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    seedColor: _seed,
    fontFamily: AppFontFamily.miSans,
  ),
  platform: TargetPlatform.iOS,
);

Widget _sectionHeader(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
  child: Text(
    text,
    style: Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  ),
);

Widget _settingsScreen() => Builder(
  builder: (context) => Scaffold(
    appBar: AppBar(title: const Text('设置')),
    body: ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        _sectionHeader(context, '通用'),
        SegmentedCardGroup(
          children: [
            ListTile(
              leading: const Icon(Symbols.palette_rounded),
              title: const Text('外观'),
              trailing: const Icon(Symbols.chevron_right_rounded),
              onTap: () {},
            ),
            ListTile(
              leading: const Icon(Symbols.menu_book_rounded),
              title: const Text('阅读'),
              subtitle: const Text('字号、行距、盘古之白'),
              trailing: const Icon(Symbols.chevron_right_rounded),
              onTap: () {},
            ),
            SwitchListTile.adaptive(
              secondary: const Icon(Symbols.blur_on_rounded),
              title: const Text('毛玻璃效果'),
              value: true,
              onChanged: (_) {},
            ),
          ],
        ),
        _sectionHeader(context, '长文本'),
        SegmentedCardGroup(
          children: [
            ListTile(
              title: const Text('一个很长很长的设置项名称，用来检查截断和换行'),
              subtitle: const Text('副标题说明也比较长，看看会不会溢出、被裁掉一半，或者和右侧开关挤在一起'),
              trailing: Switch.adaptive(value: false, onChanged: (_) {}),
            ),
          ],
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 300,
          child: AlertDialog(
            title: const Text('删除字体'),
            content: const Text('删除后用到这个字体的地方会回到系统字体。'),
            actions: [
              TextButton(onPressed: () {}, child: const Text('取消')),
              TextButton(onPressed: () {}, child: const Text('删除')),
            ],
          ),
        ),
      ],
    ),
  ),
);

Widget _sheetScreen() => Scaffold(
  body: Align(
    alignment: Alignment.bottomCenter,
    child: AppSheetScaffold(
      title: '高级筛选',
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final t in ['版块', '最近活跃', '只看这些标签'])
            ListTile(
              title: Text(t),
              trailing: const Icon(Symbols.chevron_right_rounded),
            ),
        ],
      ),
    ),
  ),
);

Future<void> _shot(WidgetTester tester, GlobalKey key, String name) async {
  final dir = Platform.environment['SHOTS_DIR'];
  if (dir == null) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(_loadFonts);

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 1.3]) {
      final label = '${brightness.name}@${scale}x';
      for (final (name, screen) in [
        ('settings', _settingsScreen),
        ('sheet', _sheetScreen),
      ]) {
        testWidgets('iOS $name 不溢出（$label）', (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = _size;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final key = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: _theme(brightness),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: child!,
                ),
                home: screen(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await _shot(tester, key, 'ios_${name}_$label');
        });
      }
    }
  }
}
