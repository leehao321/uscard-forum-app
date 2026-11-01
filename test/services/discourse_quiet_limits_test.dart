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
      await Future.any([hold!.future, ?cancelFuture]);
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

  // 放在最后：429 / 5xx 之后网络层的全局调度状态会影响后面的请求
  for (final (status, headers) in [
    (429, {'retry-after': ['1']}),
    (503, <String, List<String>>{}),
    (502, <String, List<String>>{}),
  ]) {
    test('安静请求遇到 $status：只发 1 个请求，原样抛回 DioException，不等待不重放', () async {
      final adapter = _Adapter((o) => _json({'error': 'x'}, status: status, headers: headers));
      final service = _service(adapter);
      final sw = Stopwatch()..start();
      await expectLater(
        service.getTopicDetail(1, quiet: const QuietRequest()).timeout(const Duration(seconds: 5)),
        throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'status', status)),
      );
      expect(adapter.requests.length, 1, reason: '网络层不能替它重放');
      expect(sw.elapsed, lessThan(const Duration(milliseconds: 900)), reason: '不能等 Retry-After');
    });
  }
}
