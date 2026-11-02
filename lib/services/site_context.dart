import 'package:flutter/foundation.dart';

import '../models/site_profile.dart';

/// 本次运行连接的站点。
///
/// 进程内只设置一次（见 `SiteRegistryService.init`），换站要重启生效。
/// 未设置时回落到 linux.do，只有首启选站之前和测试会走到这里。
///
/// 注意：静态状态不跨 isolate。独立 isolate 的入口（如 iOS 后台任务）如果要访问
/// 论坛，必须先调用 `SiteRegistryService.init`；`compute` 里的纯解析函数不要读
/// `AppConstants.baseUrl`，需要时由主 isolate 传参。
class SiteContext {
  SiteContext._();

  static SiteProfile? _current;

  static SiteProfile get current => _current ?? SitePresets.linuxdo;

  /// 是否已确定本次运行的站点。
  static bool get isConfigured => _current != null;

  static void activate(SiteProfile site) {
    _current = site;
  }

  @visibleForTesting
  static void debugReset() {
    _current = null;
  }
}
