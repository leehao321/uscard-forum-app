import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/site_probe_service.dart';

class _Reply {
  final int status;
  final String body;
  final Map<String, List<String>> headers;
  final Uri? redirectTo;
  final DioExceptionType? error;

  const _Reply(
    this.status,
    this.body, {
    this.headers = const {},
    this.redirectTo,
    this.error,
  });
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.replies);

  final Map<String, _Reply> replies;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final reply =
        replies[options.uri.toString()] ?? const _Reply(404, 'not found');
    if (reply.error != null) {
      throw DioException(requestOptions: options, type: reply.error!);
    }
    final body = ResponseBody.fromString(
      reply.body,
      reply.status,
      headers: reply.headers,
    );
    if (reply.redirectTo != null) {
      body.redirects = [RedirectRecord(302, 'GET', reply.redirectTo!)];
    }
    return body;
  }

  @override
  void close({bool force = false}) {}
}

const _base = 'https://forum.example.com';

final _siteJson = jsonEncode({
  'categories': [],
  'default_archetype': 'regular',
  'post_action_types': [],
});

final _basicInfo = jsonEncode({
  'title': 'Basic Title',
  'description': 'Basic description',
  'logo_url': '/uploads/logo.png',
  'apple_touch_icon_url': '//cdn.example.com/icon.png',
  'login_required': false,
});

final _about = jsonEncode({
  'about': {
    'title': 'About Title',
    'description': 'About description',
    'version': '3.5.0',
  },
});

void main() {
  (SiteProbeService, _FakeAdapter) serviceWith(Map<String, _Reply> replies) {
    final adapter = _FakeAdapter(replies);
    final dio = Dio(
      BaseOptions(
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    )..httpClientAdapter = adapter;
    return (SiteProbeService(dio: dio), adapter);
  }

  test('标准站：优先用 about.json 的信息，资源地址转绝对', () async {
    final (service, _) = serviceWith({
      '$_base/site.json': _Reply(200, _siteJson),
      '$_base/site/basic-info.json': _Reply(200, _basicInfo),
      '$_base/about.json': _Reply(200, _about),
    });

    final result = await service.probe(_base) as SiteProbeSuccess;

    expect(result.baseUrl, _base);
    expect(result.title, 'About Title');
    expect(result.description, 'About description');
    expect(result.version, '3.5.0');
    expect(result.logoUrl, '$_base/uploads/logo.png');
    expect(result.faviconUrl, 'https://cdn.example.com/icon.png');
    expect(result.loginRequired, isFalse);
    expect(result.toProfile().baseUrl, _base);
  });

  test('about.json 和 basic-info 都失败时，标题回落到 host', () async {
    final (service, _) = serviceWith({'$_base/site.json': _Reply(200, _siteJson)});
    final result = await service.probe(_base) as SiteProbeSuccess;
    expect(result.title, 'forum.example.com');
  });

  test('子路径站点', () async {
    const base = '$_base/forum';
    final (service, _) = serviceWith({
      '$base/site.json': _Reply(200, _siteJson),
      '$base/about.json': _Reply(200, _about),
    });
    final result = await service.probe(base) as SiteProbeSuccess;
    expect(result.baseUrl, base);
  });

  test('需要登录的站：site.json 被拒，靠 basic-info 确认，不再请求 about', () async {
    final (service, adapter) = serviceWith({
      '$_base/site.json': const _Reply(403, '{"error_type":"not_logged_in"}'),
      '$_base/site/basic-info.json': _Reply(
        200,
        jsonEncode({'title': 'Private', 'login_required': true}),
      ),
    });

    final result = await service.probe(_base) as SiteProbeSuccess;

    expect(result.title, 'Private');
    expect(result.loginRequired, isTrue);
    expect(adapter.requests.map((r) => r.uri.path), isNot(contains('/about.json')));
  });

  test('重定向到另一个 https 地址时，用真实地址', () async {
    const real = 'https://www.example.com';
    final (service, _) = serviceWith({
      '$_base/site.json': _Reply(
        200,
        _siteJson,
        redirectTo: Uri.parse('$real/site.json'),
      ),
      '$real/about.json': _Reply(200, _about),
    });
    final result = await service.probe(_base) as SiteProbeSuccess;
    expect(result.baseUrl, real);
  });

  test('重定向到 http 时不接受', () async {
    final (service, _) = serviceWith({
      '$_base/site.json': _Reply(
        200,
        _siteJson,
        redirectTo: Uri.parse('http://www.example.com/site.json'),
      ),
    });
    final result = await service.probe(_base) as SiteProbeFailure;
    expect(result.reason, SiteProbeFailureReason.notDiscourse);
  });

  group('失败分支', () {
    Future<SiteProbeFailureReason> reasonFor(Map<String, _Reply> replies) async {
      final (service, _) = serviceWith(replies);
      return (await service.probe(_base) as SiteProbeFailure).reason;
    }

    test('普通网页不是 Discourse', () async {
      expect(
        await reasonFor({
          '$_base/site.json': const _Reply(200, '<html>hello</html>'),
          '$_base/site/basic-info.json': const _Reply(200, '<html>hello</html>'),
        }),
        SiteProbeFailureReason.notDiscourse,
      );
    });

    test('404 不是 Discourse', () async {
      expect(await reasonFor({}), SiteProbeFailureReason.notDiscourse);
    });

    test('字段不对的 JSON 不是 Discourse', () async {
      expect(
        await reasonFor({
          '$_base/site.json': const _Reply(200, '{"categories":"x"}'),
          '$_base/site/basic-info.json': const _Reply(200, '{"title":"x"}'),
        }),
        SiteProbeFailureReason.notDiscourse,
      );
    });

    test('cf-mitigated 头判定为 Cloudflare 验证', () async {
      expect(
        await reasonFor({
          '$_base/site.json': const _Reply(
            403,
            'blocked',
            headers: {
              'cf-mitigated': ['challenge'],
            },
          ),
        }),
        SiteProbeFailureReason.cloudflareChallenge,
      );
    });

    test('Cloudflare 的验证页正文也能识别', () async {
      expect(
        await reasonFor({
          '$_base/site.json': const _Reply(
            503,
            '<title>Just a moment...</title>',
            headers: {
              'server': ['cloudflare'],
            },
          ),
        }),
        SiteProbeFailureReason.cloudflareChallenge,
      );
    });

    test('普通 403 不算 Cloudflare 验证', () async {
      expect(
        await reasonFor({
          '$_base/site.json': const _Reply(
            403,
            'forbidden',
            headers: {
              'server': ['cloudflare'],
            },
          ),
        }),
        SiteProbeFailureReason.notDiscourse,
      );
    });

    test('站点 5xx 算连不上', () async {
      expect(
        await reasonFor({'$_base/site.json': const _Reply(502, 'bad gateway')}),
        SiteProbeFailureReason.unreachable,
      );
    });

    test('连接错误算连不上', () async {
      expect(
        await reasonFor({
          '$_base/site.json': const _Reply(
            0,
            '',
            error: DioExceptionType.connectionError,
          ),
        }),
        SiteProbeFailureReason.unreachable,
      );
    });

    test('证书错误单独提示', () async {
      expect(
        await reasonFor({
          '$_base/site.json': const _Reply(
            0,
            '',
            error: DioExceptionType.badCertificate,
          ),
        }),
        SiteProbeFailureReason.badCertificate,
      );
    });
  });

  test('默认 Dio 发出的请求不带 cookie 或 API Key，且跟随重定向', () async {
    final adapter = _FakeAdapter({
      '$_base/site.json': _Reply(200, _siteJson),
      '$_base/site/basic-info.json': _Reply(200, _basicInfo),
      '$_base/about.json': _Reply(200, _about),
    });
    final dio = SiteProbeService.createDio()..httpClientAdapter = adapter;

    expect(await SiteProbeService(dio: dio).probe(_base), isA<SiteProbeSuccess>());

    expect(adapter.requests, hasLength(3));
    for (final request in adapter.requests) {
      final headers = request.headers.keys.map((k) => k.toLowerCase());
      expect(headers, isNot(contains('cookie')));
      expect(headers, isNot(contains('user-api-key')));
      expect(headers, isNot(contains('user-api-client-id')));
      expect(request.followRedirects, isTrue);
    }
  });
}
