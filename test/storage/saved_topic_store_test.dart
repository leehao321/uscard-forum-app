import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/storage/saved_topic_store.dart';

SavedPost _post(int n, String cooked) => SavedPost(
  postId: 100 + n,
  postNumber: n,
  username: 'user$n',
  cooked: cooked,
);

String _plain(String html) => html.replaceAll(RegExp(r'<[^>]*>'), '');

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('saved_topics_test');
    SavedTopicStore.debugDirectory = tmp;
  });

  tearDown(() async {
    SavedTopicStore.debugDirectory = null;
    await tmp.delete(recursive: true);
  });

  test('保存后能列出、读取，再次保存按楼层号合并', () async {
    await SavedTopicStore.save(
      topicId: 7,
      title: 'Chase Sapphire 开卡奖励',
      posts: [_post(1, '<p>首帖内容</p>'), _post(2, '<p>二楼</p>')],
      plainTextOf: _plain,
    );
    await SavedTopicStore.save(
      topicId: 7,
      title: 'Chase Sapphire 开卡奖励',
      posts: [_post(2, '<p>二楼（编辑后）</p>'), _post(3, '<p>三楼</p>')],
      plainTextOf: _plain,
    );

    final list = await SavedTopicStore.list();
    expect(list, hasLength(1));
    expect(list.single.postCount, 3);
    expect(list.single.searchText, contains('chase sapphire'));
    expect(list.single.searchText, contains('三楼'));

    final topic = await SavedTopicStore.load(7);
    expect(topic!.posts.map((e) => e.postNumber), [1, 2, 3]);
    expect(topic.posts[1].cooked, contains('编辑后'));
  });

  test('删除和清空', () async {
    for (final id in [1, 2]) {
      await SavedTopicStore.save(
        topicId: id,
        title: 't$id',
        posts: [_post(1, '<p>x</p>')],
        plainTextOf: _plain,
      );
    }
    await SavedTopicStore.delete(1);
    expect((await SavedTopicStore.list()).map((e) => e.topicId), [2]);
    expect(await SavedTopicStore.load(1), isNull);

    await SavedTopicStore.clear();
    expect(await SavedTopicStore.list(), isEmpty);
  });

  test('索引损坏时按话题文件重建', () async {
    await SavedTopicStore.save(
      topicId: 9,
      title: '重建',
      posts: [_post(1, '<p>x</p>')],
      plainTextOf: _plain,
    );
    final index = File('${tmp.path}${Platform.pathSeparator}saved_topics'
        '${Platform.pathSeparator}index.json');
    await index.writeAsString('不是 json');

    final list = await SavedTopicStore.list();
    expect(list.single.topicId, 9);
  });
}
