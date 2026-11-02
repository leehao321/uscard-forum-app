import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/site_profile.dart';

void main() {
  group('normalizeSiteBaseUrl', () {
    test('补 https、去尾斜杠、host 转小写', () {
      expect(normalizeSiteBaseUrl('Example.COM'), 'https://example.com');
      expect(normalizeSiteBaseUrl('  example.com/  '), 'https://example.com');
      expect(normalizeSiteBaseUrl('https://example.com'), 'https://example.com');
      expect(normalizeSiteBaseUrl('http://example.com'), 'https://example.com');
    });

    test('保留子路径和非默认端口', () {
      expect(
        normalizeSiteBaseUrl('example.com/forum/'),
        'https://example.com/forum',
      );
      expect(
        normalizeSiteBaseUrl('example.com:8443/a/b'),
        'https://example.com:8443/a/b',
      );
      expect(normalizeSiteBaseUrl('example.com:443'), 'https://example.com');
    });

    test('粘贴帖子链接时只留站点地址', () {
      expect(
        normalizeSiteBaseUrl('https://example.com/t/some-topic/123/4?u=a#x'),
        'https://example.com',
      );
      expect(
        normalizeSiteBaseUrl('example.com/forum/latest'),
        'https://example.com/forum',
      );
      expect(normalizeSiteBaseUrl('example.com/site.json'), 'https://example.com');
    });

    test('非法输入返回 null', () {
      for (final input in [
        '',
        '   ',
        'localhost',
        'not a domain',
        'ftp://example.com',
        'user:pass@example.com',
        '-bad.example.com',
        'example..com',
      ]) {
        expect(normalizeSiteBaseUrl(input), isNull, reason: input);
      }
    });
  });

  group('SiteProfile', () {
    test('派生字段', () {
      final site = SiteProfile(
        baseUrl: 'https://example.com:8443/forum',
        title: 'Example',
      );
      expect(site.id, 'example.com:8443/forum');
      expect(site.host, 'example.com');
      expect(site.origin, 'https://example.com:8443');
      expect(site.basePath, '/forum');
      expect(site.featurePack, SiteFeaturePack.generic);
      expect(site.allowBackgroundAccess, isTrue);
    });

    test('同 host 不同子路径是不同站点', () {
      final a = SiteProfile(baseUrl: 'https://example.com/a', title: 'A');
      final b = SiteProfile(baseUrl: 'https://example.com/b', title: 'B');
      expect(a.id, isNot(b.id));
    });

    test('功能包由地址决定，不从持久化数据读取', () {
      final site = SiteProfile.tryFromJson({
        'baseUrl': 'https://example.com',
        'title': 'Fake',
        'featurePack': 'linuxdo',
      })!;
      expect(site.featurePack, SiteFeaturePack.generic);
      expect(site.toJson().containsKey('featurePack'), isFalse);
    });

    test('JSON 往返', () {
      final site = SiteProfile(
        baseUrl: 'https://example.com/forum',
        title: 'Example',
        logoUrl: 'https://example.com/logo.png',
      );
      final restored = SiteProfile.tryFromJson(site.toJson())!;
      expect(restored.baseUrl, site.baseUrl);
      expect(restored.title, site.title);
      expect(restored.logoUrl, site.logoUrl);
      expect(restored.faviconUrl, isNull);
    });

    test('损坏数据返回 null，缺标题时用 host', () {
      expect(SiteProfile.tryFromJson('x'), isNull);
      expect(SiteProfile.tryFromJson({'title': 'a'}), isNull);
      expect(SiteProfile.tryFromJson({'baseUrl': 'not a domain'}), isNull);
      expect(
        SiteProfile.tryFromJson({'baseUrl': 'https://example.com'})!.title,
        'example.com',
      );
    });
  });

  group('SitePresets', () {
    test('美卡排第一，后台访问关闭', () {
      expect(SitePresets.all.first, same(SitePresets.uscard));
      expect(SitePresets.uscard.allowBackgroundAccess, isFalse);
      expect(SitePresets.linuxdo.allowBackgroundAccess, isTrue);
    });

    test('裸域和 www 指向同一预置站', () {
      for (final url in ['https://uscardforum.com', 'https://www.uscardforum.com']) {
        expect(SitePresets.match(url), same(SitePresets.uscard), reason: url);
      }
      for (final url in ['https://linux.do', 'https://www.linux.do']) {
        expect(SitePresets.match(url), same(SitePresets.linuxdo), reason: url);
      }
    });

    test('子路径、端口、子域不算预置站', () {
      for (final url in [
        'https://linux.do/forum',
        'https://linux.do:8443',
        'https://evil.linux.do',
        'https://example.com',
      ]) {
        expect(SitePresets.match(url), isNull, reason: url);
      }
    });

    test('持久化后的预置站仍拿到专属功能包', () {
      final restored = SiteProfile.tryFromJson(SitePresets.uscard.toJson())!;
      expect(restored.featurePack, SiteFeaturePack.uscard);
    });
  });
}
