import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/providers/theme_provider.dart'
    show sharedPreferencesProvider;
import 'package:fluxdo/providers/user_content_providers.dart';
import 'package:fluxdo/widgets/share/export_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ui/support/ui_harness.dart';

// 导出文章半屏（补充稿 26）：导出范围、文件格式两个分段控件，另存为 / 同步到 Notion
// 两个按钮。控件的选择会影响「Markdown 限制」提示；按钮要走对应的去向。

/// 示例数据：只用帖子 id 列表，不联网。[count] 条帖子
TopicDetail _detail(int count) => TopicDetail.fromJson({
  'id': 1001,
  'title': '示例话题标题',
  'slug': 'example',
  'posts_count': count,
  'category_id': 11,
  'tags': <String>[],
  'views': 1,
  'like_count': 0,
  'created_at': '2026-10-30T08:00:00.000Z',
  'highest_post_number': count,
  'last_read_post_number': 1,
  'post_stream': {
    'posts': <Map<String, dynamic>>[],
    'stream': [for (var i = 1; i <= count; i++) i],
  },
  'details': {
    'created_by': {'id': 1, 'username': 'example', 'avatar_template': ''},
    'last_poster': {'id': 1, 'username': 'example', 'avatar_template': ''},
  },
});

Future<void> _pump(
  WidgetTester tester, {
  int count = 30,
  UiVariant variant = UiVariant.lightDefault,
}) async {
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  await pumpUi(
    tester,
    Align(
      alignment: Alignment.bottomCenter,
      child: ExportSheet(detail: _detail(count)),
    ),
    variant: variant,
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      currentUsernameProvider.overrideWith((ref) async => null),
    ],
  );
  await tester.pump(const Duration(milliseconds: 100));
}

/// 「Markdown 格式最多导出前 10 条帖子」
final _limitHint = find.textContaining('最多导出前');

void main() {
  setUpAll(loadUiFonts);

  testUi('版面：标题、导出范围、文件格式、另存为、同步到 Notion', (tester) async {
    await _pump(tester);
    expectNoUiException(tester);
    expect(find.text('导出文章'), findsOneWidget);
    expect(find.text('导出范围'), findsOneWidget);
    expect(find.text('仅主帖'), findsOneWidget);
    expect(find.text('全部楼层'), findsOneWidget);
    expect(find.text('文件格式'), findsOneWidget);
    expect(find.text('Markdown'), findsOneWidget);
    expect(find.text('HTML'), findsOneWidget);
    expect(find.text('另存为…'), findsOneWidget);
    expect(find.text('同步到 Notion'), findsOneWidget);
    // 右上角有关闭按钮
    expect(find.byType(AppCloseButton), findsOneWidget);
  });

  testUi('默认「仅主帖」+ Markdown：不显示条数限制提示', (tester) async {
    await _pump(tester);
    expect(_limitHint, findsNothing);
  });

  testUi('选「全部楼层」：帖子超过限制时出现提示；改选 HTML 提示消失', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('全部楼层'));
    await tester.pumpAndSettle();
    expect(_limitHint, findsOneWidget, reason: '全部楼层 + Markdown 且 30 > 10');
    await tester.tap(find.text('HTML'));
    await tester.pumpAndSettle();
    expect(_limitHint, findsNothing, reason: 'HTML 没有条数限制');
    await tester.tap(find.text('Markdown'));
    await tester.pumpAndSettle();
    expect(_limitHint, findsOneWidget);
    await tester.tap(find.text('仅主帖'));
    await tester.pumpAndSettle();
    expect(_limitHint, findsNothing, reason: '回到仅主帖');
  });

  testUi('帖子数不超过限制时，选「全部楼层」也没有提示', (tester) async {
    await _pump(tester, count: 5);
    await tester.tap(find.text('全部楼层'));
    await tester.pumpAndSettle();
    expect(_limitHint, findsNothing);
  });

  testUi('点「同步到 Notion」：尚未配置时询问是否去设置', (tester) async {
    await _pump(tester);
    expect(find.text('尚未配置，点击前往设置'), findsOneWidget);
    await tester.tap(find.text('同步到 Notion'));
    // 执行中按钮上的转圈一直在动，不能 pumpAndSettle
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AppAlertDialog), findsOneWidget);
  });

  group('AppSegmentedControl', () {
    testUi('点另一个选项回调它的值；选中项带 selected 语义', (tester) async {
      var value = 'a';
      await pumpUi(
        tester,
        Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => AppSegmentedControl<String>(
              value: value,
              onChanged: (v) => setState(() => value = v),
              segments: const [
                AppSegment(value: 'a', label: '甲'),
                AppSegment(value: 'b', label: '乙'),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('乙'));
      await tester.pumpAndSettle();
      expect(value, 'b');
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.text('乙')),
        matchesSemantics(
          label: '乙',
          isButton: true,
          isSelected: true,
          isEnabled: true,
          isInMutuallyExclusiveGroup: true,
          hasEnabledState: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    testUi('onChanged 为 null 时禁用：点击不切换', (tester) async {
      await pumpUi(
        tester,
        Scaffold(
          body: AppSegmentedControl<String>(
            value: 'a',
            onChanged: null,
            segments: const [
              AppSegment(value: 'a', label: '甲'),
              AppSegment(value: 'b', label: '乙'),
            ],
          ),
        ),
      );
      await tester.tap(find.text('乙'));
      await tester.pumpAndSettle();
      // 禁用时滑块仍在「甲」：甲的中心在滑块范围内，乙不在
      final thumb = tester.getRect(find.byKey(const ValueKey('segment_thumb')));
      expect(thumb.contains(tester.getCenter(find.text('甲'))), isTrue);
      expect(thumb.contains(tester.getCenter(find.text('乙'))), isFalse);
    });

    testUi('选中后滑块移到该选项下面', (tester) async {
      var value = 'a';
      await pumpUi(
        tester,
        Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => AppSegmentedControl<String>(
              value: value,
              onChanged: (v) => setState(() => value = v),
              segments: const [
                AppSegment(value: 'a', label: '甲'),
                AppSegment(value: 'b', label: '乙'),
              ],
            ),
          ),
        ),
      );
      Rect thumb() => tester.getRect(find.byKey(const ValueKey('segment_thumb')));
      expect(thumb().contains(tester.getCenter(find.text('甲'))), isTrue);
      await tester.tap(find.text('乙'));
      await tester.pumpAndSettle();
      expect(thumb().contains(tester.getCenter(find.text('乙'))), isTrue);
      expect(thumb().contains(tester.getCenter(find.text('甲'))), isFalse);
    });
  });
}
