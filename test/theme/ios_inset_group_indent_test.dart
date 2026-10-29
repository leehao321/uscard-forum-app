import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/main.dart' show buildAppThemeForTest;
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:m3e_ui/m3e_ui.dart';

// iOS 分组列表的分隔线：上一行带前导图标时缩进到文字起点，否则缩进到内边距。

const _seed = Color(0xFF4B73E6);

ThemeData _theme(TargetPlatform platform) => buildAppThemeForTest(
  ColorScheme.fromSeed(seedColor: _seed),
  const ThemeState(mode: ThemeMode.light, seedColor: _seed),
  platform: platform,
);

void main() {
  testWidgets('上一行有前导图标时分隔线对齐文字起点，没有时对齐内边距', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme(TargetPlatform.iOS),
        home: Scaffold(
          body: SegmentedCardGroup(
            children: [
              const ListTile(
                leading: Icon(Symbols.palette_rounded),
                title: Text('带图标'),
              ),
              SwitchListTile.adaptive(
                secondary: const Icon(Symbols.blur_on_rounded),
                title: const Text('开关带图标'),
                value: true,
                onChanged: (_) {},
              ),
              const ListTile(title: Text('不带图标')),
              const ListTile(title: Text('最后一行')),
            ],
          ),
        ),
      ),
    );

    final dividers = tester.widgetList<Divider>(find.byType(Divider)).toList();
    expect(dividers.map((d) => d.indent), [56, 56, 16]);

    // 56 正好是带图标行文字的左缘
    final titleLeft = tester.getTopLeft(find.text('带图标')).dx;
    final groupLeft = tester.getTopLeft(find.byType(SegmentedCardGroup)).dx;
    expect(titleLeft - groupLeft, 56);
  });

  testWidgets('调用点显式 separatorIndent 优先', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme(TargetPlatform.iOS),
        home: const Scaffold(
          body: SegmentedCardGroup(
            separatorIndent: 0,
            children: [
              ListTile(leading: Icon(Symbols.palette_rounded), title: Text('a')),
              ListTile(title: Text('b')),
            ],
          ),
        ),
      ),
    );
    final divider = tester.widget<Divider>(find.byType(Divider));
    expect(divider.indent, 0);
  });

  testWidgets('Android 不变：没有分隔线', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme(TargetPlatform.android),
        home: const Scaffold(
          body: SegmentedCardGroup(
            children: [
              ListTile(leading: Icon(Symbols.palette_rounded), title: Text('a')),
              ListTile(title: Text('b')),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(Divider), findsNothing);
  });
}
