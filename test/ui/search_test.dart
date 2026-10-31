import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/search_filter.dart';
import 'package:fluxdo/models/search_result.dart';
import 'package:fluxdo/providers/category_provider.dart';
import 'package:fluxdo/providers/theme_provider.dart'
    show sharedPreferencesProvider;
import 'package:fluxdo/widgets/search/search_filter_panel.dart';
import 'package:fluxdo/widgets/search/search_list_skeleton.dart';
import 'package:fluxdo/widgets/search/search_post_card.dart';
import 'package:fluxdo/widgets/topic/topic_list_skeleton.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fixtures.dart';
import 'support/ui_harness.dart';

// 0.4.0 M6：搜索（设计说明 §5.1「搜索 · 结果与筛选」）。
// 搜索页本身要请求论坛（最近搜索、结果），不拿真站做测试，所以这里只测
// 不联网的部件：结果行、高级筛选半屏、骨架。

SearchPost _post({
  int postNumber = 1,
  String blurb = '',
  String? headline,
  int likes = 0,
}) => SearchPost.fromJson(
  {
    'id': 1,
    'username': 'amex_plat',
    'avatar_template': '',
    'created_at': fixtureTime(const Duration(hours: 3)),
    'like_count': likes,
    'blurb': blurb,
    'post_number': postNumber,
    'topic_title_headline': headline,
  },
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
);

List<Override> _overrides(SharedPreferences prefs) => [
  sharedPreferencesProvider.overrideWithValue(prefs),
  categoriesProvider.overrideWith((ref) async => fixtureCategories()),
  tagsProvider.overrideWith((ref) async => ['chase', 'csr', 'amex']),
];

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  UiVariant variant = UiVariant.lightDefault,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await pumpUi(
    tester,
    Scaffold(body: child),
    variant: variant,
    overrides: _overrides(prefs),
    settle: false,
  );
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

/// 找出文字片段里带 brand 色的部分
List<String> _brandSpans(WidgetTester tester, Color brand) {
  final result = <String>[];
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.style?.color == brand && span.text != null) {
        result.add(span.text!);
      }
      return true;
    });
  }
  return result;
}

void main() {
  setUpAll(loadUiFonts);

  group('搜索结果行', () {
    testUi('命中词用 brand 色，不加底色；楼层 > 1 时摘要前缀 #楼层', (tester) async {
      await _pump(
        tester,
        SearchPostCard(
          post: _post(
            postNumber: 12,
            blurb: '这张卡的 <span class="search-highlight">奖励</span> 要三个月',
            headline: 'Chase <span class="search-highlight">Sapphire</span> 新开卡',
          ),
        ),
      );
      expectNoUiException(tester);
      final brand = tester.element(find.byType(SearchPostCard)).tokens.colors.brandPrimary;
      expect(_brandSpans(tester, brand), containsAll(['奖励', 'Sapphire']));
      // 命中词没有背景色
      for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
        rich.text.visitChildren((span) {
          if (span is TextSpan) expect(span.style?.backgroundColor, isNull);
          return true;
        });
      }
      expect(find.textContaining('#12 '), findsOneWidget);
      await uiShot(tester, 'm6_search_row_light');
      await _unmount(tester);
    });

    testUi('一楼不加前缀；标题最多两行、摘要最多两行', (tester) async {
      await _pump(
        tester,
        SearchPostCard(post: _post(blurb: '很长的摘要 ' * 40)),
      );
      expect(find.textContaining('#1 '), findsNothing);
      final blurb = tester.widget<RichText>(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().startsWith('很长的摘要'),
        ),
      );
      expect(blurb.maxLines, 2);
      await _unmount(tester);
    });

    // Figma 55:3000：标题一行 24 + 摘要两行 32 + 元信息 16，上下 12、间距 8 = 112
    testUi('标题一行、摘要两行时行高 112（Figma 搜索结果行）', (tester) async {
      await _pump(
        tester,
        ListView(
          children: [SearchPostCard(post: _post(blurb: '很长的摘要 ' * 40))],
        ),
        variant: const UiVariant(Brightness.light, 1, UiDevice.pro),
      );
      final h = tester.getSize(find.byType(SearchPostCard)).height;
      expect(h, closeTo(112, 1));
      await _unmount(tester);
    });

    testUi('整行可点，高度符合列表行', (tester) async {
      var tapped = 0;
      await _pump(
        tester,
        SearchPostCard(post: _post(blurb: '摘要'), onTap: () => tapped++),
      );
      await tester.tap(find.byType(SearchPostCard));
      expect(tapped, 1);
      expect(
        tester.getSize(find.byType(SearchPostCard)).height,
        greaterThanOrEqualTo(AppSize.topicRow),
      );
      await _unmount(tester);
    });

    for (final variant in [...UiVariant.portrait, ...UiVariant.landscape]) {
      testUi('不溢出（${variant.label}）', (tester) async {
        await _pump(
          tester,
          ListView(
            children: [
              SearchPostCard(
                post: _post(
                  postNumber: 3,
                  blurb: '这张卡的 <span class="search-highlight">奖励</span> 要三个月，' * 3,
                  likes: 12,
                ),
              ),
            ],
          ),
          variant: variant,
        );
        expectNoUiException(tester);
        await _unmount(tester);
      });
    }
  });

  group('高级筛选半屏', () {
    Widget host(ValueChanged<SearchFilter> onChanged, {SearchFilter? filter}) =>
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => SizedBox(
                  height: 600,
                  child: SearchFilterPanel(
                    filter: filter ?? const SearchFilter(),
                    onFilterChanged: onChanged,
                    hideInType: true,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        );

    testUi('标题 + x；「应用筛选」整宽主按钮，选状态后应用', (tester) async {
      SearchFilter? applied;
      await _pump(tester, host((f) => applied = f));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expectNoUiException(tester);
      expect(find.text('高级搜索'), findsOneWidget);
      expect(find.text('应用筛选'), findsOneWidget);
      // 没有筛选时没有「重置」
      expect(find.text('重置'), findsNothing);

      await tester.tap(find.text('已解决').first);
      await tester.pump(const Duration(milliseconds: 300));
      // 有筛选后出现「重置」（brand，不是红色）
      expect(find.text('重置'), findsOneWidget);
      final reset = tester.widget<Text>(find.text('重置'));
      final brand = tester.element(find.text('重置')).tokens.colors.brandPrimary;
      expect(reset.style?.color, brand);

      await tester.tap(find.text('应用筛选'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(applied?.status, isNotNull);
      await _unmount(tester);
    });

    for (final variant in [...UiVariant.portrait, ...UiVariant.landscape]) {
      testUi('不溢出（${variant.label}）', (tester) async {
        await _pump(tester, host((_) {}), variant: variant);
        await tester.tap(find.text('open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expectNoUiException(tester);
        await _unmount(tester);
      });
    }
  });

  testUi('骨架：列表行几何，6 行', (tester) async {
    await _pump(tester, const SearchListSkeleton());
    expect(find.byType(TopicRowSkeleton), findsNWidgets(6));
    expectNoUiException(tester);
    expect(find.byIcon(AppIcons.search), findsNothing);
    await _unmount(tester);
  });
}
