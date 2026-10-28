import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/config/site_customization.dart';
import 'package:fluxdo/config/sites/uscard.dart';
import 'package:fluxdo/utils/link_launcher.dart';
import 'package:fluxdo/utils/link_security.dart';
import 'package:fluxdo/widgets/common/smart_avatar.dart';

void main() {
  group('美卡链接安全配置', () {
    final config = uscardCustomization.linkSecurityConfig!;

    test('论坛主域和带不带 www 都算内部链接', () {
      for (final url in [
        'https://www.uscardforum.com/t/topic/1',
        'https://uscardforum.com/t/topic/1',
      ]) {
        expect(
          LinkSecurity.checkUrl(url, config),
          LinkRiskLevel.internal,
          reason: url,
        );
      }
    });

    test('局域网 IP 规则能匹配（正则反斜杠写对了）', () {
      for (final url in [
        'http://127.0.0.1:8080/',
        'http://10.1.2.3/',
        'http://192.168.1.20/',
        'http://172.16.0.5/',
        'http://169.254.10.1/',
      ]) {
        expect(
          LinkSecurity.checkUrl(url, config),
          LinkRiskLevel.internal,
          reason: url,
        );
      }
      // 不是局域网的地址照常按外部链接处理
      expect(
        LinkSecurity.checkUrl('http://172.32.0.5/', config),
        LinkRiskLevel.normal,
      );
    });

    test('美卡不挂 linux.do 的站点插件，也不改名上传音视频', () {
      expect(uscardCustomization.plugins, isEmpty);
      expect(uscardCustomization.mediaUploadAsXz, isFalse);
    });
  });

  test('isSiteHost：根域、www 和子域算本站，相似域名不算', () {
    for (final host in [
      'uscardforum.com',
      'www.uscardforum.com',
      'WWW.USCARDFORUM.COM',
      'cdn.uscardforum.com',
    ]) {
      expect(isSiteHost(host), isTrue, reason: host);
    }
    for (final host in [
      'notuscardforum.com',
      'uscardforum.com.evil.net',
      'linux.do',
      '',
    ]) {
      expect(isSiteHost(host), isFalse, reason: host);
    }
  });

  test('方形头像只对 linux.do 的 neo 生效，美卡同名用户不受影响', () {
    expect(
      isSquareAvatarUrl('https://linux.do/user_avatar/linux.do/neo/96/1.png'),
      isTrue,
    );
    expect(
      isSquareAvatarUrl(
        'https://www.uscardforum.com/user_avatar/www.uscardforum.com/neo/96/1.png',
      ),
      isFalse,
    );
  });
}
