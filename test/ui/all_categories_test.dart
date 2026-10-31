import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/category.dart';
import 'package:fluxdo/pages/home/all_categories_sheet.dart';
import 'package:fluxdo/providers/category_provider.dart';

import 'support/ui_harness.dart';

// 0.4.0「全部分类」半屏（Figma 补充页 44:1951）：分类分组的父分类行带话题数和展开
// chevron，子分类缩进 32；话题数取站点分类数据的 topic_count，没有就不显示。
// 数据全是假的，不请求论坛。

Category _cat(
  int id,
  String name, {
  int? parent,
  int? topicCount,
}) => Category.fromJson({
  'id': id,
  'name': name,
  'slug': 'c$id',
  'color': '0088CC',
  'text_color': 'FFFFFF',
  if (parent != null) 'parent_category_id': parent,
  if (topicCount != null) 'topic_count': topicCount,
});

List<Override> _overrides(List<Category> cats) => [
  categoriesProvider.overrideWith((ref) async => cats),
  tagsProvider.overrideWith((ref) async => const ['chase']),
];

Future<void> _open(
  WidgetTester tester,
  List<Category> cats, {
  UiVariant variant = UiVariant.lightDefault,
}) async {
  await pumpUi(
    tester,
    Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => showAllCategoriesSheet(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
    variant: variant,
    overrides: _overrides(cats),
  );
  await tester.tap(find.text('open'));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUpAll(loadUiFonts);

  final cats = [
    _cat(10, '玩卡', topicCount: 21000),
    _cat(11, '信用卡', parent: 10, topicCount: 14000),
    _cat(12, '银行账户', parent: 10, topicCount: 3120),
    _cat(20, '旅行', topicCount: 8402),
    _cat(21, '航司', parent: 20, topicCount: 12),
    _cat(30, '败家', topicCount: 4037),
  ];

  test('Category.fromJson 读 topic_count，没有就是 null', () {
    expect(_cat(1, 'a', topicCount: 5).topicCount, 5);
    expect(_cat(2, 'b').topicCount, isNull);
  });

  testUi('父分类行：话题数 + 展开 chevron；没有子分类的没有 chevron', (tester) async {
    await _open(tester, cats);
    expect(tester.takeException(), isNull);
    expect(find.text('玩卡'), findsOneWidget);
    expect(find.text('2.1 万'), findsOneWidget);
    expect(find.text('8,402'), findsOneWidget);
    expect(find.text('4,037'), findsOneWidget);
    // 子分类默认收起；有子分类的两行是 chevron-right，没有子分类的「败家」没有
    expect(find.text('信用卡'), findsNothing);
    expect(find.byIcon(AppIcons.chevronRight), findsNWidgets(2));
    expect(find.byIcon(AppIcons.chevronDown), findsNothing);
  });

  testUi('点父分类展开子分类（缩进 32、话题数在行尾），再点收起', (tester) async {
    await _open(tester, cats);
    await tester.tap(find.text('玩卡'));
    await tester.pump();
    expect(find.text('信用卡'), findsOneWidget);
    expect(find.text('银行账户'), findsOneWidget);
    expect(find.text('1.4 万'), findsOneWidget);
    expect(find.text('3,120'), findsOneWidget);
    expect(find.byIcon(AppIcons.chevronDown), findsOneWidget);
    // 父行文字左缘 = 半屏内边距 20 + 12；子行再缩进（32）
    final parentLeft = tester.getTopLeft(find.text('玩卡')).dx;
    final childLeft = tester.getTopLeft(find.text('信用卡')).dx;
    expect(childLeft - parentLeft, 20);
    await tester.tap(find.text('玩卡'));
    await tester.pump();
    expect(find.text('信用卡'), findsNothing);
  });

  testUi('站点分类数据里没有 topic_count 时不显示话题数', (tester) async {
    await _open(tester, [_cat(10, '玩卡'), _cat(30, '败家')]);
    expect(find.text('玩卡'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^\d')), findsNothing);
  });

  testUi('页眉右侧是「编辑分类条」', (tester) async {
    await _open(tester, cats);
    expect(find.text('编辑分类条'), findsOneWidget);
  });

  for (final variant in [
    ...UiVariant.portrait,
    ...UiVariant.landscape,
  ]) {
    testUi('不溢出（${variant.label}）', (tester) async {
      await _open(tester, cats, variant: variant);
      await tester.tap(find.text('玩卡'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await uiShot(tester, 'all_categories_${variant.label}');
    });
  }
}
