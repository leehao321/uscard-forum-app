import 'dart:async';

import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/widgets/common/smart_avatar.dart';
import 'package:fluxdo_render/fluxdo_render.dart' show FluxdoRender;
import 'package:fluxdo/pages/topic_detail_page/widgets/topic_more_topics.dart'
    show MoreTopicsSection;
import 'package:fluxdo/pages/topic_detail_page/widgets/topic_post_list.dart'
    show GapIndicator;
import 'package:fluxdo/widgets/content/discourse_html_content/builders/onebox/default_onebox_builder.dart';
import 'package:fluxdo/widgets/content/discourse_html_content/builders/onebox/onebox_base.dart';
import 'package:fluxdo/widgets/post/post_item/widgets/post_header_section.dart';
import 'package:fluxdo/widgets/post/post_item/widgets/post_replies_list.dart';
import 'package:fluxdo/widgets/post/post_item/widgets/post_segment_frame.dart';
import 'package:fluxdo/widgets/post/post_links.dart';
import 'package:html/parser.dart' as html;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/final4_reading.dart';
import 'support/fixtures.dart' show fixtureTime;
import 'support/ui_harness.dart';

// 第 11 批 11b-1（补充稿 09–17）：阅读页与话题的行为测试。
// 不联网；服务一律用假数据 / 注入的假加载函数。

List<LinkCount> _links(int n) => [
  for (var i = 1; i <= n; i++)
    LinkCount(
      url: 'https://www.example$i.com/t/topic-$i/${100 + i}',
      internal: true,
      reflection: true,
      title: '示例链接标题 $i',
      clicks: i == 1 ? 1500 : 0,
    ),
];

/// 页面里 cookedHtml 含 [text] 的正文渲染个数（正文是自研渲染器画的，
/// 不是 Text / RichText，按 cookedHtml 数）
int _renderedHtml(WidgetTester tester, String text) => tester
    .widgetList<FluxdoRender>(find.byType(FluxdoRender))
    .where((w) => w.cookedHtml.contains(text))
    .length;

void main() {
  setUpAll(loadUiFonts);

  group('相关链接（09 折叠 / 10 展开）', () {
    testUi('默认折叠成一行：只有「相关链接」，不出链接标题', (tester) async {
      await pumpUi(tester, Scaffold(body: PostLinks(linkCounts: _links(3))));
      expect(find.text('相关链接'), findsOneWidget);
      expect(find.text('示例链接标题 1'), findsNothing);
      expect(find.text('收起'), findsNothing);
      // 整行 48 高
      final row = tester.getSize(
        find.byKey(const ValueKey('related_links_toggle')),
      );
      expect(row.height, greaterThanOrEqualTo(AppSize.row48));
    });

    testUi('点折叠行展开：标题 + 站点名（去 www）+ 「收起」；点收起收回', (tester) async {
      await pumpUi(tester, Scaffold(body: PostLinks(linkCounts: _links(3))));
      await tester.tap(find.byKey(const ValueKey('related_links_toggle')));
      await tester.pumpAndSettle();
      expect(find.text('示例链接标题 1'), findsOneWidget);
      expect(find.text('示例链接标题 3'), findsOneWidget);
      expect(find.text('example1.com'), findsOneWidget);
      expect(find.text('收起'), findsOneWidget);
      // 点击数 1500 → 1.5k，仍然显示
      expect(find.text('1.5k'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('related_links_collapse')));
      await tester.pumpAndSettle();
      expect(find.text('示例链接标题 1'), findsNothing);
      expect(find.byKey(const ValueKey('related_links_toggle')), findsOneWidget);
    });

    testUi('阅读设置「默认展开相关链接」打开时直接是展开态', (tester) async {
      await pumpUi(
        tester,
        Scaffold(
          body: PostLinks(linkCounts: _links(2), defaultExpanded: true),
        ),
      );
      expect(find.text('示例链接标题 1'), findsOneWidget);
      expect(find.text('收起'), findsOneWidget);
    });

    testUi('超过 5 条时展开后只列 5 条，「还有 N 条」点开后全列', (tester) async {
      await pumpUi(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: PostLinks(linkCounts: _links(7), defaultExpanded: true),
          ),
        ),
      );
      expect(find.text('示例链接标题 5'), findsOneWidget);
      expect(find.text('示例链接标题 6'), findsNothing);
      await tester.tap(find.text('还有 2 条'));
      await tester.pumpAndSettle();
      expect(find.text('示例链接标题 7'), findsOneWidget);
    });

    testUi('没有入站链接时什么都不画', (tester) async {
      await pumpUi(tester, const Scaffold(body: PostLinks(linkCounts: [])));
      expect(find.text('相关链接'), findsNothing);
    });
  });

  group('日期分隔（09）', () {
    testUi('标签 13 号 meta 色、居中，底色盖住发丝线', (tester) async {
      await pumpUi(
        tester,
        Scaffold(
          body: PostSegmentFrame(
            post: readingPost(2),
            selected: false,
            highlight: false,
            showTopDateSeparator: true,
            topDateSeparatorLabel: '2023年3月6日',
            child: const SizedBox(height: 80, width: double.infinity),
          ),
        ),
      );
      final text = tester.widget<Text>(find.text('2023年3月6日'));
      expect(text.style!.fontSize, 13);
      final tokens = AppTokens.of(tester.element(find.text('2023年3月6日')));
      expect(text.style!.color, tokens.colors.textMeta);
      expectNoUiException(tester);
    });
  });

  group('链接预览卡片（11）', () {
    Widget card(String htmlText, {List<LinkCount>? counts}) => Builder(
      builder: (context) => buildDefaultOnebox(
        context: context,
        theme: Theme.of(context),
        element: html.parseFragment(htmlText).querySelector('aside'),
        linkCounts: counts,
      ),
    );

    const withThumb = '''
<aside class="onebox allowlistedgeneric" data-onebox-src="https://example.com/a">
<header class="source"><img class="site-icon" src=""><a href="https://example.com/a">example.com</a></header>
<article class="onebox-body"><img class="thumbnail" src="https://example.com/preview.jpg">
<h3><a href="https://example.com/a">示例链接标题</a></h3>
<p>示例摘要：链接页面的简短描述。</p></article></aside>''';

    testUi('模板：描边外壳 → 预览图 → 标题 → 摘要 → 站点行', (tester) async {
      await pumpUi(tester, Scaffold(body: card(withThumb)));
      // 外壳：1px separator 描边，圆角 12，无底色
      final shell = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(OneboxContainer),
              matching: find.byType(Container),
            )
            .first,
      );
      final deco = shell.decoration! as BoxDecoration;
      final tokens = AppTokens.of(tester.element(find.byType(OneboxContainer)));
      expect(deco.color, isNull);
      expect((deco.border! as Border).top.color, tokens.colors.separator);
      expect(deco.borderRadius, BorderRadius.circular(tokens.radius.card));

      // 垂直顺序：预览图在最上，其次标题、摘要、站点
      final img = tester.getRect(find.byType(Image).first);
      final title = tester.getRect(find.text('示例链接标题'));
      final desc = tester.getRect(find.text('示例摘要：链接页面的简短描述。'));
      final site = tester.getRect(find.text('example.com'));
      expect(img.bottom, lessThanOrEqualTo(title.top));
      expect(title.bottom, lessThanOrEqualTo(desc.top));
      expect(desc.bottom, lessThanOrEqualTo(site.top));
      // 预览图整宽、高 160
      final card0 = tester.getRect(find.byType(DefaultOneboxCard));
      expect(img.width, card0.width);
      expect(img.height, DefaultOneboxCard.thumbnailHeight);
      // 标题 17 Semibold，摘要 13
      expect(tester.widget<Text>(find.text('示例链接标题')).style!.fontSize, 17);
      expect(
        tester.widget<Text>(find.text('示例链接标题')).style!.fontWeight,
        FontWeight.w600,
      );
      expect(
        tester
            .widget<Text>(find.text('示例摘要：链接页面的简短描述。'))
            .style!
            .fontSize,
        13,
      );
      expectNoUiException(tester);
    });

    testUi('没有预览图就不画图区；摘要最多 2 行', (tester) async {
      await pumpUi(
        tester,
        Scaffold(
          body: card(
            withThumb.replaceAll('<img class="thumbnail" src="https://example.com/preview.jpg">', ''),
          ),
        ),
      );
      expect(find.byType(Image), findsNothing);
      expect(
        tester
            .widget<Text>(find.text('示例摘要：链接页面的简短描述。'))
            .maxLines,
        2,
      );
      expect(tester.widget<Text>(find.text('示例链接标题')).maxLines, 2);
    });

    testUi('点击卡片仍然走链接打开（外壳可点）', (tester) async {
      await pumpUi(tester, Scaffold(body: card(withThumb)));
      final inkWell = tester.widget<InkWell>(
        find
            .descendant(
              of: find.byType(OneboxContainer),
              matching: find.byType(InkWell),
            )
            .first,
      );
      expect(inkWell.onTap, isNotNull);
    });
  });

  group('楼层回复展开（12）', () {
    Future<ValueNotifier<bool>> pumpReplies(
      WidgetTester tester, {
      bool canLoadMore = false,
      VoidCallback? onLoadMore,
      ValueNotifier<bool>? loading,
      void Function(int)? onJump,
    }) async {
      final show = ValueNotifier<bool>(true);
      await pumpUi(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: PostRepliesList(
              replies: [
                readingPost(5, username: 'amex_plat', name: '李四'),
                readingPost(6, username: 'pointsguy'),
              ],
              replyCount: 2,
              canLoadMore: canLoadMore,
              isLoadingRepliesNotifier: loading ?? ValueNotifier(false),
              showRepliesNotifier: show,
              onLoadMore: onLoadMore ?? () {},
              onJumpToPost: onJump,
            ),
          ),
        ),
        overrides: readingOverrides(
          await (() async {
            SharedPreferences.setMockInitialValues({});
            return SharedPreferences.getInstance();
          })(),
        ),
      );
      return show;
    }

    testUi('回复一张卡片：名字、@handle · 时间、楼号、正文 17 号', (tester) async {
      await pumpReplies(tester);
      expect(find.text('李四'), findsOneWidget);
      expect(find.text('pointsguy'), findsOneWidget);
      expect(find.textContaining('@amex_plat · '), findsOneWidget);
      expect(find.text('#5'), findsOneWidget);
      expect(_renderedHtml(tester, '示例数据：这是一条正文。'), 2);
      // 卡片 surface/grouped
      final tokens = AppTokens.of(tester.element(find.text('李四')));
      final card = tester.widget<Container>(
        find
            .ancestor(of: find.text('李四'), matching: find.byType(Container))
            .last,
      );
      expect((card.decoration! as BoxDecoration).color, tokens.colors.surfaceGrouped);
      expectNoUiException(tester);
    });

    testUi('点「收起回复」把展开状态置为 false', (tester) async {
      final show = await pumpReplies(tester);
      expect(find.text('收起回复'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('replies_collapse')));
      expect(show.value, isFalse);
    });

    testUi('点某条回复跳到该楼', (tester) async {
      int? jumped;
      await pumpReplies(tester, onJump: (n) => jumped = n);
      await tester.tap(find.text('#6'));
      expect(jumped, 6);
    });

    testUi('有更多时出「加载更多」，加载中带菊花且不可点', (tester) async {
      var loads = 0;
      final loading = ValueNotifier(false);
      await pumpReplies(
        tester,
        canLoadMore: true,
        onLoadMore: () => loads++,
        loading: loading,
      );
      await tester.tap(find.byKey(const ValueKey('replies_load_more')));
      expect(loads, 1);
      loading.value = true;
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('replies_load_more')),
          matching: find.byType(CupertinoActivityIndicator),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('replies_load_more')));
      expect(loads, 1, reason: '加载中不能重复触发');
    });

    testUi('没有更多时不出「加载更多」', (tester) async {
      await pumpReplies(tester);
      expect(find.byKey(const ValueKey('replies_load_more')), findsNothing);
    });
  });

  group('回复给 · 内联预览（13 内容态 / 14 加载态）', () {
    Future<void> pumpHeader(
      WidgetTester tester,
      Future<List<Post>> Function(int) loader,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await pumpUi(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: PostHeaderSection(
              post: readingPost(
                2,
                username: 'amex_plat',
                replyTo: 1,
                replyToUser: const {
                  'username': 'chase_fan',
                  'name': '示例用户',
                  'avatar_template': '',
                },
              ),
              topicId: 1001,
              isTopicOwner: false,
              showStamp: false,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              onJumpToPost: null,
              replyHistoryLoader: loader,
            ),
          ),
        ),
        overrides: readingOverrides(prefs),
      );
    }

    // 「回复给」入口：头部右侧的小胶囊（reply 图标 + 头像）
    Finder entry() => find.byIcon(AppIcons.reply);

    testUi('点入口先出加载块（含「回复给 某人」行和「加载中」），内容到达后替换', (tester) async {
      final completer = Completer<List<Post>>();
      await pumpHeader(tester, (_) => completer.future);
      expect(find.byKey(const ValueKey('reply_history_loading')), findsNothing);

      await tester.tap(entry().first);
      await tester.pump();
      // 加载态：行 + 加载块
      expect(find.text('回复给 示例用户'), findsOneWidget);
      expect(find.byKey(const ValueKey('reply_history_collapse')), findsOneWidget);
      expect(find.byKey(const ValueKey('reply_history_loading')), findsOneWidget);
      expect(find.text('加载中'), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(_renderedHtml(tester, '示例数据：被回复楼层的正文内容。'), 0);
      // 加载块：surface/grouped 圆角
      final tokens = AppTokens.of(tester.element(find.text('加载中')));
      final box = tester.widget<Container>(
        find
            .ancestor(of: find.text('加载中'), matching: find.byType(Container))
            .first,
      );
      expect((box.decoration! as BoxDecoration).color, tokens.colors.surfaceGrouped);

      completer.complete([
        readingPost(1, username: 'chase_fan', name: '示例用户', cooked: '<p>示例数据：被回复楼层的正文内容。</p>'),
      ]);
      await tester.pump();
      await tester.pump();
      // 内容态：加载块消失，引用块出现（作者 · #楼层）
      expect(find.byKey(const ValueKey('reply_history_loading')), findsNothing);
      expect(find.text('加载中'), findsNothing);
      expect(_renderedHtml(tester, '示例数据：被回复楼层的正文内容。'), 1);
      expect(find.textContaining('示例用户 · #1', findRichText: true), findsOneWidget);
      expect(find.text('回复给 示例用户'), findsOneWidget);
      expectNoUiException(tester);
    });

    testUi('内容态点「收起」收回，再点入口用缓存秒开（不再请求）', (tester) async {
      var calls = 0;
      await pumpHeader(tester, (_) async {
        calls++;
        return [readingPost(1, cooked: '<p>示例数据：被回复楼层的正文内容。</p>')];
      });
      await tester.tap(entry().first);
      await tester.pump();
      await tester.pump();
      expect(_renderedHtml(tester, '示例数据：被回复楼层的正文内容。'), 1);

      await tester.tap(find.byKey(const ValueKey('reply_history_collapse')));
      await tester.pump();
      expect(_renderedHtml(tester, '示例数据：被回复楼层的正文内容。'), 0);
      expect(find.text('回复给 示例用户'), findsNothing);

      await tester.tap(entry().first);
      await tester.pump();
      expect(_renderedHtml(tester, '示例数据：被回复楼层的正文内容。'), 1);
      expect(find.byKey(const ValueKey('reply_history_loading')), findsNothing);
      expect(calls, 1);
    });

    testUi('加载中点「收起」收回；内容迟到也不会自己再展开', (tester) async {
      final completer = Completer<List<Post>>();
      await pumpHeader(tester, (_) => completer.future);
      await tester.tap(entry().first);
      await tester.pump();
      expect(find.byKey(const ValueKey('reply_history_loading')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('reply_history_collapse')));
      await tester.pump();
      expect(find.byKey(const ValueKey('reply_history_loading')), findsNothing);

      completer.complete([readingPost(1)]);
      await tester.pump();
      await tester.pump();
      expect(find.text('回复给 示例用户'), findsNothing);
      expect(_renderedHtml(tester, '示例数据：这是一条正文。'), 0);
    });

    testUi('加载失败：展开块收回，不留一个转圈的空壳', (tester) async {
      await pumpHeader(tester, (_) async => throw StateError('boom'));
      await tester.tap(entry().first);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('reply_history_loading')), findsNothing);
      expect(find.text('回复给 示例用户'), findsNothing);
      // 吞掉 handleUnexpected 里可能抛出的异常，只关心界面状态
      tester.takeException();
    });
  });

  group('只看题主 · 隐藏回复折叠条（17）', () {
    testUi('整宽胶囊「显示隐藏的回复」，高 44，朗读标签带数量', (tester) async {
      var taps = 0;
      final handle = tester.ensureSemantics();
      await pumpUi(
        tester,
        Scaffold(body: GapIndicator(count: 3, onTap: () => taps++)),
      );
      expect(find.text('显示隐藏的回复'), findsOneWidget);
      final pill = tester.getSize(
        find.byKey(const ValueKey('hidden_replies_toggle')),
      );
      expect(pill.height, AppSize.hit);
      // 整宽（左右各 20 页边距）
      expect(pill.width, UiDevice.proMax.size.width - 2 * AppSpace.pageMargin);
      expect(find.bySemanticsLabel('显示 3 条隐藏回复'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('hidden_replies_toggle')));
      expect(taps, 1);
      handle.dispose();
    });

    testUi('点击后进入加载：菊花 + 「加载中」，且不能重复触发', (tester) async {
      var taps = 0;
      await pumpUi(
        tester,
        Scaffold(body: GapIndicator(count: 3, onTap: () => taps++)),
      );
      await tester.tap(find.byKey(const ValueKey('hidden_replies_toggle')));
      await tester.pump();
      expect(find.text('加载中'), findsOneWidget);
      expect(find.text('显示隐藏的回复'), findsNothing);
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('hidden_replies_toggle')));
      expect(taps, 1);
    });

    testUi('胶囊底色 surface/grouped、文字 brand 13 Semibold', (tester) async {
      await pumpUi(tester, Scaffold(body: GapIndicator(count: 3, onTap: () {})));
      final tokens = AppTokens.of(tester.element(find.text('显示隐藏的回复')));
      final text = tester.widget<Text>(find.text('显示隐藏的回复'));
      expect(text.style!.color, tokens.colors.brandPrimary);
      expect(text.style!.fontSize, 13);
      expect(text.style!.fontWeight, FontWeight.w600);
      final material = tester.widget<Material>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('hidden_replies_toggle')),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.color, tokens.colors.surfaceGrouped);
    });
  });

  group('帖末建议话题（17）', () {
    TopicDetail detail() => TopicDetail.fromJson({
      'id': 1001,
      'title': '示例话题',
      'slug': 'demo',
      'posts_count': 2,
      'category_id': 1,
      'post_stream': {'posts': const [], 'stream': const []},
      'details': const {},
      'suggested_topics': [
        {
          'id': 2001,
          'title': '示例建议话题一',
          'slug': 's1',
          'posts_count': 69,
          'reply_count': 68,
          'category_id': 1,
          'created_at': fixtureTime(const Duration(hours: 13)),
          'last_posted_at': fixtureTime(const Duration(hours: 13)),
          'posters': [
            {'user_id': 1, 'description': '原始发帖人'},
          ],
        },
      ],
    });

    testUi('小标题 13 meta；条目标题 17 Semibold、没有头像、左右 20', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await pumpUi(
        tester,
        Scaffold(
          body: SingleChildScrollView(child: MoreTopicsSection(detail: detail())),
        ),
        overrides: readingOverrides(prefs),
      );
      final tokens = AppTokens.of(tester.element(find.text('建议话题')));
      final label = tester.widget<Text>(find.text('建议话题'));
      expect(label.style!.fontSize, 13);
      expect(label.style!.color, tokens.colors.textMeta);
      final title = tester.widget<Text>(find.text('示例建议话题一'));
      expect(title.style!.fontSize, 17);
      expect(title.style!.fontWeight, FontWeight.w600);
      expect(tester.getTopLeft(find.text('示例建议话题一')).dx, AppSpace.pageMargin);
      expect(find.byType(SmartAvatar), findsNothing);
      // 回复数仍然在 meta 行里
      expect(find.textContaining('68', findRichText: true), findsWidgets);
      expectNoUiException(tester);
    });
  });
}
