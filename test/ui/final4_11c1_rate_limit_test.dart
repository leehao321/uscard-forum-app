import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/diagnostics_page.dart';
import 'package:fluxdo/settings/definitions/network_defs.dart';
import 'package:fluxdo/settings/search/settings_search_index.dart';
import 'package:fluxdo/widgets/settings/rate_limit_settings.dart';

import 'support/final4_11c1_support.dart';
import 'support/ui_harness.dart';

// 第 11 批 · 11c-1（补充稿 33）：诊断 › 高级 › 并发与限流。
// 三个数存在 SharedPreferences 的 mock 里，不联网。

void main() {
  setUpAll(loadUiFonts);

  Future<void> openDiagnostics(
    WidgetTester tester,
    List<Override> overrides,
  ) async {
    await pumpUi(
      tester,
      const DiagnosticsPage(),
      overrides: overrides,
      settle: false,
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.scrollUntilVisible(
      find.byType(AppSegmented),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  int selectedSegment(WidgetTester tester) =>
      tester.widget<AppSegmented>(find.byType(AppSegmented)).selectedIndex;

  testUi('底部「高级」区：预设分段 + 页脚，默认选中「均衡」，不展开滑杆', (tester) async {
    final (_, overrides) = await fakeStore();
    await openDiagnostics(tester, overrides);
    expect(find.text('高级 · 并发与限流'), findsOneWidget);
    final seg = tester.widget<AppSegmented>(find.byType(AppSegmented));
    expect(seg.labels, ['省心', '均衡', '极速', '自定义']);
    expect(seg.selectedIndex, 1);
    expect(find.byType(StepSlider), findsNothing);
    expect(
      find.text(
        '调高加载更快，也更容易触发论坛限流和 Cloudflare 验证；一般用「均衡」即可。',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
  });

  testUi('点「自定义」展开三条滑杆，数值取现版默认 3 / 6 / 3 秒，不改存储', (tester) async {
    final (prefs, overrides) = await fakeStore();
    await openDiagnostics(tester, overrides);
    await tester.tap(find.text('自定义'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(StepSlider), findsNWidgets(3));
    expect(find.text('同时请求数'), findsOneWidget);
    expect(find.text('限流阈值'), findsOneWidget);
    expect(find.text('时间窗口'), findsOneWidget);
    expect(find.text('3 秒'), findsOneWidget);
    // 数值和「均衡」重合时也停在自定义里
    expect(selectedSegment(tester), 3);
    expect(prefs.getInt('pref_max_concurrent'), isNull);
    expect(prefs.getInt('pref_max_per_window'), isNull);
    expect(prefs.getInt('pref_window_seconds'), isNull);
  });

  testUi('切到预设会写入三个数并收起滑杆：极速 6 / 15 / 3，省心 2 / 6 / 5', (tester) async {
    final (prefs, overrides) = await fakeStore();
    await openDiagnostics(tester, overrides);
    await tester.tap(find.text('自定义'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(StepSlider), findsNWidgets(3));

    await tester.tap(find.text('极速'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(prefs.getInt('pref_max_concurrent'), 6);
    expect(prefs.getInt('pref_max_per_window'), 15);
    expect(prefs.getInt('pref_window_seconds'), 3);
    expect(selectedSegment(tester), 2);
    expect(find.byType(StepSlider), findsNothing);

    await tester.tap(find.text('省心'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(prefs.getInt('pref_max_concurrent'), 2);
    expect(prefs.getInt('pref_max_per_window'), 6);
    expect(prefs.getInt('pref_window_seconds'), 5);
    expect(selectedSegment(tester), 0);
  });

  testUi('自定义里点到滑杆最右，数值写进存储并显示出来', (tester) async {
    final (prefs, overrides) = await fakeStore();
    await openDiagnostics(tester, overrides);
    await tester.tap(find.text('自定义'));
    await tester.pump(const Duration(milliseconds: 300));

    final rect = tester.getRect(find.byType(StepSlider).first);
    await tester.tapAt(Offset(rect.right - 12, rect.center.dy));
    await tester.pump(const Duration(milliseconds: 300));
    expect(prefs.getInt('pref_max_concurrent'), 10);
    expect(find.text('10'), findsOneWidget);
    // 数值不再等于任何预设，仍停在自定义
    expect(selectedSegment(tester), 3);
    expect(find.byType(StepSlider), findsNWidgets(3));
  });

  testUi('存储里的数不等于任何预设时，进页面就是自定义并展开', (tester) async {
    final (_, overrides) = await fakeStore({
      'pref_max_concurrent': 4,
      'pref_max_per_window': 9,
      'pref_window_seconds': 2,
    });
    await openDiagnostics(tester, overrides);
    expect(selectedSegment(tester), 3);
    expect(find.byType(StepSlider), findsNWidgets(3));
    expect(find.text('2 秒'), findsOneWidget);
  });

  testUi('非默认值时出现「恢复默认」：确认后回到均衡，取消不动', (tester) async {
    final (prefs, overrides) = await fakeStore({
      'pref_max_concurrent': 6,
      'pref_max_per_window': 15,
      'pref_window_seconds': 3,
    });
    await openDiagnostics(tester, overrides);
    expect(find.text('恢复默认'), findsOneWidget);

    await tester.tap(find.text('恢复默认'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('取消'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(prefs.getInt('pref_max_concurrent'), 6);

    await tester.tap(find.text('恢复默认'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('确定'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(prefs.getInt('pref_max_concurrent'), 3);
    expect(prefs.getInt('pref_max_per_window'), 6);
    expect(prefs.getInt('pref_window_seconds'), 3);
    expect(selectedSegment(tester), 1);
    // 回到默认后按钮消失
    expect(find.text('恢复默认'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
  });

  test('预设判定：三个数等于某个预设才算预设，其余是自定义', () {
    expect(
      rateLimitPresetOf(const RateLimitValues(2, 6, 5)),
      RateLimitPreset.gentle,
    );
    expect(rateLimitPresetOf(rateLimitDefaults), RateLimitPreset.balanced);
    expect(
      rateLimitPresetOf(const RateLimitValues(6, 15, 3)),
      RateLimitPreset.turbo,
    );
    expect(
      rateLimitPresetOf(const RateLimitValues(6, 15, 4)),
      RateLimitPreset.custom,
    );
  });

  testUi('并发与限流已从网络设置移走，诊断设置里能搜到', (tester) async {
    final (_, overrides) = await fakeStore();
    late List<SettingsSearchResult> index;
    await pumpUi(
      tester,
      Builder(
        builder: (context) {
          index = buildSearchIndex(context);
          return const SizedBox();
        },
      ),
      overrides: overrides,
    );
    final rateLimit = index.where((r) => r.model.id == 'rateLimit').toList();
    expect(rateLimit.map((r) => r.categoryName), ['诊断']);

    late List<String> networkIds;
    await pumpUi(
      tester,
      Builder(
        builder: (context) {
          networkIds = [
            for (final g in buildNetworkCustomGroups(context))
              for (final item in g.items) item.id,
          ];
          return const SizedBox();
        },
      ),
      overrides: overrides,
    );
    expect(networkIds, isNot(contains('rateLimit')));
  });
}
