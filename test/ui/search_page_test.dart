import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/search_result.dart';
import 'package:fluxdo/pages/search_page.dart';
import 'package:fluxdo/providers/category_provider.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/theme_provider.dart'
    show sharedPreferencesProvider;
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:fluxdo/services/preloaded_data_service.dart';
import 'package:fluxdo/widgets/common/error_view.dart';
import 'package:fluxdo/widgets/search/search_post_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fixtures.dart';
import 'support/ui_harness.dart';

// 0.4.0 M9.5a：搜索页整页（三态 + 错误）。服务一律是假的，不碰真站。

class _FakeService implements DiscourseService {
  _FakeService({this.recent = const [], this.onSearch});

  final List<String> recent;
  final Future<SearchResult> Function(String query)? onSearch;
  final List<String> queries = [];
  var cleared = false;

  @override
  Future<List<String>> getRecentSearches() async => recent;

  @override
  Future<void> clearRecentSearches() async => cleared = true;

  @override
  Future<SearchResult> search({
    required String query,
    int page = 1,
    String? typeFilter,
  }) {
    queries.add(query);
    return onSearch!(query);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

SearchResult _result({int posts = 3, bool users = false}) =>
    SearchResult.fromJson({
      'posts': [
        for (var i = 0; i < posts; i++)
          {
            'id': i + 1,
            'topic_id': 1001,
            'username': 'amex_plat',
            'avatar_template': '',
            'created_at': fixtureTime(Duration(hours: i + 1)),
            'like_count': i,
            'blurb': '这是第 $i 条 chase 的结果摘要',
            'post_number': i + 1,
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
      'users': [
        if (users)
          {'id': 5, 'username': 'chase_fan', 'name': '张三', 'avatar_template': ''},
      ],
      'grouped_search_result': <String, dynamic>{},
    });

List<Override> _overrides(SharedPreferences prefs, _FakeService service) => [
  sharedPreferencesProvider.overrideWithValue(prefs),
  discourseServiceProvider.overrideWithValue(service),
  categoriesProvider.overrideWith((ref) async => fixtureCategories()),
  tagsProvider.overrideWith((ref) async => ['chase', 'csr']),
];

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeService service, {
  String? query,
  UiVariant variant = UiVariant.lightDefault,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  // 不让页面去请求论坛首页取站点设置
  PreloadedDataService().debugSeed(siteSettings: const {});
  await pumpUi(
    tester,
    SearchPage(initialQuery: query),
    variant: variant,
    overrides: _overrides(prefs, service),
    settle: false,
  );
  await tester.pump(const Duration(milliseconds: 800));
  await tester.pump(const Duration(milliseconds: 800));
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(loadUiFonts);

  group('搜索页整页', () {
    for (final v in [
      UiVariant.lightDefault,
      const UiVariant(Brightness.dark, 1.3, UiDevice.pro),
      ...UiVariant.landscape,
    ]) {
      testUi('聚焦态：最近搜索（${v.label}）', (tester) async {
        final service = _FakeService(recent: const ['chase 125k', 'amex 白金']);
        await _pumpPage(tester, service, variant: v);
        expectNoUiException(tester);
        expect(find.text('chase 125k'), findsOneWidget);
        expect(find.text('amex 白金'), findsOneWidget);
        await uiShot(tester, 'm95a_search_focus_${v.label}');
        await _unmount(tester);
      });

      testUi('结果态：带初始查询直接出结果行（${v.label}）', (tester) async {
        final service = _FakeService(onSearch: (_) async => _result());
        await _pumpPage(tester, service, query: 'chase', variant: v);
        expectNoUiException(tester);
        expect(service.queries, isNotEmpty);
        expect(service.queries.first, contains('chase'));
        expect(find.byType(SearchPostCard), findsWidgets);
        await uiShot(tester, 'm95a_search_results_${v.label}');
        await _unmount(tester);
      });
    }

    testUi('空结果显示状态页', (tester) async {
      final service = _FakeService(
        onSearch: (_) async => _result(posts: 0),
      );
      await _pumpPage(tester, service, query: 'zzz');
      expectNoUiException(tester);
      expect(find.byType(SearchPostCard), findsNothing);
      expect(find.text('没有找到相关结果'), findsOneWidget);
      await _unmount(tester);
    });

    testUi('请求失败显示错误态，可重试', (tester) async {
      var attempts = 0;
      final service = _FakeService(
        onSearch: (_) async {
          attempts++;
          if (attempts == 1) throw Exception('boom');
          return _result();
        },
      );
      await _pumpPage(tester, service, query: 'chase');
      expect(find.byType(ErrorView), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 800));
      expect(attempts, 2);
      expect(find.byType(SearchPostCard), findsWidgets);
      await _unmount(tester);
    });

    testUi('点最近搜索会发起搜索；无障碍', (tester) async {
      final service = _FakeService(
        recent: const ['chase 125k'],
        onSearch: (_) async => _result(),
      );
      await _pumpPage(tester, service);
      await expectUiAccessibility(tester, textContrast: false);
      await tester.tap(find.text('chase 125k'));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 800));
      expect(service.queries.single, contains('chase 125k'));
      expect(find.byType(SearchPostCard), findsWidgets);
      await _unmount(tester);
    });
  });
}
