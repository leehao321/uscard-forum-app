import 'dart:async';
import 'dart:io';

import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/site_profile.dart';
import 'package:fluxdo/services/auth_session.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:fluxdo/services/network/cookie/app_cookie_manager.dart';
import 'package:fluxdo/services/network/cookie/cookie_jar_service.dart';
import 'package:fluxdo/services/network/cookie/csrf_token_service.dart';
import 'package:fluxdo/services/site_context.dart';
import 'package:fluxdo/services/site_registry_service.dart';
import 'package:fluxdo/services/site_switch_work.dart';
import 'package:fluxdo/storage/reading_stats_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 等放行后才返回响应，模拟切站时还在路上的请求。
class _HeldAdapter implements HttpClientAdapter {
  final gate = Completer<void>();
  var requested = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requested.complete();
    await gate.future;
    return ResponseBody.fromString(
      '{"csrf":"token-of-a"}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final a = SitePresets.uscard;
  final b = SiteProfile(baseUrl: 'https://b.example.com', title: 'B');
  late Directory documents;

  Uri home(SiteProfile site) => Uri.parse('${site.baseUrl}/');

  setUpAll(() async {
    documents = await Directory.systemTemp.createTemp('site-switch-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => documents.path,
        );
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    SiteContext.activate(a);
    await CookieJarService().initialize();
  });

  tearDownAll(() => documents.delete(recursive: true));

  setUp(() async {
    SiteContext.activate(a);
    CookieJarService().useJar(await CookieJarService().openJarFor(a));
  });

  group('Cookie 存储', () {
    test('Cookie 管理器跟着全局存储走：切站后不会写进旧站的目录', () async {
      final service = CookieJarService();
      final manager = AppCookieManager(service.cookieJar);
      final jarOfB = await service.openJarFor(b);
      service.useJar(jarOfB);
      expect(identical(manager.cookieJar, jarOfB), isTrue);
    });

    test('自带存储的管理器不受影响', () async {
      final own = CookieJar();
      final manager = AppCookieManager(own);
      CookieJarService().useJar(await CookieJarService().openJarFor(b));
      expect(identical(manager.cookieJar, own), isTrue);
    });

    test('两站的 Cookie 互不可见，切回来 A 的登录还在', () async {
      final service = CookieJarService();
      final jarOfA = service.cookieJar;
      await jarOfA.saveFromResponse(home(a), [Cookie('_t', 'token-of-a')..maxAge = 3600]);

      final jarOfB = await service.openJarFor(b);
      service.useJar(jarOfB);
      await jarOfB.saveFromResponse(home(b), [Cookie('_t', 'token-of-b')..maxAge = 3600]);
      expect(
        (await jarOfB.loadForRequest(home(a))).map((c) => c.value),
        isNot(contains('token-of-a')),
      );

      final jarOfAAgain = await service.openJarFor(a);
      service.useJar(jarOfAAgain);
      expect(
        (await jarOfAAgain.loadForRequest(home(a))).map((c) => c.value),
        contains('token-of-a'),
      );
      expect(
        (await jarOfAAgain.loadForRequest(home(b))).map((c) => c.value),
        isNot(contains('token-of-b')),
      );
    });

    test('存储目录按站分开', () async {
      await CookieJarService().openJarFor(a);
      await CookieJarService().openJarFor(b);
      expect(Directory('${documents.path}/.cookies/${a.storageId}').existsSync(), isTrue);
      expect(Directory('${documents.path}/.cookies/${b.storageId}').existsSync(), isTrue);
      expect(a.storageId, isNot(b.storageId));
    });
  });

  group('CSRF', () {
    final service = CsrfTokenService();

    test('切站清内存，不删旧站保存的 token', () async {
      service.setCsrfToken('saved-a');
      await Future<void>.delayed(Duration.zero);

      service.resetForSiteSwitch();
      expect(service.csrfToken, isNull);

      SiteContext.activate(b);
      await service.init();
      expect(service.csrfToken, isNull, reason: 'B 站没有存过');

      SiteContext.activate(a);
      await service.init();
      expect(service.csrfToken, 'saved-a', reason: 'A 站的还在');
      service.resetForSiteSwitch();
    });

    test('切站前发出的刷新晚到：不写内存，也不存到新站的 key 下', () async {
      final adapter = _HeldAdapter();
      service.attachDio(Dio()..httpClientAdapter = adapter);
      // attachDio 只认第一次，这里靠 DiscourseService 没初始化保证用的是这个 Dio
      final pending = service.updateCsrfToken();
      await adapter.requested.future;

      service.resetForSiteSwitch();
      SiteContext.activate(b);
      adapter.gate.complete();
      await pending;
      await Future<void>.delayed(Duration.zero);

      expect(service.csrfToken, isNull);
      service.resetForSiteSwitch();
      await service.init();
      expect(service.csrfToken, isNull, reason: 'A 的 token 不能落到 B 的 key 下');
    });
  });

  group('阅读统计', () {
    Future<Map<String, Object?>> stored(SiteProfile site) async {
      final prefs = await SharedPreferences.getInstance();
      return {'raw': prefs.getString(site.scopedKey('reading_stats_v1'))};
    }

    test('A 的统计留在 A，不会覆盖 B 的历史', () async {
      final store = ReadingStatsStore.instance;
      final prefs = await SharedPreferences.getInstance();
      final today = ReadingStatsStore.dayKey(DateTime.now());
      await prefs.setString(
        b.scopedKey('reading_stats_v1'),
        '{"$today":{"ms":7000,"t":[99]}}',
      );

      store.addReading(1, 1000);
      await store.flush();
      store.resetForSiteSwitch();
      SiteContext.activate(b);

      store.addReading(2, 2000);
      await store.flush();

      final ofA = (await stored(a))['raw'] as String;
      final ofB = (await stored(b))['raw'] as String;
      expect(ofA, contains('[1]'));
      expect(ofA, isNot(contains('2000')));
      expect(ofB, contains('9000'), reason: 'B 的 7000 加上新的 2000');
      expect(ofB, contains('99'));
      store.resetForSiteSwitch();
    });
  });

  group('真实切站', () {
    test('换站后登录态、Cookie 存储、请求地址、AI 前缀都是新站的', () async {
      final prefs = await SharedPreferences.getInstance();
      final registry = SiteRegistryService();
      await registry.init(prefs);
      final discourse = DiscourseService();
      discourse.setToken('token-of-a');
      expect(discourse.isAuthenticated, isTrue);
      final oldJar = CookieJarService().cookieJar;
      final generation = AuthSession().generation;

      final work = DeviceSiteSwitchWork(registry: registry);
      final prepared = await work.prepareSite(b);
      expect(registry.current!.id, b.id, reason: '先持久化');
      expect(SiteContext.current.id, a.id, reason: '还没换');

      work.commitSite(b, prepared);

      expect(SiteContext.current.id, b.id);
      expect(discourse.isAuthenticated, isFalse);
      expect(discourse.currentUserNotifier.value, isNull);
      expect(discourse.dio.options.baseUrl, b.baseUrl);
      expect(identical(CookieJarService().cookieJar, oldJar), isFalse);
      expect(identical(CookieJarService().cookieJar, prepared), isTrue);
      expect(CsrfTokenService().csrfToken, isNull);
      expect(AiChatStorageService.keyScope, b.scopePrefix);
      expect(AuthSession().generation, greaterThan(generation));
    });
  });
}
