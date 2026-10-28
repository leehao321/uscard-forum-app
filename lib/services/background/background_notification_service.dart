import 'package:flutter/foundation.dart';

/// 后台通知统一管理入口（美卡论坛版：已停用）
///
/// 论坛条款禁止非浏览器程序自动访问论坛，所以不再做任何后台保活或定时拉取：
/// - Android 前台服务、iOS BGTaskScheduler / Workmanager 定期唤醒全部移除
/// - App 切到后台后 MessageBus 轮询直接停止（见 `MessageBusService.enterBackgroundMode`）
///
/// 保留这个类和方法签名只是为了不改动 main.dart 里的调用点，方法本身不做任何事。
class BackgroundNotificationService {
  static final BackgroundNotificationService _instance =
      BackgroundNotificationService._internal();
  factory BackgroundNotificationService() => _instance;
  BackgroundNotificationService._internal();

  /// 初始化（在 main() 中调用一次）：空操作
  Future<void> initialize() async {}

  /// 启用后台通知：空操作
  Future<void> enable(int userId) async {
    debugPrint('[BackgroundNotification] 已停用，忽略 enable');
  }

  /// 禁用后台通知：空操作
  Future<void> disable() async {}

  bool get isEnabled => false;
}
