import 'package:fluxdo/models/category.dart';
import 'package:fluxdo/models/notification.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/models/user.dart';

// 界面测试夹具：按 Discourse 接口的 JSON 形状手写，再走各 model 的
// fromJson，解析路径和真实数据一致。全部本地数据，不碰网络。
//
// 时间相对「现在」生成（UTC ISO 字符串），这样相对时间的显示
// （「3 分钟前」「2 天前」）每次运行都稳定。头像模板留空，
// 统一显示字母头像，测试里不会去加载网络图片。

/// 当前时间往前推 [ago]，返回接口格式的 UTC 时间串
String fixtureTime(Duration ago) =>
    DateTime.now().toUtc().subtract(ago).toIso8601String();

const fixtureUsersJson = <Map<String, dynamic>>[
  {'id': 1, 'username': 'chase_fan', 'name': '张三', 'avatar_template': ''},
  {'id': 2, 'username': 'amex_plat', 'name': '李四', 'avatar_template': ''},
  {'id': 3, 'username': 'pointsguy', 'name': '', 'avatar_template': ''},
  {'id': 4, 'username': 'Wanderer', 'name': '王五', 'avatar_template': ''},
  {'id': 5, 'username': 'datapoint', 'name': '', 'avatar_template': ''},
];

final fixtureCategoriesJson = <Map<String, dynamic>>[
  {'id': 1, 'name': '信用卡', 'slug': 'credit-card', 'color': '0088CC'},
  {'id': 2, 'name': '银行账户', 'slug': 'bank', 'color': '12A89D'},
  {'id': 3, 'name': '旅行', 'slug': 'travel', 'color': 'F7941D'},
  {'id': 4, 'name': '闲聊', 'slug': 'chat', 'color': '808281'},
  {'id': 5, 'name': '数据点', 'slug': 'dp', 'color': 'BF1E2E'},
  {
    'id': 11,
    'name': 'Chase',
    'slug': 'chase',
    'color': '0088CC',
    'parent_category_id': 1,
  },
];

List<Category> fixtureCategories() =>
    fixtureCategoriesJson.map(Category.fromJson).toList();

List<Map<String, dynamic>> _topicsJson() => [
  {
    'id': 1001,
    'title': '【DP】Chase Sapphire Reserve 新开卡奖励 125k，附申请时间线',
    'slug': 'csr-125k',
    'posts_count': 86,
    'reply_count': 85,
    'views': 5320,
    'like_count': 142,
    'created_at': fixtureTime(const Duration(hours: 5)),
    'last_posted_at': fixtureTime(const Duration(minutes: 3)),
    'last_poster_username': 'amex_plat',
    'category_id': 11,
    'pinned': true,
    'tags': ['chase', 'csr'],
    'unseen': false,
    'unread_posts': 0,
    'new_posts': 4,
    'last_read_post_number': 82,
    'highest_post_number': 86,
    'posters': [
      {'user_id': 1, 'description': '原始发帖人'},
      {'user_id': 2, 'description': '最新发帖人'},
      {'user_id': 3, 'description': '频繁发帖人'},
    ],
  },
  {
    'id': 1002,
    'title': 'Amex 白金卡年费上涨后还值不值得留？',
    'slug': 'amex-plat-fee',
    'posts_count': 240,
    'reply_count': 239,
    'views': 18200,
    'like_count': 510,
    'created_at': fixtureTime(const Duration(days: 3)),
    'last_posted_at': fixtureTime(const Duration(hours: 1)),
    'last_poster_username': 'pointsguy',
    'category_id': 1,
    'tags': ['amex'],
    'unseen': false,
    'last_read_post_number': 240,
    'highest_post_number': 240,
    'posters': [
      {'user_id': 2, 'description': '原始发帖人'},
      {'user_id': 3, 'description': '最新发帖人'},
    ],
  },
  {
    'id': 1003,
    'title': '新人求助：没有 SSN 怎么开第一张卡',
    'slug': 'no-ssn-first-card',
    'posts_count': 1,
    'reply_count': 0,
    'views': 12,
    'like_count': 0,
    'created_at': fixtureTime(const Duration(minutes: 20)),
    'last_posted_at': fixtureTime(const Duration(minutes: 20)),
    'last_poster_username': 'Wanderer',
    'category_id': 2,
    'unseen': true,
    'highest_post_number': 1,
    'posters': [
      {'user_id': 4, 'description': '原始发帖人, 最新发帖人'},
    ],
  },
  {
    'id': 1004,
    'title':
        '一个特别长的标题，用来检查两行截断：从旧金山飞东京转机去曼谷，用 Hyatt 积分订了三晚，结果到店被告知房型不对，最后怎么处理的',
    'slug': 'long-title',
    'posts_count': 33,
    'reply_count': 32,
    'views': 2048,
    'like_count': 27,
    'created_at': fixtureTime(const Duration(days: 40)),
    'last_posted_at': fixtureTime(const Duration(days: 2)),
    'last_poster_username': 'datapoint',
    'category_id': 3,
    'closed': true,
    'tags': ['hyatt', 'travel', 'dp'],
    'last_read_post_number': 10,
    'highest_post_number': 33,
    'unread_posts': 23,
    'posters': [
      {'user_id': 4, 'description': '原始发帖人'},
      {'user_id': 5, 'description': '最新发帖人'},
    ],
  },
  {
    'id': 1005,
    'title': '周末闲聊楼',
    'slug': 'weekend',
    'posts_count': 1203,
    'reply_count': 1202,
    'views': 99000,
    'like_count': 3400,
    'created_at': fixtureTime(const Duration(days: 400)),
    'last_posted_at': fixtureTime(const Duration(seconds: 30)),
    'last_poster_username': 'chase_fan',
    'category_id': 4,
    'archived': false,
    'highest_post_number': 1203,
    'posters': [
      {'user_id': 3, 'description': '原始发帖人'},
      {'user_id': 1, 'description': '最新发帖人'},
    ],
  },
];

/// 首页话题列表（含置顶、未读、新话题、已关闭、超长标题）
List<Topic> fixtureTopics() => TopicListResponse.fromJson({
  'users': fixtureUsersJson,
  'topic_list': {'topics': _topicsJson()},
}).topics;

const _cookedOp = '''
<p>上周五在线申请，秒批。记一下时间线给后来的人参考：</p>
<ul>
<li>10/20 申请，秒批，额度 15k</li>
<li>10/22 收到实体卡</li>
<li>10/28 达标，奖励 125k 还没进账</li>
</ul>
<blockquote>
<p>注意：5/24 规则依然适用，过去 24 个月开了 5 张以上个人卡会被拒。</p>
</blockquote>
<p>另外 <a href="https://example.com/terms">条款原文</a> 里写的最低消费是三个月 6000。</p>
''';

const _cookedTable = '''
<p>几张卡的对比：</p>
<div class="md-table"><table>
<thead><tr><th>卡</th><th>年费</th><th>开卡奖励</th></tr></thead>
<tbody>
<tr><td>CSR</td><td>\$795</td><td>125k</td></tr>
<tr><td>CSP</td><td>\$95</td><td>75k</td></tr>
<tr><td>Amex Plat</td><td>\$895</td><td>175k</td></tr>
</tbody>
</table></div>
<pre><code class="lang-text">UR 点数 1.5 cpp × 125k = \$1875</code></pre>
''';

Map<String, dynamic> _postJson(
  int number, {
  required int userId,
  required String cooked,
  required Duration ago,
  int likes = 0,
  int replyTo = 0,
}) {
  final user = fixtureUsersJson.firstWhere((u) => u['id'] == userId);
  return {
    'id': 50000 + number,
    'username': user['username'],
    'name': user['name'],
    'avatar_template': '',
    'cooked': cooked,
    'post_number': number,
    'post_type': 1,
    'created_at': fixtureTime(ago),
    'updated_at': fixtureTime(ago),
    'like_count': likes,
    'reply_count': 0,
    'reply_to_post_number': replyTo,
    'user_id': userId,
    'read': true,
    'can_edit': userId == 1,
  };
}

/// 阅读页话题详情：楼主帖（列表 + 引用 + 链接）、表格和代码、普通回复
TopicDetail fixtureTopicDetail({int replies = 6}) {
  final posts = <Map<String, dynamic>>[
    _postJson(
      1,
      userId: 1,
      cooked: _cookedOp,
      ago: const Duration(hours: 5),
      likes: 16,
    ),
    _postJson(
      2,
      userId: 2,
      cooked: _cookedTable,
      ago: const Duration(hours: 4),
      likes: 3,
    ),
    for (var i = 3; i < replies + 3; i++)
      _postJson(
        i,
        userId: fixtureUsersJson[i % fixtureUsersJson.length]['id'] as int,
        cooked: '<p>第 $i 楼：恭喜！我也是这周批的，奖励还没到账，再等等看。</p>',
        ago: Duration(minutes: 200 - i * 10),
        likes: i % 3,
        replyTo: i.isEven ? 1 : 0,
      ),
  ];
  return TopicDetail.fromJson({
    'id': 1001,
    'title': _topicsJson().first['title'],
    'slug': 'csr-125k',
    'posts_count': posts.length,
    'category_id': 11,
    'tags': ['chase', 'csr'],
    'views': 5320,
    'like_count': 142,
    'created_at': fixtureTime(const Duration(hours: 5)),
    'highest_post_number': posts.length,
    'last_read_post_number': 2,
    'post_stream': {
      'posts': posts,
      'stream': [for (final p in posts) p['id']],
    },
    'details': {
      'created_by': fixtureUsersJson[0],
      'last_poster': fixtureUsersJson[1],
    },
  });
}

Map<String, dynamic> _notificationJson(
  int id, {
  required int type,
  required Duration ago,
  bool read = false,
  Map<String, dynamic> data = const {},
}) => {
  'id': id,
  'user_id': 99,
  'notification_type': type,
  'read': read,
  'created_at': fixtureTime(ago),
  'topic_id': 1001,
  'post_number': 3,
  'slug': 'csr-125k',
  'fancy_title': 'Chase Sapphire Reserve 新开卡奖励 125k',
  'data': {'topic_title': 'Chase Sapphire Reserve 新开卡奖励 125k', ...data},
};

/// 通知列表：回复、提及、点赞（合并）、私信、徽章，已读未读混合
List<DiscourseNotification> fixtureNotifications() => [
  _notificationJson(
    1,
    type: NotificationType.replied.id,
    ago: const Duration(minutes: 2),
    data: {'display_username': 'amex_plat'},
  ),
  _notificationJson(
    2,
    type: NotificationType.mentioned.id,
    ago: const Duration(hours: 1),
    data: {'display_username': 'pointsguy'},
  ),
  _notificationJson(
    3,
    type: NotificationType.likedConsolidated.id,
    ago: const Duration(hours: 6),
    read: true,
    data: {'display_username': 'datapoint', 'count': 12},
  ),
  _notificationJson(
    4,
    type: NotificationType.privateMessage.id,
    ago: const Duration(days: 1),
    data: {
      'display_username': 'Wanderer',
      'topic_title': '关于你上次说的那个 retention offer',
    },
  ),
  _notificationJson(
    5,
    type: NotificationType.grantedBadge.id,
    ago: const Duration(days: 9),
    read: true,
    data: {'badge_name': '优秀回复', 'badge_id': 7, 'badge_slug': 'nice-reply'},
  ),
].map(DiscourseNotification.fromJson).toList();

/// 「我的」页用户
User fixtureUser() => User.fromJson({
  'id': 99,
  'username': 'hao',
  'name': '测试用户',
  'avatar_template': '',
  'trust_level': 2,
  'unread_notifications': 2,
});
