import 'dart:async';

import 'package:common_ui/common_ui.dart';
import 'package:flutter/cupertino.dart' show CupertinoDatePicker;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/search_filter.dart';
import 'package:fluxdo/models/search_result.dart';
import 'package:fluxdo/pages/search_page.dart';
import 'package:fluxdo/providers/category_provider.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/theme_provider.dart'
    show sharedPreferencesProvider;
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:fluxdo/services/preloaded_data_service.dart';
import 'package:fluxdo/widgets/search/search_filter_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fixtures.dart';
import 'support/ui_harness.dart';

// 补充稿 07 / 08「高级筛选 · 自定义时间」：时间一行选「自定义」后，在时间组下展开
// 开始 / 结束日期两行；日期用系统日期选择器选；选了以后两行显示所选日期，点「应用筛选」后
// 按这个范围过滤搜索。服务是假的，不联网。

String _fmt(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

List<Override> _overrides(SharedPreferences prefs) => [
  sharedPreferencesProvider.overrideWithValue(prefs),
  categoriesProvider.overrideWith((ref) async => fixtureCategories()),
  tagsProvider.overrideWith((ref) async => ['chase', 'csr', 'amex']),
];

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

/// 记下每次搜索的查询串的假服务
class _FakeService implements DiscourseService {
  final queries = <String>[];

  @override
  Future<List<String>> getRecentSearches() async => const [];

  @override
  Future<SearchResult> search({
    required String query,
    int page = 1,
    String? typeFilter,
  }) async {
    queries.add(query);
    return SearchResult.fromJson({
      'posts': [
        {
          'id': 1,
          'topic_id': 1001,
          'username': 'amex_plat',
          'avatar_template': '',
          'created_at': fixtureTime(const Duration(hours: 1)),
          'like_count': 0,
          'blurb': '这是 chase 的结果摘要',
          'post_number': 1,
        },
      ],
      'topics': [
        {
          'id': 1001,
          'title': 'Chase Sapphire Reserve 新开卡奖励 125k',
          'slug': 'csr',
          'category_id': 11,
          'tags': const [],
          'posts_count': 9,
          'views': 1200,
          'closed': false,
          'archived': false,
        },
      ],
      'users': const [],
      'grouped_search_result': <String, dynamic>{},
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  setUpAll(loadUiFonts);

  /// 打开高级筛选半屏；[applied] 记下点「应用筛选」带回的筛选
  Future<void> openPanel(
    WidgetTester tester, {
    SearchFilter filter = const SearchFilter(),
    UiVariant variant = UiVariant.lightDefault,
    required List<SearchFilter> applied,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await pumpUi(
      tester,
      Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => SizedBox(
                height: 700,
                child: SearchFilterPanel(
                  filter: filter,
                  onFilterChanged: applied.add,
                  hideInType: true,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
      variant: variant,
      overrides: _overrides(prefs),
      settle: false,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  bool selected(WidgetTester tester, String label) => tester
      .widget<FilterPill>(
        find.descendant(
          of: find.byType(SearchFilterPanel),
          matching: find.widgetWithText(FilterPill, label),
        ),
      )
      .selected;

  final rows = find.byKey(const ValueKey('custom-date-rows'));
  Finder valueOf(String row) => find.byKey(ValueKey('date-row-$row-value'));
  String textOf(WidgetTester tester, Finder f) =>
      tester.widget<Text>(f).data!;

  group('自定义入口（补充稿 07）', () {
    for (final brightness in Brightness.values) {
      testUi('选「自定义」后展开开始 / 结束日期两行，都显示「选择日期」（${brightness.name}）', (
        tester,
      ) async {
        final applied = <SearchFilter>[];
        await openPanel(
          tester,
          applied: applied,
          variant: UiVariant(brightness, 1, UiDevice.pro),
        );
        expectNoUiException(tester);
        // 还没选自定义：没有日期行，「不限」是选中的
        expect(rows, findsNothing);
        expect(selected(tester, '不限'), isTrue);
        expect(selected(tester, '自定义'), isFalse);

        await tester.tap(find.text('自定义'));
        await tester.pump(const Duration(milliseconds: 300));
        expectNoUiException(tester);
        expect(rows, findsOneWidget);
        expect(selected(tester, '自定义'), isTrue);
        expect(selected(tester, '不限'), isFalse);
        // 两行：开始日期 / 结束日期，值是占位「选择日期」
        expect(
          find.descendant(of: rows, matching: find.text('开始日期')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: rows, matching: find.text('结束日期')),
          findsOneWidget,
        );
        expect(textOf(tester, valueOf('start')), '选择日期');
        expect(textOf(tester, valueOf('end')), '选择日期');
        // 行高 48、在时间那一组胶囊的下面、分类那一段的上面
        final startRow = tester.getSize(
          find.byKey(const ValueKey('date-row-start')),
        );
        expect(startRow.height, 48);
        expect(
          tester.getTopLeft(rows).dy,
          greaterThan(tester.getBottomLeft(find.text('自定义')).dy),
        );
        expect(
          tester.getBottomLeft(rows).dy,
          lessThan(tester.getTopLeft(find.text('分类')).dy),
        );
        // 卡片是 surface/elevated 圆角 12
        final colors = tester.element(rows).tokens.colors;
        final card = tester.widget<DecoratedBox>(
          find
              .descendant(of: rows, matching: find.byType(DecoratedBox))
              .first,
        );
        expect(
          (card.decoration as BoxDecoration).color,
          colors.surfaceElevated,
        );
        expect(
          (card.decoration as BoxDecoration).borderRadius,
          BorderRadius.circular(12),
        );
        await uiShot(tester, 'search_custom_date_entry_${brightness.name}');
        await _unmount(tester);
      });
    }

    testUi('点开始日期弹系统日期选择器，确定后只写开始日期；结束日期不受影响', (tester) async {
      final applied = <SearchFilter>[];
      await openPanel(tester, applied: applied);
      await tester.tap(find.text('自定义'));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byKey(const ValueKey('date-row-start')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(CupertinoDatePicker), findsOneWidget);
      await tester.tap(find.text('确定'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(CupertinoDatePicker), findsNothing);

      final today = DateUtils.dateOnly(DateTime.now());
      expect(textOf(tester, valueOf('start')), _fmt(today));
      expect(textOf(tester, valueOf('end')), '选择日期');

      await tester.tap(find.text('应用筛选'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(applied.single.afterDate, today);
      expect(applied.single.beforeDate, isNull);
      await _unmount(tester);
    });

    testUi('选了日期后，切回「最近一周」收起日期行并改成最近 7 天；再点「自定义」带着这个范围展开', (
      tester,
    ) async {
      final applied = <SearchFilter>[];
      await openPanel(tester, applied: applied);
      await tester.tap(find.text('自定义'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(rows, findsOneWidget);

      await tester.tap(find.text('最近一周'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(rows, findsNothing, reason: '选预设档位后日期行收起');
      expect(selected(tester, '最近一周'), isTrue);
      expect(selected(tester, '自定义'), isFalse);

      await tester.tap(find.text('自定义'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(rows, findsOneWidget);
      final today = DateUtils.dateOnly(DateTime.now());
      expect(
        textOf(tester, valueOf('start')),
        _fmt(today.subtract(const Duration(days: 7))),
      );
      expect(textOf(tester, valueOf('end')), _fmt(today));
      expect(selected(tester, '最近一周'), isFalse);

      await tester.tap(find.text('不限'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(rows, findsNothing);
      await tester.tap(find.text('应用筛选'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(applied.single.afterDate, isNull);
      expect(applied.single.beforeDate, isNull);
      await _unmount(tester);
    });
  });

  group('自定义已选（补充稿 08）', () {
    final range = SearchFilter(
      afterDate: DateTime(2025, 1, 1),
      beforeDate: DateTime(2025, 6, 30),
    );

    for (final brightness in Brightness.values) {
      testUi('已有自定义范围：打开就是展开状态，两行显示所选日期（${brightness.name}）', (
        tester,
      ) async {
        final applied = <SearchFilter>[];
        await openPanel(
          tester,
          filter: range,
          applied: applied,
          variant: UiVariant(brightness, 1, UiDevice.pro),
        );
        expectNoUiException(tester);
        expect(rows, findsOneWidget);
        expect(selected(tester, '自定义'), isTrue);
        expect(selected(tester, '不限'), isFalse);
        expect(textOf(tester, valueOf('start')), '2025-01-01');
        expect(textOf(tester, valueOf('end')), '2025-06-30');
        // 已选日期用 meta 色，和占位同色（Figma 里值都是 meta）
        final colors = tester.element(rows).tokens.colors;
        expect(
          tester.widget<Text>(valueOf('start')).style!.color,
          colors.textMeta,
        );
        await uiShot(tester, 'search_custom_date_selected_${brightness.name}');
        await _unmount(tester);
      });
    }

    testUi('点结束日期：选择器从当前结束日期起步；确定后带回范围，开始日期保持不变', (tester) async {
      final applied = <SearchFilter>[];
      await openPanel(tester, filter: range, applied: applied);
      await tester.tap(find.byKey(const ValueKey('date-row-end')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      final picker = tester.widget<CupertinoDatePicker>(
        find.byType(CupertinoDatePicker),
      );
      expect(picker.initialDateTime, DateTime(2025, 6, 30));
      // 结束日期不能早于开始日期、不能晚于今天
      expect(picker.minimumDate, DateTime(2025, 1, 1));
      expect(
        picker.maximumDate,
        DateUtils.dateOnly(DateTime.now()),
      );
      await tester.tap(find.text('确定'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(textOf(tester, valueOf('end')), '2025-06-30');
      await tester.tap(find.text('应用筛选'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(applied.single.afterDate, DateTime(2025, 1, 1));
      expect(applied.single.beforeDate, DateTime(2025, 6, 30));
      await _unmount(tester);
    });

    testUi('点开始日期：不能晚于结束日期', (tester) async {
      final applied = <SearchFilter>[];
      await openPanel(tester, filter: range, applied: applied);
      await tester.tap(find.byKey(const ValueKey('date-row-start')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      final picker = tester.widget<CupertinoDatePicker>(
        find.byType(CupertinoDatePicker),
      );
      expect(picker.initialDateTime, DateTime(2025, 1, 1));
      expect(picker.maximumDate, DateTime(2025, 6, 30));
      // 最上面那个是选择器半屏自己的关闭按钮
      await tester.tap(find.byType(AppCloseButton).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      // 关闭选择器不改日期
      expect(textOf(tester, valueOf('start')), '2025-01-01');
      await _unmount(tester);
    });

    testUi('应用筛选后搜索按这个范围过滤：查询串带 after: / before:', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      PreloadedDataService().debugSeed(siteSettings: const {});
      final service = _FakeService();
      await pumpUi(
        tester,
        const SearchPage(initialQuery: 'chase'),
        overrides: [
          ..._overrides(prefs),
          discourseServiceProvider.overrideWithValue(service),
        ],
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 800));
      expect(service.queries, hasLength(1));
      expect(service.queries.single, isNot(contains('after:')));

      // 时间胶囊 → 高级筛选 → 自定义，只设结束日期（今天），再应用
      await tester.tap(find.text('时间'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.tap(find.text('自定义'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('date-row-start')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('确定'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('应用筛选'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 800));

      final today = _fmt(DateUtils.dateOnly(DateTime.now()));
      expect(service.queries, hasLength(2), reason: '应用筛选后重新搜索一次');
      expect(service.queries.last, contains('chase'));
      expect(service.queries.last, contains('after:$today'));
      expect(service.queries.last, isNot(contains('before:')));
      await _unmount(tester);
    });
  });
}
