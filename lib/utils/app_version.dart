import 'package:package_info_plus/package_info_plus.dart';

/// 展示用版本号：「0.4.0 (2026103014)」，build 号为空时只显示版本号。
///
/// 关于页和启动页都显示 build 号，装包后能直接核对装的是哪一包
/// （两个包同版本号时装错过旧包，D-019）。检查更新比较版本时仍用
/// 不带 build 号的 [PackageInfo.version]。
String formatDisplayVersion(String version, String buildNumber) =>
    buildNumber.isEmpty ? version : '$version ($buildNumber)';

/// 读取当前安装包的展示用版本号，见 [formatDisplayVersion]
Future<String> loadDisplayVersion() async {
  final info = await PackageInfo.fromPlatform();
  return formatDisplayVersion(info.version, info.buildNumber);
}
