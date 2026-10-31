import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/constants.dart';

// 0.4.0 M9.7 / P-1：Sec-CH-UA-* 只在 Android 上生成；iOS / macOS 不发。
void main() {
  test('Client Hints 只在 Android 上生成', () {
    expect(AppConstants.clientHintsEnabledFor(isAndroid: true), isTrue);
    expect(AppConstants.clientHintsEnabledFor(isAndroid: false), isFalse);
  });
}
