import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/site_profile.dart';
import 'package:fluxdo/services/clipboard_topic_link_service.dart';
import 'package:fluxdo/services/deep_link_service.dart';
import 'package:fluxdo/services/site_context.dart';
import 'package:fluxdo/services/site_registry_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final custom = SiteProfile(baseUrl: 'https://example.com/forum', title: 'E');
  final service = DeepLinkService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SiteContext.debugReset();
    await SiteRegistryService.instance.init(
      await SharedPreferences.getInstance(),
    );
  });

  tearDown(SiteContext.debugReset);

  group('SiteProfile 路径与域名', () {
    test('ownsHost 认根域和子域，不认同名后缀', () {
      expect(SitePresets.uscard.ownsHost('uscardforum.com'), isTrue);
      expect(SitePresets.uscard.ownsHost('WWW.USCARDFORUM.COM'), isTrue);
      expect(SitePresets.uscard.ownsHost('notuscardforum.com'), isFalse);
      expect(SitePresets.linuxdo.ownsHost('www.uscardforum.com'), isFalse);
    });

    test('sitePath 去掉子路径前缀', () {
      expect(custom.sitePath('/forum/t/abc/12'), '/t/abc/12');
      expect(custom.sitePath('/forum'), '/');
      expect(custom.sitePath('/forumother/t/1'), '/forumother/t/1');
      expect(SitePresets.linuxdo.sitePath('/t/abc/12'), '/t/abc/12');
    });
  });

  group('深链接管范围', () {
    test('当前站接管，没注册的站不接管', () {
      SiteContext.activate(SitePresets.uscard);
      expect(
        service.canHandleUri(Uri.parse('https://www.uscardforum.com/t/1')),
        isTrue,
      );
      expect(
        service.canHandleUri(Uri.parse('https://uscardforum.com/t/1')),
        isTrue,
      );
      expect(service.canHandleUri(Uri.parse('https://linux.do/t/1')), isFalse);
      expect(service.canHandleUri(Uri.parse('https://example.com/t/1')), isFalse);
    });

    test('已注册的其他站也接管', () async {
      SiteContext.activate(SitePresets.uscard);
      await SiteRegistryService.instance.addOrUpdate(custom);
      expect(
        service.canHandleUri(Uri.parse('https://example.com/forum/t/1')),
        isTrue,
      );
    });

    test('两个 App scheme 和授权回调都接管', () {
      expect(service.canHandleUri(Uri.parse('fluxdo://topic/1')), isTrue);
      expect(service.canHandleUri(Uri.parse('uscardforum://topic/1')), isTrue);
      expect(
        service.canHandleUri(Uri.parse('discourse://auth_redirect?payload=x')),
        isTrue,
      );
      expect(service.canHandleUri(Uri.parse('discourse://other')), isFalse);
      expect(service.canHandleUri(Uri.parse('ftp://linux.do/t/1')), isFalse);
    });
  });

  group('剪贴板话题链接', () {
    bool detects(String text) =>
        ClipboardTopicLinkService.instance.findFirstTopicLink(text) != null;

    test('只认当前站，带不带 www 都行', () {
      SiteContext.activate(SitePresets.uscard);
      expect(detects('看这个 https://www.uscardforum.com/t/abc/12 吧'), isTrue);
      expect(detects('https://uscardforum.com/t/abc/12'), isTrue);
      expect(detects('https://linux.do/t/abc/12'), isFalse);
    });

    test('换站后不再认旧站', () {
      SiteContext.activate(SitePresets.linuxdo);
      expect(detects('https://linux.do/t/abc/12'), isTrue);
      expect(detects('https://www.uscardforum.com/t/abc/12'), isFalse);
    });

    test('子路径站', () {
      SiteContext.activate(custom);
      expect(detects('https://example.com/forum/t/abc/12'), isTrue);
      expect(detects('https://example.com/forum/u/abc'), isFalse);
    });
  });
}
