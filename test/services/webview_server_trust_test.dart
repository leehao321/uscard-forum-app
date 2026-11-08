import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/webview_settings.dart';

// 网页视图的证书回调：系统验证没通过的证书，放行就等于不验证。
// iOS 上一律不放行（代理自己签发的证书已由原生层放行），其他平台保持上游原有行为。
void main() {
  bool proceeds({required bool gatewayMode, required bool isIOS}) =>
      WebViewSettings.proceedsUntrustedServerCertificate(gatewayMode: gatewayMode, isIOS: isIOS);

  test('iOS：开着 DoH 网关也不放行系统不认的证书（防止假冒网站）', () {
    expect(proceeds(gatewayMode: true, isIOS: true), isFalse);
  });

  test('没开 DoH 网关：哪个平台都不放行，走系统默认验证', () {
    expect(proceeds(gatewayMode: false, isIOS: true), isFalse);
    expect(proceeds(gatewayMode: false, isIOS: false), isFalse);
  });

  test('其他平台开着网关（MITM 模式）：照旧放行，上游原有行为不变', () {
    expect(proceeds(gatewayMode: true, isIOS: false), isTrue);
  });
}
