import 'dart:async';

import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/reading_toolbar.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/topic_more_topics.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/topic_post_list.dart'
    show GapIndicator;
import 'package:fluxdo/widgets/post/post_item/post_item.dart';
import 'package:fluxdo/widgets/post/post_item/widgets/post_header_section.dart';
import 'package:fluxdo/widgets/post/post_item/widgets/post_replies_list.dart';
import 'package:fluxdo/widgets/post/post_replies_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/final4_reading.dart';
import 'support/fixtures.dart';
import 'support/ui_harness.dart';

// 第 11 批 11b-1 的截图（补充稿 09–17、20；18、19 见报告里的 QUESTION）。
// 设置 SHOTS_DIR 才会出图；不设置时只做不抛异常的检查。
//
//   SHOTS_DIR=C:/Users/hao/uscard-review/0.5.0/shots/final4 $
//     flutter test test/ui/final4_11b1_shots_test.dart

final _variants = [
  const UiVariant(Brightness.light, 1.0, UiDevice.pro),
  const UiVariant(Brightness.dark, 1.0, UiDevice.pro),
];

String _name(String id, String title, UiVariant v) =>
    '${id}_${title}_${v.brightness.name}';

const _opCooked = '<p>坛友们，今年有拿到 Chase retention offer 的吗？打电话问毛都没有，隔壁老王 Amex 最起码还是给了几根毛毛呢</p>';

/// 阅读页外壳：导航栏 + 主题头 + [posts] + 楼层胶囊工具栏
Future<void> _pumpReading(
  WidgetTester tester,
  UiVariant variant, {
  required List<Widget> posts,
  Widget? tail,
  bool settle = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await pumpUi(
    tester,
    Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              AppNavBar(
                title: '',
                slotWidth: 100,
                showDivider: true,
                trailing: [
                  AppIconButton(
                    icon: AppIcons.search,
                    semanticLabel: '搜索',
                    onPressed: () {},
                  ),
                  AppIconButton(
                    icon: AppIcons.moreHoriz,
                    semanticLabel: '更多',
                    onPressed: () {},
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 120),
                  children: [
                    const _Header(),
                    // 真实列表里楼层自带 20 页边距，不再套阅读列
                    ...posts,
                    ?tail,
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ReadingToolbar(
              expandedListenable: ValueNotifier(false),
              floorListenable: ValueNotifier(1),
              total: 776,
              isLoggedIn: true,
              bookmarked: false,
              notificationIcon: AppIcons.notification,
              onReply: () {},
              onNotification: () {},
              onBookmark: () {},
              onShare: () {},
              onOpenFloorJump: () {},
            ),
          ),
        ],
      ),
    ),
    variant: variant,
    overrides: readingOverrides(prefs),
    settle: false,
  );
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
  if (settle) await tester.pumpAndSettle();
}

Widget _item(Post p, {String? top, String? bottom, bool owner = false}) =>
    PostItem(
      post: p,
      topicId: 1001,
      isTopicOwner: owner,
      dateSeparatorLabel: top,
      bottomDateSeparatorLabel: bottom,
      onReply: ({String? initialContent}) {},
    );

Post _op({String cooked = _opCooked, List<Map<String, dynamic>>? links}) =>
    readingPost(
      1,
      username: 'bpllpb',
      name: '鲁铁蛋',
      cooked: cooked,
      likes: 21,
      linkCounts: links,
    );

List<Map<String, dynamic>> _links() => [
  reflectionLink('示例链接标题一', 'https://example.com/t/a/101'),
  reflectionLink('示例链接标题二', 'https://github.com/t/b/102'),
  reflectionLink('示例链接标题三', 'https://uscardforum.com/t/c/103'),
];

void main() {
  setUpAll(loadUiFonts);

  for (final v in _variants) {
    testUi('09 日期分隔 + 相关链接折叠（${v.label}）', (tester) async {
      await _pumpReading(
        tester,
        v,
        posts: [
          _item(_op(links: _links()), bottom: '2023年3月6日', owner: true),
          _item(
            readingPost(2, username: 'Amazon', name: '亚马逊', cooked: '<p>降級，然後未來再擼她。</p>', likes: 16),
            top: '2023年3月6日',
          ),
          _item(readingPost(3, username: 'TTTTTTTT', cooked: '<p>Chase 很难要到吧</p>', likes: 8)),
        ],
      );
      expectNoUiException(tester);
      await uiShot(tester, _name('09', '日期分隔与相关链接折叠', v));
    });

    testUi('10 相关链接展开（${v.label}）', (tester) async {
      await _pumpReading(
        tester,
        v,
        posts: [_item(_op(links: _links()), owner: true)],
      );
      await tester.tap(find.byKey(const ValueKey('related_links_toggle')));
      await tester.pumpAndSettle();
      expectNoUiException(tester);
      await uiShot(tester, _name('10', '相关链接展开', v));
    });

    testUi('11 链接预览卡片（${v.label}）', (tester) async {
      const onebox = '''
<aside class="onebox allowlistedgeneric" data-onebox-src="https://example.com/page">
<header class="source"><a href="https://example.com/page">example.com</a></header>
<article class="onebox-body"><img class="thumbnail" src="https://example.com/preview.jpg" width="690" height="345">
<h3><a href="https://example.com/page">示例链接标题</a></h3>
<p>示例摘要：链接页面的简短描述，最多两行。</p></article></aside>''';
      await _pumpReading(
        tester,
        v,
        posts: [_item(_op(cooked: _opCooked + onebox), owner: true)],
      );
      expectNoUiException(tester);
      await uiShot(tester, _name('11', '链接预览卡片', v));
    });

    testUi('12 楼层回复展开（${v.label}）', (tester) async {
      final replies = [
        readingPost(5, username: 'user_a', name: '示例用户甲', cooked: '<p>示例数据：第一条回复。</p>', ago: const Duration(seconds: 20)),
        readingPost(6, username: 'user_b', name: '示例用户乙', cooked: '<p>示例数据：第二条回复。</p>', ago: const Duration(seconds: 20)),
      ];
      await _pumpReading(
        tester,
        v,
        posts: [
          _item(_op(), owner: true),
          // 真实界面里回复列表在楼层页脚内，左右留 20 页边距
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.pageMargin),
            child: PostRepliesList(
              replies: replies,
              replyCount: 2,
              canLoadMore: false,
              isLoadingRepliesNotifier: ValueNotifier(false),
              showRepliesNotifier: ValueNotifier(true),
              onLoadMore: () {},
            ),
          ),
        ],
      );
      expectNoUiException(tester);
      await uiShot(tester, _name('12', '楼层回复展开', v));
    });

    for (final loaded in [true, false]) {
      testUi('${loaded ? '13' : '14'} 回复给${loaded ? '内联预览' : '加载中'}（${v.label}）', (tester) async {
        final completer = Completer<List<Post>>();
        final post2 = readingPost(
          2,
          username: 'Amazon',
          name: '亚马逊',
          cooked: '<p>降級，然後未來再擼她。</p>',
          likes: 16,
          replyTo: 1,
          replyToUser: const {'username': 'demo', 'name': '示例用户', 'avatar_template': ''},
        );
        await _pumpReading(
          tester,
          v,
          posts: [
            _item(_op(), owner: true),
            ReplyEntryFloor(
              post: post2,
              loader: (_) => completer.future,
            ),
          ],
        );
        await tester.tap(find.byIcon(AppIcons.reply).first);
        await tester.pump();
        if (loaded) {
          completer.complete([
            readingPost(1, username: 'demo', name: '示例用户', cooked: '<p>示例数据：被回复楼层的正文内容。</p>'),
          ]);
          await tester.pump();
          await tester.pump();
        }
        await tester.pump(const Duration(milliseconds: 100));
        expectNoUiException(tester);
        await uiShot(tester, _name(loaded ? '13' : '14', loaded ? '回复给内联预览' : '回复给加载中', v));
        if (!loaded) {
          completer.complete([]);
          await tester.pump();
        }
      });
    }

    for (final loaded in [true, false]) {
      testUi('${loaded ? '15' : '16'} 帖子详情${loaded ? '半屏' : '加载中'}（${v.label}）', (tester) async {
        final ids = Completer<List<int>>();
        final reply = readingPost(
          5,
          username: 'user_b',
          name: '示例用户乙',
          cooked: '<p>示例数据：一条相关回复。</p>',
          ago: const Duration(seconds: 20),
          replyTo: 3,
        );
        await _pumpReading(
          tester,
          v,
          posts: [_item(_op(), owner: true)],
        );
        final context = tester.element(find.byType(ReadingToolbar));
        showPostRepliesSheet(
          context: context,
          post: readingPost(
            loaded ? 3 : 4,
            username: 'demo',
            name: '示例用户',
            cooked: '<p>示例数据：本楼的完整正文。</p>',
            ago: const Duration(seconds: 20),
          ),
          topicId: 1001,
          service: readingFakeService(
            ids: loaded ? () async => [reply.id] : () => ids.future,
            posts: () async => [reply],
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        if (loaded) await tester.pump(const Duration(milliseconds: 500));
        expectNoUiException(tester);
        await uiShot(tester, _name(loaded ? '15' : '16', loaded ? '帖子详情半屏' : '帖子详情加载中', v));
        if (!loaded) {
          ids.complete([]);
          await tester.pump();
        }
      });
    }

    testUi('17 只看题主 · 折叠与建议话题（${v.label}）', (tester) async {
      final detail = TopicDetail.fromJson({
        'id': 1001,
        'title': '示例话题',
        'slug': 'demo',
        'posts_count': 2,
        'category_id': 1,
        'post_stream': {'posts': const [], 'stream': const []},
        'details': const {},
        'suggested_topics': [
          for (final (i, t) in ['示例建议话题一', '示例建议话题二'].indexed)
            {
              'id': 2001 + i,
              'title': t,
              'slug': 's$i',
              'posts_count': 69,
              'reply_count': 68,
              'like_count': 76,
              'category_id': 1,
              'created_at': fixtureTime(const Duration(hours: 13)),
              'last_posted_at': fixtureTime(const Duration(hours: 13)),
              'posters': const [
                {'user_id': 1, 'description': '原始发帖人'},
              ],
            },
        ],
      });
      await _pumpReading(
        tester,
        v,
        posts: [
          _item(_op(), owner: true),
          GapIndicator(count: 12, onTap: () {}),
          _item(readingPost(2, username: 'Amazon', name: '亚马逊', cooked: '<p>降級，然後未來再擼她。</p>', likes: 16)),
        ],
        tail: MoreTopicsSection(detail: detail),
      );
      expectNoUiException(tester);
      await uiShot(tester, _name('17', '只看题主折叠与建议话题', v));
    });

    testUi('20 首帖多图（${v.label}）', (tester) async {
      // 占位色按明暗取：图片还没加载时的底色（真实数据里来自 data-dominant-color）
      final dominant = v.brightness == Brightness.dark ? '3A3A3C' : 'E5E5EA';
      final images = [
        for (final n in ['a', 'b', 'c'])
          '<p><img src="https://example.com/$n.jpg" alt="$n" width="690" '
              'height="400" data-dominant-color="$dominant"></p>',
      ].join();
      await _pumpReading(
        tester,
        v,
        posts: [_item(_op(cooked: _opCooked + images), owner: true)],
        // 图片占位在转圈，pumpAndSettle 等不到静止
        settle: false,
      );
      expectNoUiException(tester);
      await uiShot(tester, _name('20', '首帖多图', v));
    });
  }
}

/// 头部 + 正文 + 点赞数的最小楼层（回复给入口走真实的 PostHeaderSection，
/// 可注入加载函数，用来截加载态）
class ReplyEntryFloor extends StatelessWidget {
  const ReplyEntryFloor({
    super.key,
    required this.post,
    required this.loader,
  });

  final Post post;
  final Future<List<Post>> Function(int) loader;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      color: tokens.colors.surfacePage,
      padding: const EdgeInsets.only(bottom: AppSpace.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PostHeaderSection(
            post: post,
            topicId: 1001,
            isTopicOwner: false,
            showStamp: false,
            padding: const EdgeInsets.fromLTRB(
              AppSpace.pageMargin,
              AppSpace.m,
              AppSpace.pageMargin,
              0,
            ),
            onJumpToPost: null,
            replyHistoryLoader: loader,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.pageMargin,
              AppSpace.s,
              AppSpace.pageMargin,
              0,
            ),
            child: Text(
              '降級，然後未來再擼她。',
              style: Theme.of(context).textTheme.bodyMedium!.merge(
                tokens.text.body,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 阅读页主题头（缩简：标题 22 + meta 行），不带 AI 卡片，留出屏幕给楼层
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.pageMargin,
        AppSpace.s,
        AppSpace.pageMargin,
        AppSpace.m,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Chase retention offers',
            style: theme.textTheme.titleLarge!
                .merge(tokens.text.title)
                .copyWith(color: tokens.colors.textPrimary),
          ),
          const SizedBox(height: AppSpace.s),
          Text(
            '玩卡  #chase摩根大通   775   6.7w   2021-12-23',
            style: theme.textTheme.bodySmall!
                .merge(tokens.text.meta)
                .copyWith(color: tokens.colors.textMeta),
          ),
        ],
      ),
    );
  }
}
