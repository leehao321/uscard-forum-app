import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/site_profile.dart';
import 'package:fluxdo/services/qr_login_service.dart';
import 'package:fluxdo/services/site_context.dart';

void main() {
  group('QrLoginService payload codec', () {
    final service = QrLoginService.instance;

    test('encode/parse roundtrip with expiry', () {
      final exp = DateTime.utc(2030, 1, 2, 3, 4, 5);
      final payload = QrLoginPayload(
        version: QrLoginService.currentVersion,
          site: SiteContext.current.id,
        apiKey: 'abcdef0123456789',
        otp: 'deadbeefcafebabe',
        username: 'alice',
        expiresAt: exp,
      );
      final raw = service.encodePayload(payload);
      expect(raw.startsWith('pulseflow://qr-login?'), isTrue);
      expect(raw.contains('k='), isTrue);
      expect(raw.contains('o='), isTrue);

      final parsed = service.parsePayload(raw);
      expect(parsed, isNotNull);
      expect(parsed!.version, QrLoginService.currentVersion);
      expect(parsed.site, SiteContext.current.id);
      expect(parsed.apiKey, 'abcdef0123456789');
      expect(parsed.otp, 'deadbeefcafebabe');
      expect(parsed.username, 'alice');
      expect(parsed.expiresAt!.toUtc(), exp);
      expect(parsed.neverExpires, isFalse);
    });

    test('encode/parse never-expire (exp=0)', () {
      final payload = QrLoginPayload(
        version: QrLoginService.currentVersion,
          site: SiteContext.current.id,
        apiKey: 'key-never',
        otp: 'otp-never',
        username: 'bob',
        expiresAt: null,
      );
      final raw = service.encodePayload(payload);
      expect(raw.contains('exp=0'), isTrue);

      final parsed = service.parsePayload(raw);
      expect(parsed, isNotNull);
      expect(parsed!.neverExpires, isTrue);
      expect(parsed.expiresAt, isNull);
      expect(parsed.isExpired, isFalse);
    });

    test('reject non fluxdo scheme and v1 token payload', () {
      expect(service.parsePayload('https://linux.do/t/1'), isNull);
      expect(service.parsePayload('pulseflow://topic/1'), isNull);
      expect(service.parsePayload('not a uri'), isNull);
      // 旧 v1 `_t` 协议不再接受
      expect(
        service.parsePayload(
          'pulseflow://qr-login?v=1&t=oldtoken&u=alice&exp=9999999999999',
        ),
        isNull,
      );
    });

    test('requireValidPayload rejects expired key', () {
      final exp = DateTime.now().toUtc().subtract(const Duration(seconds: 5));
      final raw = service.encodePayload(
        QrLoginPayload(
          version: QrLoginService.currentVersion,
          site: SiteContext.current.id,
          apiKey: 'key',
          otp: 'otp',
          username: 'bob',
          expiresAt: exp,
        ),
      );
      expect(
        () => service.requireValidPayload(raw),
        throwsA(
          isA<QrLoginException>().having(
            (e) => e.error,
            'error',
            QrLoginError.expired,
          ),
        ),
      );
    });

    test('requireValidPayload rejects bad version', () {
      final raw = service.encodePayload(
        QrLoginPayload(
          version: 99,
          site: SiteContext.current.id,
          apiKey: 'key',
          otp: 'otp',
          username: 'bob',
          expiresAt: null,
        ),
      );
      expect(
        () => service.requireValidPayload(raw),
        throwsA(
          isA<QrLoginException>().having(
            (e) => e.error,
            'error',
            QrLoginError.unsupportedVersion,
          ),
        ),
      );
    });

    test('requireValidPayload accepts fresh never-expire payload', () {
      final raw = service.encodePayload(
        QrLoginPayload(
          version: QrLoginService.currentVersion,
          site: SiteContext.current.id,
          apiKey: 'key',
          otp: 'otp',
          username: 'bob',
          expiresAt: null,
        ),
      );
      final valid = service.requireValidPayload(raw);
      expect(valid.apiKey, 'key');
      expect(valid.otp, 'otp');
      expect(valid.isExpired, isFalse);
      expect(valid.neverExpires, isTrue);
    });

    test('requireValidPayload accepts future-dated expiry', () {
      final exp = DateTime.now().toUtc().add(const Duration(hours: 1));
      final raw = service.encodePayload(
        QrLoginPayload(
          version: QrLoginService.currentVersion,
          site: SiteContext.current.id,
          apiKey: 'key',
          otp: 'otp',
          username: 'bob',
          expiresAt: exp,
        ),
      );
      final valid = service.requireValidPayload(raw);
      expect(valid.apiKey, 'key');
      expect(valid.isExpired, isFalse);
    });
  });

  group('F1 二维码绑定站点', () {
    final service = QrLoginService.instance;

    QrLoginPayload payloadFor(String site) => QrLoginPayload(
      version: QrLoginService.currentVersion,
      site: site,
      apiKey: 'key',
      otp: 'otp',
      username: 'alice',
    );

    tearDown(SiteContext.debugReset);

    test('别的论坛的二维码被拒绝，OTP 不会发出去', () {
      SiteContext.activate(SitePresets.linuxdo);
      final raw = service.encodePayload(payloadFor('www.uscardforum.com'));
      expect(
        () => service.requireValidPayload(raw),
        throwsA(
          isA<QrLoginException>()
              .having((e) => e.error, 'error', QrLoginError.siteMismatch)
              .having((e) => e.message, 'message', contains('www.uscardforum.com')),
        ),
      );
    });

    test('同一个论坛可以用，www 和裸域算同一个', () {
      SiteContext.activate(SitePresets.uscard);
      expect(service.requireValidPayload(service.encodePayload(payloadFor('www.uscardforum.com'))).otp, 'otp');
      expect(service.requireValidPayload(service.encodePayload(payloadFor('uscardforum.com'))).otp, 'otp');
    });

    test('子路径站不和同 host 的根站混用', () {
      SiteContext.activate(SiteProfile(baseUrl: 'https://example.com/a', title: 'A'));
      expect(
        () => service.requireValidPayload(service.encodePayload(payloadFor('example.com'))),
        throwsA(isA<QrLoginException>()),
      );
    });

    test('没有站点的二维码被拒绝', () {
      SiteContext.activate(SitePresets.uscard);
      expect(
        () => service.requireValidPayload(service.encodePayload(payloadFor(''))),
        throwsA(isA<QrLoginException>()),
      );
    });

    test('旧版 v2 二维码提示升级', () {
      SiteContext.activate(SitePresets.uscard);
      expect(
        () => service.requireValidPayload('pulseflow://qr-login?v=2&k=k&o=o&u=a&exp=0'),
        throwsA(
          isA<QrLoginException>().having((e) => e.error, 'error', QrLoginError.unsupportedVersion),
        ),
      );
    });
  });
}
