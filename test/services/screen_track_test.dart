import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:fluxdo/services/screen_track.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 0.4.0 M9.7 / P-6：退出帖子时，在途请求后面刚入队的最后一批阅读时间不能丢。
// 服务全是假的，不请求论坛。

class _Request {
  _Request(this.topicId, this.timings);

  final int topicId;
  final Map<int, int> timings;
  final Completer<int?> done = Completer<int?>();
}

class _Service extends Fake implements DiscourseService {
  final List<_Request> requests = [];

  @override
  bool get isAuthenticated => true;

  @override
  Future<int?> topicsTimings({
    required int topicId,
    required int topicTime,
    required Map<int, int> timings,
    Map<String, dynamic>? logContext,
  }) {
    final r = _Request(topicId, Map<int, int>.from(timings));
    requests.add(r);
    return r.done.future;
  }
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 40));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('stop() 时上一个请求还在途：第二批在第一批完成后自动发出并触发回调', () async {
    final service = _Service();
    final sent = <int>[];
    final track = ScreenTrack(
      service,
      onTimingsSent: (topicId, postNumbers, highestSeen) => sent.add(topicId),
    );

    // 话题 1 读了一会儿，切到话题 2 时 flush：请求 A 发出并停在途
    track.start(1);
    track.setOnscreen({1});
    await _settle();
    track.start(2);
    expect(service.requests.map((r) => r.topicId), [1]);

    // 在话题 2 里又读了一会儿，退出：请求 A 还没回来，这一批只能入队
    track.setOnscreen({5});
    await _settle();
    track.stop();
    expect(service.requests.length, 1, reason: '在途期间不并发发第二个');

    // A 回来后，队列里的话题 2 自动接着发
    service.requests[0].done.complete(200);
    await _settle();
    expect(service.requests.map((r) => r.topicId), [1, 2]);
    expect(service.requests[1].timings.keys, contains(5));

    service.requests[1].done.complete(200);
    await _settle();
    expect(sent, [1, 2], reason: '两批都要触发 onTimingsSent，首页未读点才消得掉');
  });

  test('abandon()：不发请求，在途请求完成也不触发回调，队列清空', () async {
    final service = _Service();
    final sent = <int>[];
    final track = ScreenTrack(
      service,
      onTimingsSent: (topicId, postNumbers, highestSeen) => sent.add(topicId),
    );

    track.start(1);
    track.setOnscreen({1});
    await _settle();
    track.abandon();
    await _settle();
    expect(service.requests, isEmpty);

    // 在途 + abandon
    track.start(1);
    track.setOnscreen({1});
    await _settle();
    track.start(2);
    expect(service.requests.length, 1);
    track.setOnscreen({5});
    await _settle();
    track.abandon();
    service.requests[0].done.complete(200);
    await _settle();
    expect(service.requests.length, 1, reason: 'abandon 后不再发队列');
    expect(sent, isEmpty, reason: 'abandon 抑制在途请求的回调');
  });
}
