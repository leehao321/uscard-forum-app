import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/services/app_ui_scale.dart';
import 'package:fluxdo/settings/definitions/appearance_defs.dart';
import 'package:fluxdo/settings/settings_model.dart';
import 'package:fluxdo/settings/settings_renderer.dart';
import 'package:fluxdo/widgets/settings/font_choice_card.dart';
import 'package:fluxdo/widgets/settings/ui_scale_segmented.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/app_harness.dart';

Widget _themed(Widget child, {Brightness brightness = Brightness.light, double width = 360}) {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.blue, brightness: brightness);
  return MaterialApp(
    theme: ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      cardTheme: CardThemeData(color: scheme.surfaceContainerLow),
    ),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: width, child: child),
      ),
    ),
  );
}

void main() {
  group('字体卡片', () {
    Widget card({
      String selected = 'system',
      ValueChanged<String>? onSelected,
      VoidCallback? onImport,
      Brightness brightness = Brightness.light,
    }) => _themed(
      FontChoiceCard<String>(
        selected: selected,
        choices: const [
          FontChoice(value: 'system', label: '系统默认'),
          FontChoice(value: 'misans', label: 'MiSans', fontFamily: 'MiSans'),
        ],
        onSelected: onSelected ?? (_) {},
        importTitle: '导入字体',
        importSubtitle: '从手机或 iCloud 选择 .ttf、.otf 文件',
        onImport: onImport ?? () {},
      ),
      brightness: brightness,
    );

    testWidgets('选项和导入在同一张 16 圆角的卡片里', (tester) async {
      await tester.pumpWidget(card());
      final material = tester.widget<Material>(
        find.descendant(of: find.byType(FontChoiceCard<String>), matching: find.byType(Material)).first,
      );
      expect(
        (material.shape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(16),
      );
      expect(material.clipBehavior, Clip.antiAlias, reason: '行的水波纹不能把圆角顶出去');
      // 选项行和导入行都在这一张卡片里，没有第二张
      expect(
        find.descendant(of: find.byType(FontChoiceCard<String>), matching: find.text('系统默认')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(FontChoiceCard<String>), matching: find.text('导入字体')),
        findsOneWidget,
      );
    });

    testWidgets('没有单选按钮，选中的右侧打勾，只有一个勾', (tester) async {
      await tester.pumpWidget(card(selected: 'misans'));
      expect(find.byType(Radio<String>), findsNothing);
      expect(find.byType(RadioListTile<String>), findsNothing);
      expect(find.byIcon(Icons.check), findsOneWidget);

      final checkX = tester.getCenter(find.byIcon(Icons.check)).dx;
      final cardRight = tester.getRect(find.byType(FontChoiceCard<String>)).right;
      expect(cardRight - checkX, lessThan(40), reason: '勾在右侧');
      // 勾和 MiSans 同一行
      expect(
        tester.getCenter(find.byIcon(Icons.check)).dy,
        closeTo(tester.getCenter(find.text('MiSans')).dy, 1),
      );
      final check = tester.widget<Icon>(find.byIcon(Icons.check));
      final scheme = Theme.of(tester.element(find.byIcon(Icons.check))).colorScheme;
      expect(check.color, scheme.primary);
    });

    testWidgets('所有行的标题从同一个位置开始', (tester) async {
      await tester.pumpWidget(card());
      final startX = tester.getTopLeft(find.text('系统默认')).dx;
      expect(tester.getTopLeft(find.text('MiSans')).dx, startX);
      expect(tester.getTopLeft(find.text('导入字体')).dx, startX);
    });

    testWidgets('导入行上方一条淡分割线，两侧各缩进 16', (tester) async {
      await tester.pumpWidget(card());
      final divider = tester.widget<Divider>(find.byType(Divider));
      expect(divider.height, 1);
      expect(divider.indent, 16);
      expect(divider.endIndent, 16);
      // 分割线在最后一个选项和导入行之间
      final dividerY = tester.getCenter(find.byType(Divider)).dy;
      expect(dividerY, greaterThan(tester.getCenter(find.text('MiSans')).dy));
      expect(dividerY, lessThan(tester.getCenter(find.text('导入字体')).dy));
      final scheme = Theme.of(tester.element(find.byType(Divider))).colorScheme;
      expect(divider.color!.a, lessThan(scheme.outlineVariant.a), reason: '比默认的分割线更淡');
    });

    testWidgets('导入行保留导入图标和右侧箭头', (tester) async {
      await tester.pumpWidget(card());
      expect(find.byIcon(Symbols.upload_file_rounded), findsOneWidget);
      expect(find.byIcon(Symbols.chevron_right_rounded), findsOneWidget);
      final row = tester.getRect(find.byType(FontChoiceCard<String>));
      expect(
        row.right - tester.getCenter(find.byIcon(Symbols.chevron_right_rounded)).dx,
        lessThan(40),
        reason: '箭头在最右',
      );
    });

    testWidgets('点另一个选项：回调；点已选中的：不回调', (tester) async {
      final picked = <String>[];
      await tester.pumpWidget(card(onSelected: picked.add));
      await tester.tap(find.text('系统默认'));
      await tester.pump();
      expect(picked, isEmpty);
      await tester.tap(find.text('MiSans'));
      await tester.pump();
      expect(picked, ['misans']);
    });

    testWidgets('点整行都有反应，不只是文字', (tester) async {
      final picked = <String>[];
      await tester.pumpWidget(card(onSelected: picked.add));
      final row = tester.getRect(find.byType(InkWell).at(1));
      await tester.tapAt(Offset(row.right - 4, row.center.dy));
      await tester.pump();
      expect(picked, ['misans']);
    });

    testWidgets('点导入行：回调', (tester) async {
      var imports = 0;
      await tester.pumpWidget(card(onImport: () => imports++));
      await tester.tap(find.text('从手机或 iCloud 选择 .ttf、.otf 文件'));
      expect(imports, 1);
    });

    testWidgets('选项名用各自的字体显示', (tester) async {
      await tester.pumpWidget(card());
      expect(tester.widget<Text>(find.text('MiSans')).style?.fontFamily, 'MiSans');
      // 没指定字体的选项跟随当前主题的字体，不另设
      final themeFamily = Theme.of(tester.element(find.text('系统默认'))).textTheme.bodyLarge?.fontFamily;
      expect(tester.widget<Text>(find.text('系统默认')).style?.fontFamily, themeFamily);
    });

    testWidgets('读屏：互斥选项，选中状态可读', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(card(selected: 'misans'));
      expect(
        tester.getSemantics(find.text('MiSans')),
        matchesSemantics(
          label: 'MiSans',
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
          hasCheckedState: true,
          isChecked: true,
          isInMutuallyExclusiveGroup: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('深色主题不溢出', (tester) async {
      await tester.pumpWidget(card(brightness: Brightness.dark));
      expect(tester.takeException(), isNull);
    });
  });

  group('界面缩放分段控件', () {
    const options = <ScaleOption>[
      (value: 0.9, label: '紧凑 90%'),
      (value: 1.0, label: '标准 100%'),
      (value: 1.1, label: '舒适 110%'),
      (value: 1.2, label: '放大 120%'),
    ];

    Widget control({
      double value = 1.0,
      ValueChanged<double>? onChanged,
      Brightness brightness = Brightness.light,
      double width = 360,
    }) => _themed(
      Padding(
        padding: const EdgeInsets.all(16),
        child: UiScaleSegmentedControl(
          options: options,
          value: value,
          onChanged: onChanged ?? (_) {},
        ),
      ),
      brightness: brightness,
      width: width,
    );

    /// 把当前值放在 State 里的宿主，点了真的会变
    Widget stateful({double initial = 1.0, List<double>? log}) =>
        _themed(_Holder(initial: initial, log: log));

    testWidgets('四个档位的文字，标准补全了 100%', (tester) async {
      await tester.pumpWidget(control());
      for (final o in options) {
        expect(find.text(o.label), findsOneWidget);
      }
      expect(find.text('标准'), findsNothing);
    });

    testWidgets('没有外框和竖向分隔线', (tester) async {
      await tester.pumpWidget(control());
      final boxes = tester.widgetList<DecoratedBox>(
        find.descendant(of: find.byType(UiScaleSegmentedControl), matching: find.byType(DecoratedBox)),
      );
      for (final box in boxes) {
        expect((box.decoration as BoxDecoration).border, isNull);
      }
      expect(find.byType(VerticalDivider), findsNothing);
      expect(find.byType(SegmentedButton<double>), findsNothing);
    });

    testWidgets('轨道：surfaceContainer，内边距 3，圆角 12', (tester) async {
      await tester.pumpWidget(control());
      final scheme = Theme.of(tester.element(find.byType(UiScaleSegmentedControl))).colorScheme;
      final track = tester.widgetList<DecoratedBox>(
        find.descendant(of: find.byType(UiScaleSegmentedControl), matching: find.byType(DecoratedBox)),
      ).first;
      final decoration = track.decoration as BoxDecoration;
      expect(decoration.color, scheme.surfaceContainer);
      expect(decoration.borderRadius, BorderRadius.circular(12));

      final outer = tester.getRect(find.byType(UiScaleSegmentedControl));
      final thumb = tester.getRect(find.byKey(const ValueKey('ui-scale-thumb')));
      expect(thumb.top - outer.top, 3);
      expect(outer.bottom - thumb.bottom, 3);
    });

    testWidgets('滑块：浅色是白色，9 圆角，带微阴影', (tester) async {
      await tester.pumpWidget(control(value: 1.1));
      final scheme = Theme.of(tester.element(find.byType(UiScaleSegmentedControl))).colorScheme;
      final thumb = tester.widget<DecoratedBox>(
        find.descendant(of: find.byKey(const ValueKey('ui-scale-thumb')), matching: find.byType(DecoratedBox)),
      );
      final decoration = thumb.decoration as BoxDecoration;
      expect(decoration.color, scheme.surfaceContainerLowest);
      expect(decoration.borderRadius, BorderRadius.circular(9));
      expect(decoration.boxShadow, isNotEmpty);
      expect(decoration.boxShadow!.first.blurRadius, lessThanOrEqualTo(6), reason: '微阴影');
      expect(decoration.border, isNull);
    });

    testWidgets('深色主题：滑块比轨道亮一档', (tester) async {
      await tester.pumpWidget(control(brightness: Brightness.dark));
      final scheme = Theme.of(tester.element(find.byType(UiScaleSegmentedControl))).colorScheme;
      final thumb = tester.widget<DecoratedBox>(
        find.descendant(of: find.byKey(const ValueKey('ui-scale-thumb')), matching: find.byType(DecoratedBox)),
      );
      expect((thumb.decoration as BoxDecoration).color, scheme.surfaceContainerHighest);
    });

    testWidgets('滑块停在当前值的那一格，四格等宽', (tester) async {
      for (var i = 0; i < options.length; i++) {
        await tester.pumpWidget(control(value: options[i].value));
        await tester.pumpAndSettle();
        final track = tester.getRect(find.byType(UiScaleSegmentedControl));
        final thumb = tester.getRect(find.byKey(const ValueKey('ui-scale-thumb')));
        final inner = track.width - 6;
        expect(thumb.width, closeTo(inner / 4, 0.01));
        expect(thumb.left - track.left - 3, closeTo(inner / 4 * i, 0.01), reason: '第 $i 格');
      }
    });

    testWidgets('字重：选中 w500，其余 w400', (tester) async {
      await tester.pumpWidget(control(value: 1.1));
      FontWeight? weightOf(String label) =>
          tester.widget<Text>(find.text(label)).style?.fontWeight;
      expect(weightOf('舒适 110%'), FontWeight.w500);
      expect(weightOf('紧凑 90%'), FontWeight.w400);
      expect(weightOf('标准 100%'), FontWeight.w400);
      expect(weightOf('放大 120%'), FontWeight.w400);
    });

    testWidgets('点另一格：回调新值，滑块滑过去', (tester) async {
      final log = <double>[];
      await tester.pumpWidget(stateful(log: log));
      final before = tester.getRect(find.byKey(const ValueKey('ui-scale-thumb'))).left;
      await tester.tap(find.text('放大 120%'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));
      final middle = tester.getRect(find.byKey(const ValueKey('ui-scale-thumb'))).left;
      await tester.pumpAndSettle();
      final after = tester.getRect(find.byKey(const ValueKey('ui-scale-thumb'))).left;
      expect(log, [1.2]);
      expect(middle, greaterThan(before));
      expect(middle, lessThan(after), reason: '是滑过去的，不是跳过去');
    });

    testWidgets('点当前这一格：不回调', (tester) async {
      final log = <double>[];
      await tester.pumpWidget(stateful(log: log));
      await tester.tap(find.text('标准 100%'));
      await tester.pump();
      expect(log, isEmpty);
    });

    testWidgets('系统关了动画：直接到位', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: stateful(),
        ),
      );
      await tester.tap(find.text('放大 120%'));
      await tester.pump();
      final track = tester.getRect(find.byType(UiScaleSegmentedControl));
      final thumb = tester.getRect(find.byKey(const ValueKey('ui-scale-thumb')));
      expect(thumb.right + 3, closeTo(track.right, 0.01));
    });

    testWidgets('窄屏加大字号：文字缩小放得下，不溢出不换行', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(control(width: 300));
      expect(tester.takeException(), isNull);
      for (final o in options) {
        expect(tester.getSize(find.text(o.label)).height, lessThan(60), reason: o.label);
      }
    });

    testWidgets('值不在档位里：不画滑块，也不崩', (tester) async {
      await tester.pumpWidget(control(value: 7.0));
      expect(find.byKey(const ValueKey('ui-scale-thumb')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('读屏：每一格是按钮，选中状态可读', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(control(value: 1.1));
      final semantics = tester.getSemantics(find.text('舒适 110%'));
      expect(semantics.flagsCollection.isSelected, isNotNull);
      expect(semantics.label, '舒适 110%');
      handle.dispose();
    });

    testWidgets('每一格的点击区域不小于 44', (tester) async {
      await tester.pumpWidget(control());
      final track = tester.getRect(find.byType(UiScaleSegmentedControl));
      expect(track.height, greaterThanOrEqualTo(44));
    });
  });

  group('接进设置页', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      AppUiScale.factor.value = 1.0;
    });

    tearDown(() => AppUiScale.factor.value = 1.0);

    List<SettingsGroup> groupsIn(WidgetTester tester) {
      return buildAppearanceGroups(tester.element(find.byType(Scaffold).first));
    }

    Future<void> pumpItem(WidgetTester tester, String id) async {
      await pumpApp(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) {
              final item = buildAppearanceGroups(context)
                  .expand((g) => g.items)
                  .firstWhere((i) => i.id == id);
              return SingleChildScrollView(child: SettingsRenderer(model: item));
            },
          ),
        ),
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
    }

    testWidgets('字体组：一个条目、不分段，导入行不再单独成卡', (tester) async {
      await pumpApp(
        tester,
        const Scaffold(body: SizedBox()),
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      final groups = groupsIn(tester);
      final group = groups.firstWhere((g) => g.items.any((i) => i.id == 'font'));
      expect(group.wrapInCard, isFalse);
      expect(group.items.map((i) => i.id), ['font']);
      expect(
        groups.expand((g) => g.items).any((i) => i.id == 'customFontImport'),
        isFalse,
      );
    });

    testWidgets('搜「导入字体」还能搜到字体这一项', (tester) async {
      await pumpApp(
        tester,
        const Scaffold(body: SizedBox()),
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      final font = groupsIn(tester).expand((g) => g.items).firstWhere((i) => i.id == 'font');
      expect(font.matchesQuery('导入字体'), isTrue);
      expect(font.matchesQuery('字体'), isTrue);
    });

    testWidgets('点 MiSans：主题字体立即切换，对勾跟着走', (tester) async {
      await pumpItem(tester, 'font');
      expect(find.byIcon(Icons.check), findsOneWidget);
      final container = ProviderScope.containerOf(tester.element(find.byType(FontChoiceCard<AppFontFamily>)));
      expect(container.read(themeProvider).fontFamily, AppFontFamily.system);

      await tester.tap(find.text('MiSans'));
      await tester.pumpAndSettle();

      expect(container.read(themeProvider).fontFamily, AppFontFamily.miSans);
      expect(container.read(themeProvider).fontFamilyName, 'MiSans');
      final checkY = tester.getCenter(find.byIcon(Icons.check)).dy;
      expect(checkY, closeTo(tester.getCenter(find.text('MiSans')).dy, 1));
    });

    testWidgets('没导入过字体时只有两个选项', (tester) async {
      await pumpItem(tester, 'font');
      expect(find.text('系统默认'), findsOneWidget);
      expect(find.text('MiSans'), findsOneWidget);
      expect(find.textContaining('自定义'), findsNothing);
    });

    testWidgets('缩放：点「放大 120%」立即生效并保存', (tester) async {
      await pumpItem(tester, 'uiScale');
      expect(find.text('标准 100%'), findsOneWidget);
      // 在分号处断成两行，避免末尾孤零零剩一个字
      final desc = tester.widget<Text>(find.textContaining('放大后可显示的内容更少。'));
      expect(desc.data, '同步调整文字、图标与卡片大小；\n放大后可显示的内容更少。');
      expect(
        desc.data!.replaceAll('\n', ''),
        '同步调整文字、图标与卡片大小；放大后可显示的内容更少。',
      );

      await tester.tap(find.text('放大 120%'));
      await tester.pumpAndSettle();

      expect(AppUiScale.factor.value, 1.2);
      expect(prefs.getDouble(AppUiScale.prefKey), 1.2);
    });

    testWidgets('缩放：已经是某一档时滑块在那一格', (tester) async {
      AppUiScale.factor.value = 0.9;
      await pumpItem(tester, 'uiScale');
      final track = tester.getRect(find.byType(UiScaleSegmentedControl));
      final thumb = tester.getRect(find.byKey(const ValueKey('ui-scale-thumb')));
      expect(thumb.left - track.left, closeTo(3, 0.01));
    });
  });
}

class _Holder extends StatefulWidget {
  const _Holder({required this.initial, this.log});

  final double initial;
  final List<double>? log;

  @override
  State<_Holder> createState() => _HolderState();
}

class _HolderState extends State<_Holder> {
  late double value = widget.initial;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: UiScaleSegmentedControl(
      options: const [
        (value: 0.9, label: '紧凑 90%'),
        (value: 1.0, label: '标准 100%'),
        (value: 1.1, label: '舒适 110%'),
        (value: 1.2, label: '放大 120%'),
      ],
      value: value,
      onChanged: (v) {
        widget.log?.add(v);
        setState(() => value = v);
      },
    ),
  );
}
