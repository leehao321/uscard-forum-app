import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/utils/app_version.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  test('展示版本带 build 号', () {
    expect(formatDisplayVersion('0.4.0', '2026103014'), '0.4.0 (2026103014)');
  });

  test('build 号为空时只显示版本号', () {
    expect(formatDisplayVersion('0.4.0', ''), '0.4.0');
  });

  test('从安装包信息读取', () async {
    PackageInfo.setMockInitialValues(
      appName: 'USCard Forum',
      packageName: 'com.hao.uscardforum',
      version: '0.4.0',
      buildNumber: '2026103014',
      buildSignature: '',
    );
    expect(await loadDisplayVersion(), '0.4.0 (2026103014)');
  });
}
