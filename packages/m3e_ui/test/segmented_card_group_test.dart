import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_ui/m3e_ui.dart';

const _children = [
  SizedBox(height: 44, child: Text('a')),
  SizedBox(height: 44, child: Text('b')),
  SizedBox(height: 44, child: Text('c')),
];

ThemeData _iosTheme({SegmentedCardGroupStyle? style}) => ThemeData(
  platform: TargetPlatform.iOS,
  extensions: [
    style ??
        const SegmentedCardGroupStyle(
          insetGrouped: true,
          radius: 10,
          separatorIndent: 16,
          separatorColor: Color(0xFFFF0000),
          cellColor: Color(0xFF00FF00),
        ),
  ],
);

Widget _host(ThemeData theme, Widget child) => MaterialApp(
  theme: theme,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Finder _inGroup(Finder matching) =>
    find.descendant(of: find.byType(SegmentedCardGroup), matching: matching);

/// 组内作为"缝隙"的 SizedBox(高度 = gap 且无 child)。
Finder _gapBoxes(double gap) => _inGroup(
  find.byWidgetPredicate(
    (w) => w is SizedBox && w.height == gap && w.child == null,
  ),
);

void main() {
  group('SegmentedCardGroup 分段形态(默认 / Android)', () {
    testWidgets('无扩展:3 个独立块 + 2 条 gap,无分隔线', (tester) async {
      await tester.pumpWidget(
        _host(
          ThemeData(platform: TargetPlatform.android),
          const SegmentedCardGroup(children: _children),
        ),
      );
      expect(_inGroup(find.byType(Material)), findsNWidgets(3));
      expect(_gapBoxes(3), findsNWidgets(2));
      expect(_inGroup(find.byType(Divider)), findsNothing);

      // 圆角:首块上大下小,末块上小下大
      final materials = tester
          .widgetList<Material>(_inGroup(find.byType(Material)))
          .toList();
      expect(
        materials[0].shape,
        const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(20),
            bottom: Radius.circular(5),
          ),
        ),
      );
      expect(
        materials[2].shape,
        const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(5),
            bottom: Radius.circular(20),
          ),
        ),
      );
    });

    testWidgets('insetGrouped=false 的扩展不改变分段形态,cellColor 不生效', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          _iosTheme(
            style: const SegmentedCardGroupStyle(
              insetGrouped: false,
              cellColor: Color(0xFF00FF00),
            ),
          ),
          const SegmentedCardGroup(children: _children),
        ),
      );
      expect(_inGroup(find.byType(Material)), findsNWidgets(3));
      expect(_gapBoxes(3), findsNWidgets(2));
      expect(_inGroup(find.byType(Divider)), findsNothing);
      for (final m in tester.widgetList<Material>(
        _inGroup(find.byType(Material)),
      )) {
        expect(m.color, isNot(const Color(0xFF00FF00)));
      }
    });

    testWidgets('自定义 gap / 圆角参数仍然生效', (tester) async {
      await tester.pumpWidget(
        _host(
          ThemeData(platform: TargetPlatform.android),
          const SegmentedCardGroup(
            gap: 7,
            outerRadius: 30,
            innerRadius: 2,
            children: _children,
          ),
        ),
      );
      expect(_gapBoxes(7), findsNWidgets(2));
      final first = tester
          .widgetList<Material>(_inGroup(find.byType(Material)))
          .first;
      expect(
        first.shape,
        const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(30),
            bottom: Radius.circular(2),
          ),
        ),
      );
    });
  });

  group('SegmentedCardGroup inset-grouped(iOS)', () {
    testWidgets('单个圆角容器 + 2 条发丝分隔线,无 gap', (tester) async {
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(_iosTheme(), const SegmentedCardGroup(children: _children)),
      );

      expect(_inGroup(find.byType(Material)), findsOneWidget);
      expect(_gapBoxes(3), findsNothing);

      final dividers = tester
          .widgetList<Divider>(_inGroup(find.byType(Divider)))
          .toList();
      expect(dividers, hasLength(2));
      for (final d in dividers) {
        expect(d.thickness, closeTo(0.5, 1e-9)); // 1 / devicePixelRatio
        expect(d.height, closeTo(0.5, 1e-9));
        expect(d.indent, 16);
        expect(d.color, const Color(0xFFFF0000));
      }

      final material = tester.widget<Material>(
        _inGroup(find.byType(Material)),
      );
      expect(material.clipBehavior, Clip.antiAlias);
      expect(material.color, const Color(0xFF00FF00));
      expect(
        material.shape,
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );

      // 容器只包住内容:3 × 44 + 2 × 0.5
      expect(
        tester.getSize(_inGroup(find.byType(Material))).height,
        closeTo(133, 1e-6),
      );
    });

    testWidgets('发丝线厚度随 devicePixelRatio 变化', (tester) async {
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(_iosTheme(), const SegmentedCardGroup(children: _children)),
      );
      final d = tester.widget<Divider>(_inGroup(find.byType(Divider)).first);
      expect(d.thickness, closeTo(1 / 3, 1e-9));
    });

    testWidgets('构造参数 separatorIndent 覆盖主题,显式 color 覆盖 cellColor', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          _iosTheme(),
          const SegmentedCardGroup(
            separatorIndent: 56,
            color: Color(0xFF0000FF),
            children: _children,
          ),
        ),
      );
      for (final d in tester.widgetList<Divider>(
        _inGroup(find.byType(Divider)),
      )) {
        expect(d.indent, 56);
      }
      expect(
        tester.widget<Material>(_inGroup(find.byType(Material))).color,
        const Color(0xFF0000FF),
      );
    });

    testWidgets('未指定 separatorColor / cellColor 时取 outlineVariant / cardTheme', (
      tester,
    ) async {
      final theme = _iosTheme(
        style: const SegmentedCardGroupStyle(insetGrouped: true),
      );
      await tester.pumpWidget(
        _host(theme, const SegmentedCardGroup(children: _children)),
      );
      expect(
        tester.widget<Divider>(_inGroup(find.byType(Divider)).first).color,
        theme.colorScheme.outlineVariant,
      );
      expect(
        tester.widget<Material>(_inGroup(find.byType(Material))).color,
        theme.colorScheme.surfaceContainerLow,
      );
    });

    testWidgets('单个子项没有分隔线', (tester) async {
      await tester.pumpWidget(
        _host(
          _iosTheme(),
          const SegmentedCardGroup(children: [SizedBox(height: 44)]),
        ),
      );
      expect(_inGroup(find.byType(Divider)), findsNothing);
      expect(_inGroup(find.byType(Material)), findsOneWidget);
    });

    testWidgets('子项 ListTile 仍可点击', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        _host(
          _iosTheme(),
          SegmentedCardGroup(
            children: [
              ListTile(title: const Text('x'), onTap: () => tapped++),
              const ListTile(title: Text('y')),
            ],
          ),
        ),
      );
      await tester.tap(find.text('x'));
      expect(tapped, 1);
    });
  });

  group('SegmentedCardItem(懒加载列表用)', () {
    Widget items(int count) => Column(
      children: [
        for (var i = 0; i < count; i++)
          SegmentedCardItem(
            index: i,
            count: count,
            child: const SizedBox(height: 44),
          ),
      ],
    );

    testWidgets('inset-grouped:仅首上/尾下圆角,非末项带分隔线', (tester) async {
      await tester.pumpWidget(_host(_iosTheme(), items(3)));
      final materials = tester
          .widgetList<Material>(
            find.descendant(
              of: find.byType(SegmentedCardItem),
              matching: find.byType(Material),
            ),
          )
          .toList();
      expect(materials, hasLength(3));
      expect(
        materials[0].shape,
        const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
        ),
      );
      expect(
        materials[1].shape,
        const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      );
      expect(
        materials[2].shape,
        const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(10)),
        ),
      );
      expect(find.byType(Divider), findsNWidgets(2));
    });

    testWidgets('默认形态不变,无分隔线', (tester) async {
      await tester.pumpWidget(_host(ThemeData(), items(3)));
      expect(find.byType(Divider), findsNothing);
    });
  });

  test('SegmentedCardGroupStyle:copyWith / lerp / 相等性', () {
    const a = SegmentedCardGroupStyle(
      insetGrouped: true,
      radius: 10,
      separatorIndent: 16,
    );
    expect(a, const SegmentedCardGroupStyle(insetGrouped: true));
    expect(
      a.hashCode,
      const SegmentedCardGroupStyle(insetGrouped: true).hashCode,
    );
    expect(a.copyWith(radius: 14).radius, 14);
    expect(a.copyWith(radius: 14).insetGrouped, isTrue);

    const b = SegmentedCardGroupStyle(
      insetGrouped: false,
      radius: 20,
      separatorIndent: 32,
    );
    final mid = a.lerp(b, 0.5);
    expect(mid.radius, closeTo(15, 1e-9));
    expect(mid.separatorIndent, closeTo(24, 1e-9));
    expect(a.lerp(b, 0.4).insetGrouped, isTrue);
    expect(a.lerp(b, 0.6).insetGrouped, isFalse);
    expect(a.lerp(null, 0.5), same(a));
  });
}
