import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' hide Cookie;
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as iaw show Cookie;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/cookie/app_cookie_manager.dart';
import 'package:fluxdo/services/network/cookie/cookie_jar_service.dart';
import 'package:fluxdo/services/network/cookie/session_cookie_sentinel.dart';

import '../../../support/cf_test_platform.dart';

/// 记下所有写进 WebView 的 Cookie（Windows、Linux 走 setCookie，其他平台走原生通道）
class _SpyCookieManager extends CfTestCookieManager {
  final writes = <(String url, String name, String value)>[];

  @override
  Future<bool> setCookie({
    required WebUri url,
    required String name,
    required String value,
    String path = '/',
    String? domain,
    int? expiresDate,
    int? maxAge,
    bool? isSecure,
    bool? isHttpOnly,
    HTTPCookieSameSitePolicy? sameSite,
    PlatformInAppWebViewController? iosBelow11WebViewController,
    PlatformInAppWebViewController? webViewController,
  }) async {
    writes.add((url.toString(), name, value));
    values = [
      ...values.where((c) => c.name != name),
      iaw.Cookie(name: name, value: value, domain: domain, path: path),
    ];
    return true;
  }
}

class _SpyPlatform extends CfTestPlatform {
  final spy = _SpyCookieManager();

  @override
  PlatformCookieManager createPlatformCookieManager(
    PlatformCookieManagerCreationParams params,
  ) => spy;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = _SpyPlatform();
  final jar = CookieJarService();
  late io.Directory cookieDirectory;
  final channelWrites = <(String url, String name)>[];

  setUpAll(() async {
    cookieDirectory = await io.Directory.systemTemp.createTemp('third-party-');
    await platform.initialize(cookieDirectory: cookieDirectory.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.fluxdo/raw_cookie'), (
          call,
        ) async {
          if (call.method == 'setRawCookie') {
            final args = call.arguments as Map<Object?, Object?>;
            final raw = args['rawSetCookie']! as String;
            channelWrites.add((args['url']! as String, raw.split('=').first));
          }
          return true;
        });
  });

  setUp(() async {
    await platform.reset();
    platform.spy.writes.clear();
    platform.spy.values = [];
    channelWrites.clear();
    SessionCookieSentinel.instance.resetForTest();
    await jar.cookieJar.saveFromResponse(Uri.parse('https://linux.do/'), [
      io.Cookie('_t', 'REAL')..path = '/',
    ]);
  });

  tearDownAll(() => cookieDirectory.delete(recursive: true));

  Future<void> respond(String url, List<String> setCookies) {
    final options = RequestOptions(path: url);
    return AppCookieManager(jar.cookieJar).saveCookies(
      Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        headers: Headers.fromMap({'set-cookie': setCookies}),
      ),
    );
  }

  Iterable<(String, String)> webViewWrites(String name) => [
    for (final w in platform.spy.writes)
      if (w.$2 == name) (w.$1, w.$3),
    for (final w in channelWrites)
      if (w.$2 == name) (w.$1, '?'),
  ];

  group('第三方响应不能动主站的会话 Cookie', () {
    test('A-01：Set-Cookie: _t=del 不删主站 _t', () async {
      await respond('https://evil.test/x.bin', ['_t=del; Path=/']);
      expect(await jar.getTToken(), 'REAL');
    });

    test('A-01：过期的 _t 也不删', () async {
      await respond('https://evil.test/x.bin', [
        '_t=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT',
      ]);
      expect(await jar.getTToken(), 'REAL');
    });

    test('A-02：主站令牌不会被写进第三方 host 的 WebView', () async {
      await respond('https://evil.test/x.bin', ['_t=x; Path=/']);
      expect(
        webViewWrites('_t').where((w) => w.$1.contains('evil.test')),
        isEmpty,
        reason: '写给 evil.test 的 _t 会在 App 内打开该站时发出去',
      );
      expect(await jar.getTToken(), 'REAL');
    });

    test('A-02：_forum_session 同样不处理', () async {
      await respond('https://other-forum.test/x', [
        '_forum_session=abc; Path=/',
      ]);
      expect(
        webViewWrites('_forum_session').where((w) => w.$1.contains('other-forum')),
        isEmpty,
      );
    });

    test('A-02：对第三方 URL 的同步不写主站令牌', () async {
      await SessionCookieSentinel.instance.sweep(
        'https://evil.test/',
        '_t',
        force: true,
      );
      expect(
        webViewWrites('_t').where((w) => w.$1.contains('evil.test')),
        isEmpty,
      );
    });

    test('A-03：Domain 写成主站也不能覆盖 _t', () async {
      await respond('https://evil.test/x.bin', [
        '_t=ATTACKER; Domain=linux.do; Path=/',
      ]);
      expect(await jar.getTToken(), 'REAL');
    });

    test('A-03：Domain=do 这种公共后缀不入库', () async {
      await respond('https://evil.do/x', ['track=1; Domain=do; Path=/']);
      final cookies = await jar.cookieJar.loadForRequest(
        Uri.parse('https://linux.do/'),
      );
      expect(cookies.map((c) => c.name), isNot(contains('track')));
    });

    test('第三方自己的普通 Cookie 不受影响', () async {
      await respond('https://evil.test/x', ['foo=bar; Path=/']);
      final cookies = await jar.cookieJar.loadForRequest(
        Uri.parse('https://evil.test/'),
      );
      expect(cookies.map((c) => c.name), contains('foo'));
    });
  });

  group('主站自己的响应照常生效', () {
    test('更新 _t', () async {
      await respond('https://linux.do/session', ['_t=NEW; Path=/']);
      expect(await jar.getTToken(), 'NEW');
    });

    test('删除 _t', () async {
      await respond('https://linux.do/session', ['_t=del; Path=/']);
      expect(await jar.getTToken(), isNull);
    });

    test('Domain 写成主站的上级或自身仍然可以', () async {
      await respond('https://linux.do/session', [
        '_t=NEW; Domain=linux.do; Path=/',
      ]);
      expect(await jar.getTToken(), 'NEW');
    });
  });

  group('isAppOriginHost', () {
    test('只认主站和 www 别名', () {
      expect(CookieJarService.isAppOriginHost('linux.do'), isTrue);
      expect(CookieJarService.isAppOriginHost('LINUX.DO'), isTrue);
      expect(CookieJarService.isAppOriginHost('www.linux.do'), isTrue);
      expect(CookieJarService.isAppOriginHost('connect.linux.do'), isFalse);
      expect(CookieJarService.isAppOriginHost('evil.test'), isFalse);
      expect(CookieJarService.isAppOriginHost('notlinux.do'), isFalse);
      expect(CookieJarService.isAppOriginHost(''), isFalse);
    });
  });
}
