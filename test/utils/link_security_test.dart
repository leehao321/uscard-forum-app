import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/config/site_customization.dart';
import 'package:fluxdo/config/sites/generic.dart';
import 'package:fluxdo/config/sites/linuxdo.dart';
import 'package:fluxdo/utils/link_security.dart';

void main() {
  final configs = <String, LinkSecurityConfig>{
    '通用站': genericCustomization('example.com').linkSecurityConfig!,
    'linux.do': linuxdoCustomization.linkSecurityConfig!,
  };

  configs.forEach((name, config) {
    group(name, () {
      LinkRiskLevel level(String url) => LinkSecurity.checkUrl(url, config);

      test('URL 里出现内网 IP 形状的文字，不算内部链接', () {
        for (final url in [
          'https://evil.example/app-10.1.2.3.apk',
          'https://evil.example/?ip=192.168.1.1',
          'https://evil.example/r/127.0.0.1',
          'https://evil.example/v110.1.2.3',
          'https://evil.example/#172.16.0.1',
          'https://evil.example/169.254.1.1',
          'https://10.0.0.1.evil.example/',
          'https://192.168.1.1.evil.example/x',
          'https://user:10.0.0.1@evil.example/',
        ]) {
          expect(level(url), LinkRiskLevel.normal, reason: url);
        }
      });

      test('真正的内网地址仍是内部链接', () {
        for (final url in [
          'http://10.0.0.1/',
          'http://10.0.0.1',
          'http://10.0.0.1:8080/x',
          'https://192.168.1.1/admin?a=1',
          'http://127.0.0.1:3000',
          'http://172.16.0.1#top',
          'http://169.254.1.1/',
        ]) {
          expect(level(url), LinkRiskLevel.internal, reason: url);
        }
      });

      test('不在内网范围的 IP 不算', () {
        expect(level('http://172.32.0.1/'), LinkRiskLevel.normal);
        expect(level('http://11.0.0.1/'), LinkRiskLevel.normal);
      });
    });
  });

  test('通用站自己的域名仍是内部链接', () {
    final config = configs['通用站']!;
    expect(LinkSecurity.checkUrl('https://example.com/t/1', config), LinkRiskLevel.internal);
    expect(LinkSecurity.checkUrl('https://cdn.example.com/a', config), LinkRiskLevel.internal);
  });

  test('风险和危险规则优先级不变', () {
    final config = configs['通用站']!;
    expect(LinkSecurity.checkUrl('https://bit.ly/10.0.0.1', config), LinkRiskLevel.risky);
    expect(LinkSecurity.checkUrl('https://x.example/?aff=1', config), LinkRiskLevel.dangerous);
  });
}
