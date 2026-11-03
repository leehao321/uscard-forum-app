import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/auth_session.dart';
import 'package:fluxdo/services/network/interceptors/request_scheduler_interceptor.dart';
import 'package:fluxdo/services/network/interceptors/session_guard_interceptor.dart';
import 'package:fluxdo/services/network/request_scheduler_config.dart';

/// 回复前一直等，直到请求被取消或 [release] 完成。
class _HoldingAdapter implements HttpClientAdapter {
  final release = Completer<void>();
  final seen = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options);
    await Future.any([release.future, if (cancelFuture != null) cancelFuture]);
    return ResponseBody.fromString('{}', 200);
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(HttpClientAdapter adapter, String host) =>
    Dio(BaseOptions(baseUrl: 'https://$host'))
      ..httpClientAdapter = adapter
      ..interceptors.addAll([
        SessionGuardInterceptor(),
        RequestSchedulerInterceptor(),
      ]);

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('会话推进时的调度槽位', () {
    test('在途请求没带令牌：推进后槽位释放，后面的请求不会永远排队', () async {
      final adapter = _HoldingAdapter();
      final dio = _dio(adapter, 'slots-a.test');
      final inFlight = [
        for (var i = 0; i < RequestSchedulerConfig.maxConcurrent; i++)
          dio.get<dynamic>('/a').then<Object?>((r) => r, onError: (Object e) => e),
      ];
      await _settle();
      expect(adapter.seen, hasLength(RequestSchedulerConfig.maxConcurrent));

      AuthSession().advance();
      final results = await Future.wait(inFlight);
      for (final r in results) {
        expect(r, isA<DioException>());
        expect((r! as DioException).type, DioExceptionType.cancel);
        expect(
          (r as DioException).requestOptions.path,
          '/a',
          reason: '取消错误要带这个请求自己的 options，调度器才能释放槽位',
        );
      }

      final next = _HoldingAdapter()..release.complete();
      dio.httpClientAdapter = next;
      final response = await dio
          .get<dynamic>('/after')
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => fail('推进后新请求一直在排队：调度槽位泄漏'),
          );
      expect(response.statusCode, 200);
    });

    test('在途请求带调用方令牌：推进后同样释放', () async {
      final adapter = _HoldingAdapter();
      final dio = _dio(adapter, 'slots-b.test');
      final inFlight = [
        for (var i = 0; i < RequestSchedulerConfig.maxConcurrent; i++)
          dio
              .get<dynamic>('/a', cancelToken: CancelToken())
              .then<Object?>((r) => r, onError: (Object e) => e),
      ];
      await _settle();

      AuthSession().advance();
      await Future.wait(inFlight);

      dio.httpClientAdapter = _HoldingAdapter()..release.complete();
      final response = await dio
          .get<dynamic>('/after')
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => fail('推进后新请求一直在排队：调度槽位泄漏'),
          );
      expect(response.statusCode, 200);
    });

    test('排队中的请求也被取消，不占槽位', () async {
      final adapter = _HoldingAdapter();
      final dio = _dio(adapter, 'slots-c.test');
      final all = [
        for (var i = 0; i < RequestSchedulerConfig.maxConcurrent + 2; i++)
          dio.get<dynamic>('/a').then<Object?>((r) => r, onError: (Object e) => e),
      ];
      await _settle();
      expect(adapter.seen, hasLength(RequestSchedulerConfig.maxConcurrent));

      AuthSession().advance();
      final results = await Future.wait(all);
      expect(results.whereType<DioException>(), hasLength(all.length));

      dio.httpClientAdapter = _HoldingAdapter()..release.complete();
      final response = await dio
          .get<dynamic>('/after')
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => fail('推进后新请求一直在排队：调度槽位泄漏'),
          );
      expect(response.statusCode, 200);
    });
  });

  group('取消令牌', () {
    test('每个请求一个令牌，长寿命对象不会留住响应', () async {
      final adapter = _HoldingAdapter()..release.complete();
      final dio = _dio(adapter, 'token-a.test');
      await dio.get<dynamic>('/a');
      await dio.get<dynamic>('/b');
      final tokens = adapter.seen.map((o) => o.cancelToken).toList();
      expect(tokens[0], isNotNull);
      expect(identical(tokens[0], tokens[1]), isFalse, reason: '共用令牌会把每个响应都留到下次推进');
      expect(identical(tokens[0]!.requestOptions, adapter.seen[0]), isTrue);
    });

    test('调用方取消只影响自己的请求，会话令牌不受牵连', () async {
      final adapter = _HoldingAdapter();
      final dio = _dio(adapter, 'token-b.test');
      final caller = CancelToken();
      final own = dio
          .get<dynamic>('/a', cancelToken: caller)
          .then<Object?>((r) => r, onError: (Object e) => e);
      final other = dio
          .get<dynamic>('/b')
          .then<Object?>((r) => r, onError: (Object e) => e);
      await _settle();

      caller.cancel('user');
      final ownResult = await own;
      expect(ownResult, isA<DioException>());
      expect((ownResult! as DioException).type, DioExceptionType.cancel);

      adapter.release.complete();
      expect(await other, isA<Response<dynamic>>());
    });

    test('调用方令牌已取消：请求不发出', () async {
      final adapter = _HoldingAdapter()..release.complete();
      final dio = _dio(adapter, 'token-c.test');
      final caller = CancelToken()..cancel('already');
      await expectLater(
        dio.get<dynamic>('/a', cancelToken: caller),
        throwsA(
          isA<DioException>().having((e) => e.type, 'type', DioExceptionType.cancel),
        ),
      );
      expect(adapter.seen, isEmpty);
    });

    test('推进之前结束的请求不受影响', () async {
      final adapter = _HoldingAdapter()..release.complete();
      final dio = _dio(adapter, 'token-d.test');
      final response = await dio.get<dynamic>('/a');
      expect(response.statusCode, 200);
      AuthSession().advance();
      expect(await dio.get<dynamic>('/b'), isA<Response<dynamic>>());
    });
  });

  test('退出登录在清 Cookie 前后都推进会话代（防幽灵登录）', () {
    final src = File('lib/services/discourse/_auth.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final logout = src.substring(src.indexOf('Future<void> logout({'));
    final clear = logout.indexOf('await _cookieJar.clearAll();');
    expect(clear, greaterThan(0));
    final before = logout.substring(0, clear);
    final after = logout.substring(clear);
    expect('AuthSession().advance();'.allMatches(before).length, 2,
        reason: '开头一次，清 Cookie 前一次');
    final broadcast = after.indexOf('_authStateController.add(null);');
    expect(after.indexOf('AuthSession().advance();'), inInclusiveRange(0, broadcast),
        reason: '清完 Cookie 后、广播前要再推进一次');
  });

  test('推进后才回来的响应按过期丢弃', () async {
    final adapter = _HoldingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://stale.test'))
      ..httpClientAdapter = adapter
      ..interceptors.add(SessionGuardInterceptor());
    final pending = dio
        .get<dynamic>('/a')
        .then<Object?>((r) => r, onError: (Object e) => e);
    await _settle();
    AuthSession().advance();
    adapter.release.complete();
    final result = await pending;
    expect(result, isA<DioException>());
    expect((result! as DioException).type, DioExceptionType.cancel);
  });
}
