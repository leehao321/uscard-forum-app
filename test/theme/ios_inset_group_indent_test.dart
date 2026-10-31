import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/main.dart' show buildAppThemeForTest;
import 'package:m3e_ui/m3e_ui.dart';

// 分组列表的分隔线：上一行带前导图标时缩进到文字起点，否则缩进到行内边距
// （v2：行 pad 0 12）。0.4.0 起全平台一套（计划 P2）。

ThemeData _theme(TargetPlatform platform) =>
    buildAppThemeForTest(Brightness.light, platform: platform);

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('${platform.name}：上一行有前导图标时分隔线对齐文字起点，没有时对齐内边距', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme(platform),
          home: Scaffold(
            body: SegmentedCardGroup(
              children: [
                const ListTile(
                  leading: Icon(AppIcons.palette),
                  title: Text('带图标'),
                ),
                SwitchListTile.adaptive(
                  secondary: const Icon(AppIcons.speed),
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
      // 组内图标 20（M2）：12 + 20 + 12 = 44
      expect(dividers.map((d) => d.indent), [44, 44, 12]);
      expect(tester.getSize(find.byIcon(AppIcons.palette)).width, 20);

      final groupLeft = tester.getTopLeft(find.byType(SegmentedCardGroup)).dx;
      expect(tester.getTopLeft(find.text('带图标')).dx - groupLeft, 44);
      expect(tester.getTopLeft(find.text('不带图标')).dx - groupLeft, 12);
    });
  }

  testWidgets('调用点显式 separatorIndent 优先', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme(TargetPlatform.iOS),
        home: const Scaffold(
          body: SegmentedCardGroup(
            separatorIndent: 0,
            children: [
              ListTile(leading: Icon(AppIcons.palette), title: Text('a')),
              ListTile(title: Text('b')),
            ],
          ),
        ),
      ),
    );
    final divider = tester.widget<Divider>(find.byType(Divider));
    expect(divider.indent, 0);
  });
}
