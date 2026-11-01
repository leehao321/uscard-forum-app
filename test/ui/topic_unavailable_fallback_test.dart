import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/topic_detail_page/topic_unavailable_fallback.dart';
import 'package:fluxdo/services/network/exceptions/api_exception.dart';
import 'package:fluxdo/widgets/common/error_view.dart';

import 'support/ui_harness.dart';

// 话题打不开时的替代内容扩展点：只在 404 / 410 / 429 / 403 的最终结果里触发。

DioException _http(int code) => DioException(
  requestOptions: RequestOptions(path: '/t/1.json'),
  response: Response(
    requestOptions: RequestOptions(path: '/t/1.json'),
    statusCode: code,
  ),
  type: DioExceptionType.badResponse,
);

void main() {
  setUpAll(loadUiFonts);
  tearDown(() => TopicUnavailableFallback.builder = null);

  group('topicUnavailableStatusOf', () {
    test('404 / 410 / 429 / 403 的响应原样返回状态码', () {
      for (final code in [404, 410, 429, 403]) {
        expect(topicUnavailableStatusOf(_http(code)), code, reason: '$code');
      }
    });

    test('限流异常（直接的或包在 DioException 里的）算 429', () {
      expect(topicUnavailableStatusOf(RateLimitException(0)), 429);
      expect(
        topicUnavailableStatusOf(
          DioException(
            requestOptions: RequestOptions(path: '/'),
            error: RateLimitException(0),
          ),
        ),
        429,
      );
    });

    test('Cloudflare 验证不算（含包在 403 响应里的）', () {
      expect(topicUnavailableStatusOf(CfChallengeException()), isNull);
      expect(
        topicUnavailableStatusOf(
          DioException(
            requestOptions: RequestOptions(path: '/'),
            response: Response(
              requestOptions: RequestOptions(path: '/'),
              statusCode: 403,
            ),
            error: CfChallengeException(),
          ),
        ),
        isNull,
      );
    });

    test('5xx、网络错误、超时、其它状态码都不算', () {
      for (final code in [500, 502, 503, 401, 400]) {
        expect(topicUnavailableStatusOf(_http(code)), isNull, reason: '$code');
      }
      expect(topicUnavailableStatusOf(ServerException(503)), isNull);
      expect(
        topicUnavailableStatusOf(
          DioException(
            requestOptions: RequestOptions(path: '/'),
            type: DioExceptionType.connectionTimeout,
          ),
        ),
        isNull,
      );
      expect(topicUnavailableStatusOf(Exception('boom')), isNull);
    });
  });

  group('TopicLoadErrorContent', () {
    Widget page(Object error) => Scaffold(
      body: TopicLoadErrorContent(topicId: 321, error: error, onRetry: () {}),
    );

    testUi('没有注册替代内容：显示原来的错误页', (tester) async {
      await pumpUi(tester, page(_http(404)));
      expect(find.byType(SliverErrorView), findsOneWidget);
    });

    testUi('404：把话题 id、状态码和原错误页交给替代内容', (tester) async {
      TopicUnavailableInfo? got;
      TopicUnavailableFallback.builder = (context, info) {
        got = info;
        return const Center(child: Text('替代内容'));
      };
      await pumpUi(tester, page(_http(404)));
      expect(find.text('替代内容'), findsOneWidget);
      expect(find.byType(SliverErrorView), findsNothing);
      expect(got!.topicId, 321);
      expect(got!.statusCode, 404);
      expect(got!.errorView, isA<CustomScrollView>());
    });

    testUi('410 / 429 / 403 同样触发', (tester) async {
      final seen = <int>[];
      TopicUnavailableFallback.builder = (context, info) {
        seen.add(info.statusCode);
        return const SizedBox();
      };
      for (final code in [410, 429, 403]) {
        await pumpUi(tester, page(_http(code)));
      }
      expect(seen, [410, 429, 403]);
    });

    testUi('Cloudflare 验证、5xx、网络错误不触发，仍是原错误页', (tester) async {
      var called = 0;
      TopicUnavailableFallback.builder = (context, info) {
        called++;
        return const SizedBox();
      };
      for (final error in <Object>[
        CfChallengeException(),
        _http(500),
        DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.connectionError,
        ),
      ]) {
        await pumpUi(tester, page(error));
        expect(find.byType(SliverErrorView), findsOneWidget);
      }
      expect(called, 0);
    });

    testUi('替代内容拿不到数据时可以继续显示原错误页', (tester) async {
      TopicUnavailableFallback.builder = (context, info) => info.errorView;
      await pumpUi(tester, page(_http(404)));
      expect(find.byType(SliverErrorView), findsOneWidget);
    });
  });
}
