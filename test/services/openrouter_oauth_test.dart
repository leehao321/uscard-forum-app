import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/openrouter_oauth.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.body, {this.status = 200});

  final String body;
  final int status;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(_Adapter adapter) => Dio()..httpClientAdapter = adapter;

void main() {
  group('PKCE', () {
    test('S256：RFC 7636 附录 B 的官方向量', () {
      expect(
        OpenRouterOAuth.challengeFor('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });

    test('verifier 长度合规（43~128），只有 URL 安全字符，每次不同', () {
      final a = OpenRouterOAuth.createVerifier();
      final b = OpenRouterOAuth.createVerifier();
      expect(a.length, inInclusiveRange(43, 128));
      expect(RegExp(r'^[A-Za-z0-9\-_]+$').hasMatch(a), isTrue);
      expect(a, isNot(b));
    });

    test('授权地址带回调和 challenge，不带 verifier', () {
      final uri = OpenRouterOAuth.authorizeUrl('my-verifier');
      expect(uri.host, 'openrouter.ai');
      expect(uri.path, '/auth');
      expect(uri.queryParameters['callback_url'], 'pulseflow://openrouter-auth');
      expect(uri.queryParameters['code_challenge_method'], 'S256');
      expect(
        uri.queryParameters['code_challenge'],
        OpenRouterOAuth.challengeFor('my-verifier'),
      );
      expect(uri.toString(), isNot(contains('my-verifier')));
    });
  });

  group('登录', () {
    test('完整流程：打开授权页，用 code 和 verifier 换 Key', () async {
      final adapter = _Adapter('{"key":"sk-or-test"}');
      String? openedUrl;
      String? openedScheme;
      final oauth = OpenRouterOAuth(
        dio: _dio(adapter),
        newVerifier: () => 'my-verifier',
        authenticate: (url, scheme) async {
          openedUrl = url;
          openedScheme = scheme;
          return 'pulseflow://openrouter-auth?code=abc123';
        },
      );

      expect(await oauth.login(), 'sk-or-test');
      expect(openedScheme, 'pulseflow');
      expect(Uri.parse(openedUrl!).queryParameters['code_challenge'], isNotEmpty);

      final request = adapter.requests.single;
      expect(request.uri.toString(), 'https://openrouter.ai/api/v1/auth/keys');
      expect(request.method, 'POST');
      final data = request.data is String
          ? jsonDecode(request.data as String)
          : request.data as Map;
      expect(data['code'], 'abc123');
      expect(data['code_verifier'], 'my-verifier');
      expect(data['code_challenge_method'], 'S256');
      expect(request.headers['cookie'], isNull);
    });

    test('用户关掉授权页：返回 null，不算失败，不发请求', () async {
      final adapter = _Adapter('{}');
      final oauth = OpenRouterOAuth(
        dio: _dio(adapter),
        authenticate: (_, _) async => throw PlatformException(code: 'CANCELED'),
      );
      expect(await oauth.login(), isNull);
      expect(adapter.requests, isEmpty);
    });

    test('其他授权错误抛出去', () async {
      final oauth = OpenRouterOAuth(
        dio: _dio(_Adapter('{}')),
        authenticate: (_, _) async => throw PlatformException(code: 'EUNKNOWN'),
      );
      await expectLater(oauth.login(), throwsA(isA<PlatformException>()));
    });

    test('回调里没有 code：失败，不发请求', () async {
      final adapter = _Adapter('{}');
      final oauth = OpenRouterOAuth(
        dio: _dio(adapter),
        authenticate: (_, _) async => 'pulseflow://openrouter-auth?error=denied',
      );
      await expectLater(oauth.login(), throwsFormatException);
      expect(adapter.requests, isEmpty);
    });

    test('响应里没有 key：失败', () async {
      final oauth = OpenRouterOAuth(
        dio: _dio(_Adapter('{"data":1}')),
        authenticate: (_, _) async => 'pulseflow://openrouter-auth?code=x',
      );
      await expectLater(oauth.login(), throwsFormatException);
    });

    test('code 过期（403）：失败', () async {
      final oauth = OpenRouterOAuth(
        dio: _dio(_Adapter('{"error":"expired"}', status: 403)),
        authenticate: (_, _) async => 'pulseflow://openrouter-auth?code=x',
      );
      await expectLater(oauth.login(), throwsA(isA<DioException>()));
    });
  });
}
