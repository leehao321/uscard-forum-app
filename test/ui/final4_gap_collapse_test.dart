import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/topic_post_list.dart'
    show RevealedGapHeader;
import 'package:fluxdo/providers/topic_detail_provider.dart';

import 'support/ui_harness.dart';

// 补充稿 18：展开隐藏回复后，顶部出现「已显示隐藏的回复 · 收起」，
// 点收起只在本地把这批楼层重新折叠，不发请求。

Post _post(int id, int number) => Post(
  id: id,
  postNumber: number,
  username: 'tester',
  avatarTemplate: '',
  createdAt: DateTime(2026, 5, 15),
  updatedAt: DateTime(2026, 5, 15),
  cooked: '<p>test</p>',
  postType: 1,
  replyCount: 0,
  likeCount: 0,
  replyToPostNumber: 0,
  canEdit: false,
  canDelete: false,
  canRecover: false,
  canWiki: false,
  linkCounts: const [],
);

TopicDetail _detail({
  required List<Post> posts,
  required List<int> stream,
  PostStreamGaps? gaps,
}) => TopicDetail(
  id: 1,
  title: 'Topic',
  slug: 'topic',
  postsCount: stream.length,
  postStream: PostStream(posts: posts, stream: stream, gaps: gaps),
  categoryId: 1,
  closed: false,
  archived: false,
);

List<int> _ids(TopicDetail d) => d.postStream.posts.map((p) => p.id).toList();

void main() {
  group('展开 / 收起隐藏回复（18）', () {
    // 本地有 #1、#4；#4 前面被折叠了 #2、#3（#2 已在 stream 里，#3 不在）
    TopicDetail folded() => _detail(
      posts: [_post(10, 1), _post(40, 4)],
      stream: [10, 20, 40],
      gaps: const PostStreamGaps(
        before: {
          40: [20, 30],
        },
      ),
    );

    test('展开：楼层并进列表，gap 条目换成展开记录', () {
      final opened = revealGapInDetail(
        folded(),
        40,
        before: true,
        gapPostIds: const [20, 30],
        newPosts: [_post(20, 2), _post(30, 3)],
      );
      expect(_ids(opened), [10, 20, 30, 40]);
      expect(opened.postStream.stream, [10, 20, 40, 30]);
      final gaps = opened.postStream.gaps!;
      expect(gaps.before, isEmpty);
      expect(gaps.revealedBefore[40]!.insertedPostIds, [20, 30]);
      expect(gaps.revealedBefore[40]!.addedStreamIds, [30]);
    });

    test('收起：楼层重新隐藏，stream 与 gap 条目还原，不需要任何请求', () {
      final opened = revealGapInDetail(
        folded(),
        40,
        before: true,
        gapPostIds: const [20, 30],
        newPosts: [_post(20, 2), _post(30, 3)],
      );
      final closed = collapseGapInDetail(opened, 40, before: true)!;
      expect(_ids(closed), [10, 40]);
      expect(closed.postStream.stream, [10, 20, 40]);
      final gaps = closed.postStream.gaps!;
      expect(gaps.before[40], [20, 30]);
      expect(gaps.revealedBefore, isEmpty);
    });

    test('收起后可以再次展开（记录不残留）', () {
      final opened = revealGapInDetail(
        folded(),
        40,
        before: true,
        gapPostIds: const [20, 30],
        newPosts: [_post(20, 2), _post(30, 3)],
      );
      final closed = collapseGapInDetail(opened, 40, before: true)!;
      final again = revealGapInDetail(
        closed,
        40,
        before: true,
        gapPostIds: closed.postStream.gaps!.before[40]!,
        newPosts: [_post(20, 2), _post(30, 3)],
      );
      expect(_ids(again), [10, 20, 30, 40]);
      expect(again.postStream.gaps!.revealedBefore.keys, [40]);
    });

    test('after 方向：楼层展开在锚点后面，收起后消失', () {
      final detail = _detail(
        posts: [_post(10, 1)],
        stream: [10],
        gaps: const PostStreamGaps(
          after: {
            10: [20],
          },
        ),
      );
      final opened = revealGapInDetail(
        detail,
        10,
        before: false,
        gapPostIds: const [20],
        newPosts: [_post(20, 2)],
      );
      expect(_ids(opened), [10, 20]);
      expect(opened.postStream.gaps!.revealedAfter[10], isNotNull);
      final closed = collapseGapInDetail(opened, 10, before: false)!;
      expect(_ids(closed), [10]);
      expect(closed.postStream.gaps!.after[10], [20]);
    });

    test('没有展开记录时收起什么也不做（返回 null）', () {
      expect(collapseGapInDetail(folded(), 40, before: true), isNull);
      expect(
        collapseGapInDetail(
          _detail(posts: [_post(10, 1)], stream: [10]),
          10,
          before: true,
        ),
        isNull,
      );
    });

    testUi('顶部提示行：「已显示隐藏的回复」+「收起」，点收起回调一次', (tester) async {
      var taps = 0;
      await pumpUi(
        tester,
        Scaffold(body: RevealedGapHeader(onCollapse: () => taps++)),
      );
      expect(find.text('已显示隐藏的回复'), findsOneWidget);
      expect(find.text('收起'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('revealed_gap_collapse')));
      expect(taps, 1);
    });
  });
}
