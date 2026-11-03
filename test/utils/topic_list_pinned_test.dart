import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/providers/topic_list/filter_provider.dart';
import 'package:fluxdo/utils/topic_list_updates.dart';

Topic _topic(int id, {bool pinned = false}) => Topic(
  id: id,
  title: 'topic $id',
  slug: 'topic-$id',
  postsCount: 1,
  replyCount: 0,
  views: 0,
  likeCount: 0,
  categoryId: '1',
  pinned: pinned,
  tags: const [],
  posters: const [],
  unseen: false,
  unread: 0,
  lastReadPostNumber: null,
  highestPostNumber: 1,
);

List<int> _ids(List<Topic> topics) => topics.map((t) => t.id).toList();

void main() {
  group('新帖不能越过置顶', () {
    final current = [
      _topic(1, pinned: true),
      _topic(2, pinned: true),
      _topic(10),
      _topic(11),
    ];

    test('新帖插在置顶之后、普通帖之前', () {
      final result = prependTopicUpdates(current, [_topic(20), _topic(21)]);
      expect(_ids(result), [1, 2, 20, 21, 10, 11]);
    });

    test('普通帖有新回复，提到普通帖最前，仍在置顶之后', () {
      final result = prependTopicUpdates(current, [_topic(11)]);
      expect(_ids(result), [1, 2, 11, 10]);
    });

    test('置顶帖有新回复，留在原来的位置', () {
      final result = prependTopicUpdates(current, [_topic(2, pinned: true)]);
      expect(_ids(result), [1, 2, 10, 11]);
    });

    test('置顶帖的更新内容会替换旧数据', () {
      final updated = _topic(2, pinned: true).copyWith(unread: 5);
      final result = prependTopicUpdates(current, [updated]);
      expect(result[1].unread, 5);
    });

    test('新置顶的帖子进置顶区，排在已有置顶之后', () {
      final result = prependTopicUpdates(current, [
        _topic(20),
        _topic(11, pinned: true),
      ]);
      expect(_ids(result), [1, 2, 11, 20, 10]);
    });

    test('被取消置顶的帖子回到普通帖最前', () {
      final result = prependTopicUpdates(current, [_topic(2)]);
      expect(_ids(result), [1, 2, 10, 11]);
      expect(result[1].pinned, isFalse);
    });

    test('没有置顶时行为不变', () {
      final result = prependTopicUpdates(
        [_topic(10), _topic(11)],
        [_topic(20), _topic(11)],
      );
      expect(_ids(result), [20, 11, 10]);
    });

    test('自定义排序下夹在中间的置顶帖不被提到最前', () {
      final result = prependTopicUpdates(
        [_topic(10), _topic(1, pinned: true), _topic(11)],
        [_topic(20)],
      );
      expect(_ids(result), [20, 10, 1, 11]);
    });

    test('连续多次推入，置顶都不动', () {
      var list = current;
      for (final id in [30, 31, 32]) {
        list = prependTopicUpdates(list, [_topic(id)]);
      }
      expect(_ids(list).take(2), [1, 2]);
      expect(_ids(list), [1, 2, 32, 31, 30, 10, 11]);
    });
  });

  group('置顶分流', () {
    test('按最新回复排序把置顶打散了：分流回最前面，各自顺序不变', () {
      final list = [_topic(10), _topic(1, pinned: true), _topic(11), _topic(2, pinned: true)];
      expect(_ids(pinnedFirst(list)), [1, 2, 10, 11]);
    });

    test('已经是正确顺序：返回原列表，不做无谓的重建', () {
      final list = [_topic(1, pinned: true), _topic(10)];
      expect(identical(pinnedFirst(list), list), isTrue);
    });

    test('默认和最新回复排序才锁，排行类和待办类不锁', () {
      expect(shouldLockPinned(TopicListFilter.latest, null), isTrue);
      expect(shouldLockPinned(TopicListFilter.latest, 'activity'), isTrue);
      expect(shouldLockPinned(TopicListFilter.latest, 'views'), isFalse);
      expect(shouldLockPinned(TopicListFilter.latest, 'likes'), isFalse);
      expect(shouldLockPinned(TopicListFilter.unread, null), isFalse);
      expect(shouldLockPinned(TopicListFilter.newTopics, null), isFalse);
    });
  });

  group('置顶折叠', () {
    final three = [
      _topic(1, pinned: true),
      _topic(2, pinned: true),
      _topic(3, pinned: true),
      _topic(4, pinned: true),
      _topic(10),
    ];

    test('不超过两条：不折叠，没有开关', () {
      final list = [_topic(1, pinned: true), _topic(2, pinned: true), _topic(10)];
      final fold = PinnedFold.apply(list, expanded: false);
      expect(identical(fold.topics, list), isTrue);
      expect(fold.toggleIndex, isNull);
    });

    test('超过两条默认收起：露前两条，开关在第二条下面', () {
      final fold = PinnedFold.apply(three, expanded: false);
      expect(_ids(fold.topics), [1, 2, 10]);
      expect(fold.toggleIndex, 1);
      expect(fold.hiddenCount, 2);
    });

    test('展开：全部显示，开关在最后一条置顶下面', () {
      final fold = PinnedFold.apply(three, expanded: true);
      expect(_ids(fold.topics), [1, 2, 3, 4, 10]);
      expect(fold.toggleIndex, 3);
      expect(fold.hiddenCount, 0);
    });
  });
}
