import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:fluxdo/utils/dialog_utils.dart';
import 'package:fluxdo/widgets/common/tag_selection_sheet.dart';

import 'support/ui_harness.dart';

// 补充稿 03「首页 · 添加标签 · 无可用标签」：添加标签半屏 = 头行「添加标签」+ 关闭、
// 搜索框、空状态（标签图标 + 标题 + 说明）。分类页的标签筛选共用同一个半屏。
// 标签搜索走假的网络拦截器，不联网。

/// 拦住 `/tags/filter/search`，按 [tags] 返回；记录每次查询词
class _FakeTagSearch {
  _FakeTagSearch(this.tags);

  /// 空串键 = 没有搜索词时的结果，其他键按搜索词
  final Map<String, List<String>> tags;
  final queries = <String>[];

  late final InterceptorsWrapper interceptor = InterceptorsWrapper(
    onRequest: (options, handler) {
      final q = options.queryParameters['q'] as String? ?? '';
      queries.add(q);
      final names = tags[q] ?? const <String>[];
      handler.resolve(
        Response(
          requestOptions: options,
          data: {
            'results': [
              for (final n in names) {'name': n, 'text': n, 'count': 3},
            ],
          },
        ),
      );
    },
  );
}

void main() {
  setUpAll(loadUiFonts);

  /// 点「open」打开半屏；返回值通过 [result] 取
  Future<void> openSheet(
    WidgetTester tester,
    Map<String, List<String>> tags, {
    int? categoryId,
    List<String> selected = const [],
    UiVariant variant = UiVariant.lightDefault,
    required List<List<String>?> results,
  }) async {
    final fake = _FakeTagSearch(tags);
    final dio = DiscourseService().dio;
    dio.interceptors.insert(0, fake.interceptor);
    addTearDown(() => dio.interceptors.remove(fake.interceptor));
    await pumpUi(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                results.add(
                  await showAppBottomSheet<List<String>>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => TagSelectionSheet(
                      categoryId: categoryId,
                      availableTags: const [],
                      selectedTags: selected,
                      maxTags: 99,
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
      variant: variant,
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    testUi('没有可用标签：头行、搜索框、空状态（${brightness.name}）', (tester) async {
      final results = <List<String>?>[];
      await openSheet(
        tester,
        const {},
        categoryId: 7,
        variant: UiVariant(brightness, 1, UiDevice.pro),
        results: results,
      );
      expectNoUiException(tester);
      final colors = tester.element(find.byType(TagSelectionSheet)).tokens.colors;

      // 头行：标题「添加标签」+ 右侧关闭（不再有搜索框旁的「确定」）
      expect(find.text('添加标签'), findsOneWidget);
      expect(find.byType(AppCloseButton), findsOneWidget);
      expect(find.text('确定'), findsNothing);

      // 搜索框：40 高填充框，占位「搜索标签」，搜索图标 16
      final field = find.byKey(const ValueKey('tag-search-field'));
      expect(tester.getSize(field).height, 40);
      expect(find.text('搜索标签'), findsOneWidget);
      final searchIcon = tester.widget<Icon>(
        find.descendant(of: field, matching: find.byIcon(AppIcons.search)),
      );
      expect(searchIcon.size, 16);
      final fieldDecoration = tester
          .widget<Container>(field)
          .decoration! as BoxDecoration;
      expect(fieldDecoration.color, colors.surfaceElevated);

      // 空状态：48 标签图标 + 标题 + 13 号说明（分类页带「这个分类下」）
      final empty = find.byKey(const ValueKey('tag-empty-state'));
      expect(empty, findsOneWidget);
      final tagsIcon = tester.widget<Icon>(
        find.descendant(of: empty, matching: find.byIcon(AppIcons.tags)),
      );
      expect(tagsIcon.size, 48);
      expect(find.text('暂无可用标签'), findsOneWidget);
      final desc = tester.widget<Text>(find.text('这个分类下还没有可以添加的标签'));
      expect(desc.style!.fontSize, 13);
      expect(desc.style!.color, colors.textMeta);
      // 空状态在搜索框下面
      expect(
        tester.getTopLeft(find.text('暂无可用标签')).dy,
        greaterThan(tester.getBottomLeft(field).dy),
      );
      await uiShot(tester, 'tag_sheet_empty_${brightness.name}');
    });
  }

  testUi('不在分类里打开时，说明不写「这个分类下」', (tester) async {
    final results = <List<String>?>[];
    await openSheet(tester, const {}, results: results);
    expect(find.text('暂无可用标签'), findsOneWidget);
    expect(find.text('还没有可以添加的标签'), findsOneWidget);
    expect(find.textContaining('这个分类下'), findsNothing);
  });

  testUi('搜索没有结果：显示「未找到相关标签」，没有说明行', (tester) async {
    final results = <List<String>?>[];
    await openSheet(tester, const {'': ['amex']}, results: results);
    expect(find.text('暂无可用标签'), findsNothing);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('未找到相关标签'), findsOneWidget);
    expect(find.text('还没有可以添加的标签'), findsNothing);
    expectNoUiException(tester);
  });

  testUi('选标签后出现「确定」，点确定带回选中的标签', (tester) async {
    final results = <List<String>?>[];
    await openSheet(
      tester,
      const {'': ['amex', 'chase']},
      results: results,
    );
    expect(find.text('确定'), findsNothing, reason: '没有改动时不出现确定');
    await tester.tap(find.text('amex'));
    await tester.pumpAndSettle();
    expect(find.text('确定'), findsOneWidget);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(results, [
      ['amex'],
    ]);
  });

  testUi('点关闭：不带回任何改动', (tester) async {
    final results = <List<String>?>[];
    await openSheet(
      tester,
      const {'': ['amex']},
      results: results,
    );
    await tester.tap(find.text('amex'));
    await tester.pumpAndSettle();
    // 头行右侧的关闭按钮（已选标签 chip 上的 x 是另一回事）
    await tester.tap(find.byType(AppCloseButton));
    await tester.pumpAndSettle();
    expect(results, [null]);
  });
}
