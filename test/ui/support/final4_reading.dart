import 'dart:async';

import 'package:ai_model_manager/ai_model_manager.dart'
    show aiSharedPreferencesProvider;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart' show Fake;
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/providers/category_provider.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/message_bus/topic_tracking_providers.dart';
import 'package:fluxdo/providers/theme_provider.dart'
    show sharedPreferencesProvider;
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

// 第 11 批 11b-1（阅读页与话题 09–20）的测试底座：
// 假用户 / 假追踪状态 / 帖子夹具。全部本地数据，不联网。

class FakeNoUser extends CurrentUserNotifier {
  @override
  FutureOr<User?> build() => null;
}

class FakeTracking extends TopicTrackingStateNotifier {
  @override
  Map<int, TrackedTopicState> build() => const {};
}

class FakeMessageBusInit extends MessageBusInitNotifier {
  @override
  void build() {}
}

/// 阅读页组件需要的 provider 覆盖
List<Override> readingOverrides(SharedPreferences prefs) => [
  sharedPreferencesProvider.overrideWithValue(prefs),
  aiSharedPreferencesProvider.overrideWithValue(prefs),
  categoriesProvider.overrideWith((ref) async => fixtureCategories()),
  currentUserProvider.overrideWith(FakeNoUser.new),
  messageBusInitProvider.overrideWith(FakeMessageBusInit.new),
  topicTrackingStateProvider.overrideWith(FakeTracking.new),
];

/// 按 Discourse 接口形状手写一个帖子
Post readingPost(
  int number, {
  String username = 'chase_fan',
  String? name,
  String cooked = '<p>示例数据：这是一条正文。</p>',
  Duration ago = const Duration(hours: 3),
  int likes = 0,
  int replyTo = 0,
  Map<String, dynamic>? replyToUser,
  List<Map<String, dynamic>>? linkCounts,
  int replyCount = 0,
}) => Post.fromJson({
  'id': 60000 + number,
  'username': username,
  'name': name ?? '',
  'avatar_template': '',
  'cooked': cooked,
  'post_number': number,
  'post_type': 1,
  'created_at': fixtureTime(ago),
  'updated_at': fixtureTime(ago),
  'like_count': likes,
  'reply_count': replyCount,
  'reply_to_post_number': replyTo,
  'reply_to_user': ?replyToUser,
  'user_id': 1,
  'read': true,
  'link_counts': ?linkCounts,
});

/// 一条站内入站链接
Map<String, dynamic> reflectionLink(String title, String url, {int clicks = 0}) => {
  'url': url,
  'internal': true,
  'reflection': true,
  'title': title,
  'clicks': clicks,
};

/// 帖子详情半屏用到的三个请求
class FakeRepliesService extends Fake implements DiscourseService {
  FakeRepliesService({this.ids, this.posts});

  final Future<List<int>> Function()? ids;
  final Future<List<Post>> Function()? posts;

  @override
  Future<List<int>> getPostReplyIds(int postId) => ids!();

  @override
  Future<PostStream> getPosts(
    int topicId,
    List<int> postIds, {
    includeSuggested = false,
    quiet,
  }) async {
    final list = await posts!();
    return PostStream(posts: list, stream: [for (final p in list) p.id]);
  }

  @override
  Future<List<Post>> getPostReplies(int postId, {int after = 1}) async =>
      posts!();
}

/// 帖子详情半屏用的假服务
DiscourseService readingFakeService({
  Future<List<int>> Function()? ids,
  Future<List<Post>> Function()? posts,
}) => FakeRepliesService(ids: ids, posts: posts);
