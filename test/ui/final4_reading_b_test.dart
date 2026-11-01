import 'dart:async';

import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:fluxdo/utils/fluxdo_render_callbacks.dart';
import 'package:fluxdo/widgets/content/discourse_html_content/lazy_image.dart';
import 'package:fluxdo/widgets/post/post_item/post_item.dart';
import 'package:fluxdo/widgets/post/post_item/widgets/post_action_bar.dart';
import 'package:fluxdo/widgets/post/post_links.dart';
import 'package:fluxdo/widgets/post/post_replies_sheet.dart';
import 'package:fluxdo_render/fluxdo_render.dart' show FluxdoRender;
import 'package:m3e_ui/m3e_ui.dart' show LoadingSpinner;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/final4_reading.dart';
import 'support/ui_harness.dart';

// 第 11 批 11b-1（补充稿 15 / 16 / 20，以及相关链接在楼层里的位置）。
// 不联网：帖子详情半屏的服务用假实现。

Future<void> _openSheet(
  WidgetTester tester,
  DiscourseService service,
  Post post,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await pumpUi(
    tester,
    Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showPostRepliesSheet(
              context: context,
              post: post,
              topicId: 1001,
              service: service,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
    overrides: readingOverrides(prefs),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(loadUiFonts);

  group('帖子详情半屏（15 内容 / 16 加载中）', () {
    testUi('加载中：标题「#N 帖子详情」+ 共享加载指示「加载中」，不用 M3E 指示器', (tester) async {
      final ids = Completer<List<int>>();
      await _openSheet(
        tester,
        readingFakeService(ids: () => ids.future, posts: () async => []),
        readingPost(4),
      );
      expect(find.text('#4 帖子详情'), findsOneWidget);
      expect(find.byType(LoadingHint), findsOneWidget);
      expect(find.text('加载中'), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(find.byType(LoadingSpinner), findsNothing);
      expect(find.text('相关回复'), findsNothing);
      expectNoUiException(tester);
      // 收尾：让请求完成，不留挂起的 future
      ids.complete([]);
      await tester.pump();
    });

    testUi('加载完成：本楼 + 「相关回复」分隔标签 + 回复，加载指示消失', (tester) async {
      final reply = readingPost(
        5,
        username: 'amex_plat',
        name: '示例用户乙',
        cooked: '<p>示例数据：一条相关回复。</p>',
        replyTo: 4,
      );
      await _openSheet(
        tester,
        readingFakeService(
          ids: () async => [reply.id],
          posts: () async => [reply],
        ),
        readingPost(4, cooked: '<p>示例数据：本楼的完整正文。</p>'),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(LoadingHint), findsNothing);
      expect(find.text('#4 帖子详情'), findsOneWidget);
      // 分隔标签：13 meta 的「相关回复」，数量放进朗读标签
      final label = tester.widget<Text>(find.text('相关回复'));
      expect(label.style!.fontSize, 13);
      final tokens = AppTokens.of(tester.element(find.text('相关回复')));
      expect(label.style!.color, tokens.colors.textMeta);
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('相关回复共 1 条'), findsOneWidget);
      handle.dispose();
      // 本楼与回复的正文都在，且正文 17 号
      final renders = tester
          .widgetList<FluxdoRender>(find.byType(FluxdoRender))
          .toList();
      expect(
        renders.any((w) => w.cookedHtml.contains('本楼的完整正文')),
        isTrue,
      );
      expect(
        renders.any((w) => w.cookedHtml.contains('一条相关回复')),
        isTrue,
      );
      for (final r in renders) {
        expect(r.baseTextStyle!.fontSize, 17);
      }
      // 回复排在本楼下面、标签在两者之间
      final labelTop = tester.getTopLeft(find.text('相关回复')).dy;
      final replyTop = tester.getTopLeft(find.text('示例用户乙')).dy;
      expect(replyTop, greaterThan(labelTop));
      expectNoUiException(tester);
    });

    testUi('没有回复时不出「相关回复」标签', (tester) async {
      await _openSheet(
        tester,
        readingFakeService(ids: () async => [], posts: () async => []),
        readingPost(4),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(LoadingHint), findsNothing);
      expect(find.text('相关回复'), findsNothing);
    });

    testUi('请求失败：原位显示错误和「重试」，点重试回到加载态', (tester) async {
      var calls = 0;
      final retry = Completer<List<int>>();
      await _openSheet(
        tester,
        readingFakeService(
          ids: () {
            calls++;
            if (calls == 1) {
              throw DioException(requestOptions: RequestOptions());
            }
            return retry.future;
          },
          posts: () async => [],
        ),
        readingPost(4),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('重试'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pump();
      expect(find.byType(LoadingHint), findsOneWidget);
      expect(calls, 2);
      retry.complete([]);
      await tester.pump();
    });
  });

  group('相关链接在楼层里的位置（09）', () {
    testUi('链接行在点赞 / 操作栏下面，不在正文和操作栏之间', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await pumpUi(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: PostItem(
              post: readingPost(
                1,
                likes: 21,
                linkCounts: [
                  reflectionLink(
                    '示例链接标题一',
                    'https://example.com/t/a/101',
                  ),
                ],
              ),
              topicId: 1001,
              isTopicOwner: true,
              onReply: ({String? initialContent}) {},
            ),
          ),
        ),
        overrides: readingOverrides(prefs),
      );
      final bar = tester.getRect(find.byType(PostActionBar));
      final links = tester.getRect(find.byType(PostLinks));
      expect(links.top, greaterThanOrEqualTo(bar.bottom));
      expect(find.text('相关链接'), findsOneWidget);
      expect(find.text('示例链接标题一'), findsNothing);
      expectNoUiException(tester);
    });
  });

  group('首帖多图（20）', () {
    // 两张大图（宽高比 4:3）+ 一张小图（不放大）
    const cooked = '''
<p><img src="https://example.com/a.jpg" alt="a" width="800" height="600"></p>
<p><img src="https://example.com/b.jpg" alt="b" width="1200" height="900"></p>
<p><img src="https://example.com/c.jpg" alt="c" width="100" height="60"></p>
''';

    Future<List<Rect>> pumpImages(WidgetTester tester) async {
      await pumpUi(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.pageMargin),
            child: FluxdoRenderCallbacks.generic(
              heroTagNamespace: 'final4_images',
            ).render(cookedHtml: cooked, selectionEnabled: false),
          ),
        ),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 300));
      return [
        for (final e in find.byType(LazyImage).evaluate())
          (e.renderObject! as RenderBox).localToGlobal(Offset.zero) &
              (e.renderObject! as RenderBox).size,
      ];
    }

    testUi('每张大图整宽、纵向排列，互不并排', (tester) async {
      final rects = await pumpImages(tester);
      expect(rects.length, 3);
      final column = UiDevice.proMax.size.width - 2 * AppSpace.pageMargin;
      expect(rects[0].width, column);
      expect(rects[1].width, column);
      // 4:3 等比
      expect(rects[0].height, closeTo(column * 600 / 800, 0.5));
      expect(rects[1].height, closeTo(column * 900 / 1200, 0.5));
      // 同一左缘、自上而下排列
      expect(rects[1].left, rects[0].left);
      expect(rects[1].top, greaterThanOrEqualTo(rects[0].bottom));
      expect(rects[2].top, greaterThanOrEqualTo(rects[1].bottom));
      expectNoUiException(tester);
    });

    testUi('小图保持原尺寸，不上采样放大', (tester) async {
      final rects = await pumpImages(tester);
      expect(rects[2].width, 100);
      expect(rects[2].height, 60);
    });

    testUi('图片圆角 12（随圆角档的 card 圆角），裁在图外层', (tester) async {
      await pumpImages(tester);
      final tokens = AppTokens.of(tester.element(find.byType(LazyImage).first));
      final clip = tester.widget<ClipRRect>(
        find
            .ancestor(
              of: find.byType(LazyImage).first,
              matching: find.byType(ClipRRect),
            )
            .first,
      );
      expect(clip.borderRadius, BorderRadius.circular(tokens.radius.card));
      expect(tokens.radius.card, 12);
    });

    testUi('点图仍然可点（手势没有被圆角裁剪层吃掉）', (tester) async {
      await pumpImages(tester);
      final lazy = tester.widget<LazyImage>(find.byType(LazyImage).first);
      expect(lazy.onTap, isNotNull);
      expect(find.byIcon(AppIcons.image), findsNothing);
    });
  });
}
