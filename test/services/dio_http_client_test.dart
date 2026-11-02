import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/site_profile.dart';
import 'package:fluxdo/services/dio_http_client.dart';
import 'package:fluxdo/services/site_context.dart';

void main() {
  tearDown(SiteContext.debugReset);

  group('主站带 www 的站', () {
    setUp(() => SiteContext.activate(SitePresets.uscard));

    group('canonicalRequestUri', () {
      test('不带 www 的根域改写成主站，路径与查询保留', () {
        expect(
          DioHttpClient.canonicalRequestUri(
            Uri.parse(
              'https://uscardforum.com/uploads/default/original/1X/a.png?v=2',
            ),
          ).toString(),
          'https://www.uscardforum.com/uploads/default/original/1X/a.png?v=2',
        );
      });

      test('主站、根域其他子域、外站和相对地址原样返回', () {
        for (final url in [
          'https://www.uscardforum.com/a.png',
          'https://cdn.uscardforum.com/a.png',
          'https://notuscardforum.com/a.png',
          'https://uscardforum.com.evil.example/a.png',
          '/uploads/default/original/1X/a.png',
        ]) {
          expect(
            DioHttpClient.canonicalRequestUri(Uri.parse(url)).toString(),
            url,
            reason: url,
          );
        }
      });
    });

    group('usesCookieDio', () {
      bool usesCookieDio(String url) => DioHttpClient.usesCookieDio(
        DioHttpClient.canonicalRequestUri(Uri.parse(url)),
      );

      test('主站 www 与其子域、改写后的根域走带 cookie 的主域 dio', () {
        for (final url in [
          'https://www.uscardforum.com/uploads/default/original/1X/a.png',
          'https://WWW.USCARDFORUM.COM/user_avatar/www.uscardforum.com/a/96/1.png',
          'https://cdn.www.uscardforum.com/a.png',
          'https://uscardforum.com/uploads/default/original/1X/a.png',
        ]) {
          expect(usesCookieDio(url), isTrue, reason: url);
        }
      });

      test('根域其他子域、外站、同名后缀和相对地址走不带 cookie 的 CDN', () {
        for (final url in [
          'https://cdn.uscardforum.com/a.png',
          'https://notuscardforum.com/a.png',
          'https://uscardforum.com.evil.example/a.png',
          'https://i.imgur.com/a.png',
          '/uploads/default/original/1X/a.png',
        ]) {
          expect(usesCookieDio(url), isFalse, reason: url);
        }
      });
    });
  });

  group('主站不带 www 的站', () {
    setUp(() => SiteContext.activate(SitePresets.linuxdo));

    test('不改写，子域走带 cookie 的主域 dio，别的站不走', () {
      final same = Uri.parse('https://linux.do/uploads/a.png');
      expect(DioHttpClient.canonicalRequestUri(same), same);
      expect(DioHttpClient.usesCookieDio(same), isTrue);
      expect(
        DioHttpClient.usesCookieDio(Uri.parse('https://auth.linux.do/a')),
        isTrue,
      );
      expect(
        DioHttpClient.usesCookieDio(
          Uri.parse('https://www.uscardforum.com/a.png'),
        ),
        isFalse,
      );
    });
  });

  test('换站后主域判断跟随当前站', () {
    SiteContext.activate(SitePresets.linuxdo);
    final url = Uri.parse('https://example.com/forum/a.png');
    expect(DioHttpClient.usesCookieDio(url), isFalse);

    SiteContext.activate(
      SiteProfile(baseUrl: 'https://example.com/forum', title: 'E'),
    );
    expect(DioHttpClient.usesCookieDio(url), isTrue);
    expect(
      DioHttpClient.usesCookieDio(Uri.parse('https://linux.do/a.png')),
      isFalse,
    );
  });
}
