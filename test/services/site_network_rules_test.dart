import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/config/sites/current.dart';
import 'package:fluxdo/config/sites/linuxdo.dart';
import 'package:fluxdo/constants.dart';
import 'package:fluxdo/models/site_profile.dart';
import 'package:fluxdo/services/network/cookie/cookie_jar_service.dart';
import 'package:fluxdo/services/network/cookie/csrf_token_service.dart';
import 'package:fluxdo/services/network/interceptors/request_header_interceptor.dart';
import 'package:fluxdo/services/network/doh/ech_dns_policy.dart';
import 'package:fluxdo/services/preloaded_data_service.dart';
import 'package:fluxdo/services/site_context.dart';
import 'package:fluxdo/services/user_api_key_service.dart';
import 'package:fluxdo/utils/link_launcher.dart';

class _RecordingAdapter implements HttpClientAdapter {
  Uri? lastUri;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastUri = options.uri;
    return ResponseBody.fromString('{}', 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final custom = SiteProfile(baseUrl: 'https://example.com/forum', title: 'E');

  tearDown(SiteContext.debugReset);

  group('ECH 内置域名', () {
    test('linux.do 与 Rust 内置规则一致，不额外下发', () {
      SiteContext.activate(SitePresets.linuxdo);
      expect(EchDnsPolicy.builtinDomains, ['linux.do', 'ldstatic.com']);
      expect(
        const EchDnsPolicy(customDomains: ['a.example']).toJson()['custom_domains'],
        ['a.example'],
      );
      expect(
        const EchDnsPolicy().queryName('linux.do'),
        EchDnsPolicy.cloudflareQueryName,
      );
    });

    test('USCard用根域，并下发给 Rust，读回来不混进自定义域名', () {
      SiteContext.activate(SitePresets.uscard);
      expect(EchDnsPolicy.builtinDomains, ['uscardforum.com']);
      expect(
        const EchDnsPolicy().queryName('www.uscardforum.com'),
        EchDnsPolicy.cloudflareQueryName,
      );
      final json = const EchDnsPolicy(customDomains: ['a.example']).toJson();
      expect(json['custom_domains'], ['uscardforum.com', 'a.example']);
      expect(EchDnsPolicy.fromJson(json).customDomains, ['a.example']);
    });

    test('自加的站不走 Cloudflare 入口：不确定它在不在 Cloudflare 后面', () {
      SiteContext.activate(custom);
      expect(EchDnsPolicy.builtinDomains, isEmpty);
      expect(const EchDnsPolicy().queryName('example.com'), 'example.com');
      expect(const EchDnsPolicy().queryName('linux.do'), 'linux.do');
    });
  });

  group('Cookie 主域判断', () {
    test('主站带 www 时认上级根域，不放宽到顶级域', () {
      SiteContext.activate(SitePresets.uscard);
      for (final domain in [
        'www.uscardforum.com',
        '.uscardforum.com',
        'uscardforum.com',
        'a.www.uscardforum.com',
      ]) {
        expect(CookieJarService.matchesAppHost(domain), isTrue, reason: domain);
      }
      for (final domain in ['com', '.com', 'other.com', 'cardforum.com']) {
        expect(CookieJarService.matchesAppHost(domain), isFalse, reason: domain);
      }
    });

    test('规则跟随当前站', () {
      SiteContext.activate(custom);
      expect(CookieJarService.matchesAppHost('example.com'), isTrue);
      expect(CookieJarService.matchesAppHost('linux.do'), isFalse);
    });
  });

  group('站内链接', () {
    test('带不带 www 都算本站，别的站不算', () {
      SiteContext.activate(SitePresets.uscard);
      expect(isSiteHost('uscardforum.com'), isTrue);
      expect(isSiteHost('WWW.USCARDFORUM.COM'), isTrue);
      expect(isSiteHost('notuscardforum.com'), isFalse);
      expect(isSiteHost('linux.do'), isFalse);
    });

    test('当前站是 linux.do 时，USCard链接是外链', () {
      SiteContext.activate(SitePresets.linuxdo);
      expect(isSiteHost('linux.do'), isTrue);
      expect(isSiteHost('www.uscardforum.com'), isFalse);
    });
  });

  group('登录配置', () {
    test('只有 linux.do 写死 hCaptcha sitekey 和会话 bootstrap', () {
      SiteContext.activate(SitePresets.linuxdo);
      expect(currentSiteCustomization, same(linuxdoCustomization));
      expect(currentSiteCustomization.hcaptchaSiteKey, isNotNull);
      expect(currentSiteCustomization.hasSessionBootstrapPlugin, isTrue);

      for (final site in [SitePresets.uscard, custom]) {
        SiteContext.activate(site);
        expect(currentSiteCustomization.hcaptchaSiteKey, isNull, reason: site.id);
        expect(
          currentSiteCustomization.hasSessionBootstrapPlugin,
          isFalse,
          reason: site.id,
        );
      }
    });

    test('User API Key 只申请 one_time_password，不保留 key', () {
      for (final site in [SitePresets.linuxdo, SitePresets.uscard, custom]) {
        SiteContext.activate(site);
        expect(UserApiKeyService.scopes, 'one_time_password', reason: site.id);
        expect(UserApiKeyService.keyWorthKeeping, isFalse, reason: site.id);
      }
    });

    test('站点设置决定 hCaptcha 和密码登录', () {
      final preloaded = PreloadedDataService();
      addTearDown(() => preloaded.debugSeed());

      preloaded.debugSeed(siteSettings: {});
      expect(preloaded.hcaptchaSiteKey, isNull);
      expect(preloaded.localLoginsEnabled, isTrue);

      preloaded.debugSeed(
        siteSettings: {
          'hcaptcha_site_key': 'abc',
          'enable_local_logins': false,
        },
      );
      expect(preloaded.hcaptchaSiteKey, 'abc');
      expect(preloaded.localLoginsEnabled, isFalse);
    });
  });

  group('子路径站的请求地址', () {
    Future<Uri> requestedUri(SiteProfile site, String path) async {
      SiteContext.activate(site);
      final adapter = _RecordingAdapter();
      final dio = Dio(BaseOptions(baseUrl: site.baseUrl))
        ..httpClientAdapter = adapter
        ..interceptors.add(RequestHeaderInterceptor(CsrfTokenService()));
      await dio.get<dynamic>(path);
      return adapter.lastUri!;
    }

    test('相对路径拼上前缀', () async {
      expect(
        (await requestedUri(custom, '/site.json')).toString(),
        'https://example.com/forum/site.json',
      );
    });

    test('服务端下发的路径已带前缀时不重复', () async {
      expect(
        (await requestedUri(custom, '/forum/latest?page=1')).toString(),
        'https://example.com/forum/latest?page=1',
      );
    });

    test('前缀只是开头相同的路径不动', () async {
      expect(
        (await requestedUri(custom, '/forumother/a')).toString(),
        'https://example.com/forum/forumother/a',
      );
    });

    test('根部署的站不受影响', () async {
      expect(
        (await requestedUri(SitePresets.linuxdo, '/latest')).toString(),
        'https://linux.do/latest',
      );
    });
  });

  test('密码重置等地址跟随当前站', () {
    SiteContext.activate(custom);
    expect(AppConstants.baseUrl, 'https://example.com/forum');
    expect(AppConstants.siteOrigin, 'https://example.com');
  });
}
