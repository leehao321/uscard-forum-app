import 'dart:async';
import 'dart:convert';

import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/search_filter.dart';
import 'package:fluxdo/models/search_result.dart';
import 'package:fluxdo/providers/ai_topic_summary_provider.dart';
import 'package:fluxdo/providers/category_provider.dart';
import 'package:fluxdo/providers/theme_provider.dart'
    show sharedPreferencesProvider;
import 'package:fluxdo/services/toast_service.dart';
import 'package:fluxdo/storage/topic_note_store.dart';
import 'package:fluxdo/widgets/badge/my_badges_skeleton.dart';
import 'package:fluxdo/widgets/notes/topic_note_sheet.dart';
import 'package:fluxdo/widgets/search/search_filter_panel.dart';
import 'package:fluxdo/widgets/search/search_post_card.dart';
import 'package:fluxdo/widgets/topic/ai_segment_summary_card.dart';
import 'package:fluxdo/widgets/topic/topic_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fixtures.dart';
import 'support/ui_harness.dart';

// Gemini 审阅核实 B（M 级 / L 级）：每条能复现的问题都在这里有测试，
// 并且放到旧代码上跑过，确认旧代码上会失败。数据全是假的。

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

String _notes() => jsonEncode({
  'v': 2,
  'notes': [
    {
      'id': 5,
      'title': '测试话题',
      'text': '话题级笔记',
      'excerpts': <Object>[],
      'floors': {'3': '三楼的笔记', '8': '八楼的笔记'},
      'updated': 1700000100000,
    },
  ],
});

SearchPost _post({String blurb = ''}) => SearchPost.fromJson(
  {
    'id': 1,
    'username': 'amex_plat',
    'avatar_template': '',
    'created_at': fixtureTime(const Duration(hours: 3)),
    'like_count': 0,
    'blurb': blurb,
    'post_number': 1,
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

List<Override> _searchOverrides(SharedPreferences prefs) => [
  sharedPreferencesProvider.overrideWithValue(prefs),
  categoriesProvider.overrideWith((ref) async => fixtureCategories()),
  tagsProvider.overrideWith((ref) async => ['chase', 'csr', 'amex']),
];

void main() {
  setUpAll(loadUiFonts);

  group('M-1 笔记半屏：概览里的其他笔记能改、能删', () {
    testUi('点「其他笔记」里的楼层改成编辑它，删除按钮只删那一楼', (tester) async {
      await pumpUi(
        tester,
        const Scaffold(
          body: TopicNoteSheetBody(topicId: 5, title: '测试话题'),
        ),
        prefs: {'topic_notes_v2': _notes()},
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('note-row-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('note-row-8')), findsOneWidget);

      // 点 3 楼：输入框换成 3 楼的文字，话题级笔记出现在「其他笔记」里
      await tester.tap(find.byKey(const ValueKey('note-row-3')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '三楼的笔记',
      );
      expect(find.byKey(const ValueKey('note-row-topic')), findsOneWidget);

      // 删 8 楼：只剩 3 楼
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('note-row-8')),
          matching: find.byIcon(AppIcons.delete),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final note = await TopicNoteStore.get(5);
      expect(note!.floorNotes.keys, [3]);
      expect(note.floorNotes[3], '三楼的笔记');
      await _unmount(tester);
    });
  });

  group('M-2 AI 局部总结卡', () {
    Widget card({FutureOr<void> Function()? onSettings}) => Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: AiSegmentSummaryCard(
          title: '测试话题',
          posts: fixtureTopicDetail().postStream.posts,
          onJumpToPost: (_) {},
          onOpenSettings: onSettings,
        ),
      ),
    );

    testUi('没配 API Key：去添加服务商，回来后不再卡在「未配置」', (tester) async {
      var runs = 0;
      await pumpUi(
        tester,
        card(onSettings: () async {}),
        overrides: [
          aiTopicSummaryModelProvider.overrideWithValue(null),
          aiSegmentSummaryRunnerProvider.overrideWithValue((_) async* {
            runs++;
            throw const AiSummaryNotConfigured();
          }),
        ],
      );
      await tester.tap(find.text('总结这一段'));
      await tester.pumpAndSettle();
      expect(runs, 1);
      expect(find.text('所选服务商还没有配置 API Key。'), findsOneWidget);

      // 点「去添加服务商」，设置页返回后，卡片回到可以总结的状态
      final add = find.byKey(const ValueKey('ai-card-add-provider'));
      expect(tester.getSize(add).height, greaterThanOrEqualTo(44));
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.text('所选服务商还没有配置 API Key。'), findsNothing);
      expect(find.text('总结这一段'), findsOneWidget);
      await _unmount(tester);
    });

    testUi('2.0 倍字号下未配置 / 出错态不横向溢出', (tester) async {
      await pumpUi(
        tester,
        card(onSettings: () async {}),
        variant: const UiVariant(Brightness.light, 2.0, UiDevice.pro),
        overrides: [
          aiTopicSummaryModelProvider.overrideWithValue(null),
          aiSegmentSummaryRunnerProvider.overrideWithValue((_) async* {
            throw const AiSummaryNotConfigured();
          }),
        ],
      );
      expect(tester.takeException(), isNull, reason: '收起态');
      await tester.tap(find.text('总结这一段'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '未配置态');
      await _unmount(tester);
    });

    testUi('要点 13 号、楼层链接点击区 ≥ 44，多楼合并成「#N 等 M 楼」', (tester) async {
      final stream = StreamController<String>();
      await pumpUi(
        tester,
        card(),
        overrides: [
          aiTopicSummaryModelProvider.overrideWithValue(null),
          aiSegmentSummaryRunnerProvider.overrideWithValue(
            (_) => stream.stream,
          ),
        ],
      );
      await tester.tap(find.text('总结这一段'));
      await tester.pump();
      stream.add('- 第一个要点 #2\n- 第二个要点 #3 #4 #5');
      await tester.pump();
      await stream.close();
      await tester.pumpAndSettle();

      final point = tester.widget<Text>(find.text('第一个要点'));
      expect(point.style!.fontSize, 13);

      final link = find.bySemanticsLabel('跳到第 2 楼');
      expect(link, findsOneWidget);
      final size = tester.getSize(
        find.ancestor(of: link, matching: find.byType(ConstrainedBox)).first,
      );
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
      expect(find.textContaining('等 3 楼'), findsOneWidget);
      await _unmount(tester);
    });
  });

  group('M-3 我的徽章骨架屏', () {
    testUi('不再自带大横幅顶栏（页面外层已经有导航栏）', (tester) async {
      await pumpUi(
        tester,
        const Scaffold(body: MyBadgesSkeleton()),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(SliverAppBar), findsNothing);
      expect(find.byType(SliverGrid), findsWidgets);
      await _unmount(tester);
    });
  });

  group('M-5 搜索', () {
    testUi('摘要里的 HTML 实体解码成正常字符', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await pumpUi(
        tester,
        Scaffold(
          body: SearchPostCard(
            post: _post(blurb: 'Chase &amp; Amex &quot;开卡奖励&quot; &lt;3'),
          ),
        ),
        overrides: _searchOverrides(prefs),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 600));
      final plain = [
        for (final r in tester.widgetList<RichText>(find.byType(RichText)))
          r.text.toPlainText(),
      ].join('\n');
      expect(plain, contains('Chase & Amex "开卡奖励" <3'));
      expect(plain, isNot(contains('&amp;')));
      await _unmount(tester);
    });

    testUi('日期范围正好是「最近一周」时，「最近一周」胶囊选中、自定义不选中', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
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
                  height: 600,
                  child: SearchFilterPanel(
                    filter: SearchFilter(
                      afterDate: now.subtract(const Duration(days: 7)),
                      beforeDate: now,
                    ),
                    onFilterChanged: (_) {},
                    hideInType: true,
                    initialSection: SearchFilterSection.date,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
        overrides: _searchOverrides(prefs),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      bool selected(String label) => tester
          .widget<FilterPill>(find.widgetWithText(FilterPill, label))
          .selected;
      expect(selected('最近一周'), isTrue);
      expect(selected('最近一月'), isFalse);
      expect(selected('最近一年'), isFalse);
      await _unmount(tester);
    });
  });

  group('M-11 档位滑块', () {
    testUi('带两端 A 时，档位文字和轨道对齐', (tester) async {
      await pumpUi(
        tester,
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: StepSlider(
              value: 1,
              count: 4,
              onChanged: (_) {},
              labels: const ['小', '标准', '大', '特大'],
              showTextSizeEnds: true,
            ),
          ),
        ),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 300));
      final track = find.descendant(
        of: find.byType(StepSlider),
        matching: find.byType(CustomPaint),
      );
      final trackLeft = tester.getTopLeft(track.first).dx;
      expect(tester.getTopLeft(find.text('小')).dx, closeTo(trackLeft, 0.5));
      await _unmount(tester);
    });

    testUi('父约束窄到只剩拇指宽度时点一下不抛异常', (tester) async {
      await pumpUi(
        tester,
        Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 24,
              child: StepSlider(value: 0, count: 4, onChanged: (_) {}),
            ),
          ),
        ),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tapAt(const Offset(12, 22));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });
  });

  group('M-14 左滑操作', () {
    Widget row(List<String> log) => Scaffold(
      body: SwipeActions(
        actions: [
          SwipeActionItem(label: '删除', onTap: () => log.add('删除')),
        ],
        child: const SizedBox(
          height: 72,
          width: double.infinity,
          child: Center(child: Text('一行内容')),
        ),
      ),
    );

    testUi('2.0 倍系统字号下，按钮里的字最多按 1.3 倍放大', (tester) async {
      await pumpUi(
        tester,
        row([]),
        variant: const UiVariant(Brightness.light, 2.0, UiDevice.pro),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.drag(find.text('一行内容'), const Offset(-120, 0));
      await tester.pumpAndSettle();
      final scaled = MediaQuery.textScalerOf(
        tester.element(find.text('删除').first),
      ).scale(10);
      expect(scaled, closeTo(13, 0.01));
      await _unmount(tester);
    });

    testUi('读屏自定义操作触发后收起抽屉', (tester) async {
      final handle = tester.ensureSemantics();
      final log = <String>[];
      await pumpUi(tester, row(log), settle: false);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.drag(find.text('一行内容'), const Offset(-120, 0));
      await tester.pumpAndSettle();
      expect(find.text('删除'), findsWidgets);

      // VoiceOver 触发「删除」自定义操作
      final node = tester.getSemantics(find.byType(SwipeActions));
      final id = CustomSemanticsAction.getIdentifier(
        const CustomSemanticsAction(label: '删除'),
      );
      tester.binding.pipelineOwner.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.customAction,
        id,
      );
      await tester.pumpAndSettle();
      expect(log, ['删除']);
      expect(find.text('删除'), findsNothing, reason: '触发后抽屉要收起');
      handle.dispose();
      await _unmount(tester);
    });
  });

  group('M-15 下载完成后的普通提示', () {
    testUi('下载原位变成「已保存」后，新的普通提示接替它，不叠成两层', (tester) async {
      await pumpUi(tester, const Scaffold(body: SizedBox()), settle: false);
      await tester.pump(const Duration(milliseconds: 300));
      final handle = ToastService.showDownload('report.pdf');
      await tester.pump(const Duration(milliseconds: 300));
      handle.updateProgress(1);
      handle.complete('已保存到文件');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('已保存到文件'), findsOneWidget);

      ToastService.showInfo('已复制');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('已复制'), findsOneWidget);
      expect(find.text('已保存到文件'), findsNothing, reason: '同时只显示一条结果提示');
      await tester.pump(const Duration(seconds: 6));
      await _unmount(tester);
    });
  });

  group('L-2 置顶行', () {
    testUi('选中态有底色；鼠标中键触发 onMiddleClick', (tester) async {
      var middle = 0;
      final topic = fixtureTopics().first;
      await pumpUi(
        tester,
        Scaffold(
          body: PinnedTopicRow(
            topic: topic,
            onTap: () {},
            onMiddleClick: () => middle++,
            isSelected: true,
          ),
        ),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.descendant(
          of: find.byType(PinnedTopicRow),
          matching: find.byWidgetPredicate(
            (w) => w is ColoredBox && w.color.a > 0,
          ),
        ),
        findsWidgets,
      );
      final g = await tester.startGesture(
        tester.getCenter(find.byType(PinnedTopicRow)),
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await g.up();
      expect(middle, 1);
      await _unmount(tester);
    });
  });

  group('L-1 图标按钮', () {
    testUi('AppIconButton 接得住自绘图标，读屏标签照常', (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await pumpUi(
        tester,
        Scaffold(
          body: Center(
            child: AppIconButton(
              icon: AppIcons.openBook,
              semanticLabel: '阅读',
              onPressed: () => taps++,
            ),
          ),
        ),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(AppIconButton)).width, 44);
      expect(find.bySemanticsLabel('阅读'), findsOneWidget);
      await tester.tap(find.byType(AppIconButton));
      expect(taps, 1);
      handle.dispose();
      await _unmount(tester);
    });
  });

  group('M-12 对话框', () {
    testUi('外面包了限宽 / 滚动的纯文字也按「纯文字确认」排：左右各 60', (tester) async {
      Widget host(Widget content) => Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AppAlertDialog(
                title: const Text('标题'),
                content: content,
                actions: [
                  TextButton(onPressed: () {}, child: const Text('好')),
                ],
              ),
            ),
            child: const Text('open'),
          ),
        ),
      );
      for (final content in <Widget>[
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: const Text('一段说明文字'),
        ),
        const SingleChildScrollView(child: SelectableText('一段说明文字')),
      ]) {
        await pumpUi(
          tester,
          host(content),
          variant: const UiVariant(Brightness.light, 1, UiDevice.pro),
          settle: false,
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        // 393 宽的屏幕：纯文字确认左右各 60 → 273；当成复杂内容左右各 40 → 313
        expect(
          tester
              .getSize(
                find
                    .descendant(
                      of: find.byType(Dialog),
                      matching: find.byType(Material),
                    )
                    .first,
              )
              .width,
          closeTo(273, 0.5),
        );
        await _unmount(tester);
      }
    });

    testUi('复杂内容 scrollable：标题固定，只有内容滚', (tester) async {
      await pumpUi(
        tester,
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AppAlertDialog(
                  title: const Text('这是标题'),
                  scrollable: true,
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < 60; i++)
                        SizedBox(height: 44, child: Text('第 $i 行')),
                    ],
                  ),
                  actions: [
                    TextButton(onPressed: () {}, child: const Text('好')),
                  ],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final before = tester.getRect(find.text('这是标题'));
      await tester.drag(find.text('第 3 行'), const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getRect(find.text('这是标题')), before, reason: '标题不能跟着滚走');
      await tester.tap(find.text('好'));
      await tester.pump(const Duration(milliseconds: 500));
      await _unmount(tester);
    });
  });
}
