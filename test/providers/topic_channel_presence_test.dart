import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/message_bus/message_bus_service_provider.dart';
import 'package:fluxdo/providers/message_bus/models.dart';
import 'package:fluxdo/providers/message_bus/topic_channel_provider.dart';
import 'package:fluxdo/providers/message_bus/topic_tracking_providers.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:fluxdo/services/message_bus_service.dart';
import 'package:fluxdo/services/preloaded_data_service.dart';

// 0.4.0 M9.7 / P-4、P-5：
// - 只有已登录且站点启用 presence 时才订阅 presence 频道、请求 /presence/get；
// - /topic/:id 等详情加载完再订阅，带 message_bus_last_id；
// - 退出后 30 秒内重进同一帖不重新订阅。
// 服务全是假的，不请求论坛。

class _Bus extends Fake implements MessageBusService {
  final List<({String channel, int lastMessageId})> subscribed = [];
  final List<String> unsubscribed = [];

  @override
  void subscribe(
    String channel,
    MessageBusCallback callback, {
    int lastMessageId = -1,
  }) {
    subscribed.add((channel: channel, lastMessageId: lastMessageId));
  }

  @override
  void subscribeWithMessageId(
    String channel,
    MessageBusCallback callback,
    int messageId,
  ) {
    subscribed.add((channel: channel, lastMessageId: messageId));
  }

  @override
  void unsubscribe(String channel, [MessageBusCallback? callback]) {
    unsubscribed.add(channel);
  }
}

class _Service extends Fake implements DiscourseService {
  _Service({required this.authenticated});

  final bool authenticated;
  int presenceCalls = 0;

  @override
  bool get isAuthenticated => authenticated;

  @override
  Future<PresenceResponse> getPresence(int topicId) async {
    presenceCalls++;
    return const PresenceResponse(users: [], messageId: 42);
  }
}

class _FakeMessageBusInit extends MessageBusInitNotifier {
  @override
  void build() {}
}

ProviderContainer _container(_Bus bus, _Service service) => ProviderContainer(
  retry: (_, _) => null,
  overrides: [
    messageBusServiceProvider.overrideWithValue(bus),
    discourseServiceProvider.overrideWithValue(service),
    messageBusInitProvider.overrideWith(_FakeMessageBusInit.new),
  ],
);

Iterable<String> _channels(_Bus bus) => bus.subscribed.map((s) => s.channel);

void main() {
  const presenceChannel = '/presence/discourse-presence/reply/7';

  tearDown(() => PreloadedDataService().debugSeed());

  test('未登录：不订阅 presence、不请求 /presence/get', () async {
    PreloadedDataService().debugSeed(siteSettings: {'presence_enabled': true});
    final bus = _Bus();
    final service = _Service(authenticated: false);
    final c = _container(bus, service);
    addTearDown(c.dispose);
    final sub = c.listen(topicChannelProvider(7), (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(_channels(bus), isNot(contains(presenceChannel)));
    expect(service.presenceCalls, 0);
    sub.close();
  });

  test('站点没开 presence：已登录也不订阅、不请求', () async {
    PreloadedDataService().debugSeed(siteSettings: {'presence_enabled': false});
    final bus = _Bus();
    final service = _Service(authenticated: true);
    final c = _container(bus, service);
    addTearDown(c.dispose);
    final sub = c.listen(topicChannelProvider(7), (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(_channels(bus), isNot(contains(presenceChannel)));
    expect(service.presenceCalls, 0);
    sub.close();
  });

  test('已登录且站点开了 presence：订阅并拉一次初始状态', () async {
    PreloadedDataService().debugSeed(siteSettings: {'presence_enabled': true});
    final bus = _Bus();
    final service = _Service(authenticated: true);
    final c = _container(bus, service);
    addTearDown(c.dispose);
    final sub = c.listen(topicChannelProvider(7), (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(_channels(bus), contains(presenceChannel));
    expect(service.presenceCalls, 1);
    sub.close();
  });

  test('/topic/:id 等详情加载完再订阅，带 message_bus_last_id', () async {
    PreloadedDataService().debugSeed(siteSettings: {'presence_enabled': false});
    final bus = _Bus();
    final c = _container(bus, _Service(authenticated: true));
    addTearDown(c.dispose);
    final sub = c.listen(topicChannelProvider(7), (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(_channels(bus), isNot(contains('/topic/7')), reason: '详情没加载完先不订阅');

    c.read(topicChannelProvider(7).notifier).attachTopicChannel(1234);
    c.read(topicChannelProvider(7).notifier).attachTopicChannel(1234);
    final topicSubs = bus.subscribed.where((s) => s.channel == '/topic/7');
    expect(topicSubs.length, 1, reason: '重复 attach 不重复订阅');
    expect(topicSubs.single.lastMessageId, 1234);
    sub.close();
  });

  test('TopicDetail 解析 message_bus_last_id', () {
    final detail = TopicDetail.fromJson({
      'id': 7,
      'title': 't',
      'slug': 't',
      'posts_count': 1,
      'message_bus_last_id': 5678,
      'post_stream': {'posts': <dynamic>[], 'stream': <dynamic>[]},
    });
    expect(detail.messageBusLastId, 5678);
    expect(detail.copyWith().messageBusLastId, 5678);
  });

  test('退出后 30 秒内重进同一帖：不重新订阅，也不再拉 presence', () async {
    PreloadedDataService().debugSeed(siteSettings: {'presence_enabled': true});
    final bus = _Bus();
    final service = _Service(authenticated: true);
    final c = _container(bus, service);
    addTearDown(c.dispose);

    var sub = c.listen(topicChannelProvider(7), (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final before = bus.subscribed.length;
    expect(service.presenceCalls, 1);

    sub.close(); // 退出帖子
    await Future<void>.delayed(const Duration(milliseconds: 20));
    sub = c.listen(topicChannelProvider(7), (_, _) {}); // 30 秒内重进
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(bus.subscribed.length, before, reason: '没有新的订阅');
    expect(service.presenceCalls, 1, reason: '没有第二次 /presence/get');
    sub.close();
  });
}
