import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:fluxdo/services/network/flux_request_spec.dart';
import 'package:fluxdo/services/network/interceptors/error_interceptor.dart';
import 'package:fluxdo/services/network/quiet_request.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 「安静」的只读请求：走真实的拦截器链（恢复、人工验证都在），断言它们不插手：
// 429（带 Retry-After）和 503 只发出 1 个请求；带取消令牌、不记资料页浏览；不传时行为不变。

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);

  final ResponseBody Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  Completer<void>? hold;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    if (hold != null) {
      await Future.any([hold!.future, if (cancelFuture != null) cancelFuture]);
      if (cancelFuture != null) {
        throw DioException.requestCancelled(requestOptions: options, reason: 'cancelled');
      }
    }
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, {int status = 200, Map<String, List<String>> headers = const {}}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
      ...headers,
    });

DiscourseService _service(_Adapter adapter) {
  final service = DiscourseService();
  final originalAdapter = service.dio.httpClientAdapter;
  final originalInterceptors = service.dio.interceptors.toList();
  service.dio.httpClientAdapter = adapter;
  // 只去掉要弹界面提示的那个；恢复、人工验证等其余拦截器都保留
  service.dio.interceptors.removeWhere((item) => item is ErrorInterceptor);
  service.cookieSync.setCsrfToken('quiet-test-token');
  addTearDown(() {
    service.dio.httpClientAdapter = originalAdapter;
    service.dio.interceptors
      ..clear()
      ..addAll(originalInterceptors);
    service.cookieSync.clearCsrfToken();
  });
  return service;
}

const _topic = {
  'id': 1,
  'title': 'T',
  'slug': 't',
  'posts_count': 1,
  'post_stream': {'posts': <Object>[], 'stream': <int>[]},
  'category_id': 1,
  'details': <String, dynamic>{},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('取消令牌：触发后底层请求立即断开，抛取消异常', () async {
    final adapter = _Adapter((o) => _json(_topic))..hold = Completer<void>();
    final service = _service(adapter);
    final token = CancelToken();
    final future = service.getTopicDetail(1, quiet: QuietRequest(cancelToken: token));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(adapter.requests.length, 1);
    token.cancel('stop');
    await expectLater(
      future.timeout(const Duration(seconds: 3)),
      throwsA(isA<DioException>().having((e) => CancelToken.isCancel(e), 'cancel', isTrue)),
    );
    // 网络层会把它和自己的令牌合并，所以看触发状态而不是同一个对象
    expect(adapter.requests.single.cancelToken!.isCancelled, isTrue);
  });

  test('其余几个方法也都带安静标记，并且点取消能立刻断开', () async {
    final names = ['actions', 'notifications', 'badge', 'posts', 'summary'];
    Future<Object?> call(DiscourseService service, String name, QuietRequest q) => switch (name) {
      'actions' => service.getUserActions('a', filter: '5', quiet: q),
      'notifications' => service.getNotifications(quiet: q),
      'badge' => service.getBadgeUsers(badgeId: 20, quiet: q),
      'posts' => service.getPosts(1, [1, 2], quiet: q),
      _ => service.getUserSummary('a', quiet: q),
    };
    for (final name in names) {
      final adapter = _Adapter((o) => _json({}))..hold = Completer<void>();
      final service = _service(adapter);
      final token = CancelToken();
      final future = call(service, name, QuietRequest(cancelToken: token));
      for (var i = 0; i < 100 && adapter.requests.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(adapter.requests.length, 1, reason: name);
      final extra = adapter.requests.single.extra;
      expect(extra[FluxRequestKeys.noRecovery], isTrue, reason: name);
      expect(extra[FluxRequestKeys.skipCfChallenge], isTrue, reason: name);
      expect(extra[FluxRequestKeys.isSilent], isTrue, reason: name);
      token.cancel('stop');
      await expectLater(
        future.timeout(const Duration(seconds: 3)),
        throwsA(isA<DioException>().having((e) => CancelToken.isCancel(e), 'cancel', isTrue)),
        reason: name,
      );
    }
  });
}
