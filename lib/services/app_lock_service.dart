import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用锁：开启后冷启动或在后台超过设定时间，回到 App 要先用
/// Face ID / Touch ID / 设备密码（Windows Hello）解锁。
///
/// Android 需要 FlutterFragmentActivity，目前不开放。
class AppLockService extends ChangeNotifier with WidgetsBindingObserver {
  AppLockService._();

  static final AppLockService instance = AppLockService._();

  static const _enabledKey = 'app_lock_enabled';
  static const _timeoutKey = 'app_lock_timeout_seconds';

  /// 可选的后台多久后上锁
  static const timeoutChoices = <int, String>{
    0: '立即',
    60: '1 分钟',
    300: '5 分钟',
    900: '15 分钟',
  };

  static bool get isSupportedPlatform =>
      !kIsWeb && (Platform.isIOS || Platform.isMacOS || Platform.isWindows);

  final LocalAuthentication _auth = LocalAuthentication();

  bool _enabled = false;
  int _timeoutSeconds = 60;
  bool _locked = false;
  bool _authenticating = false;
  DateTime? _backgroundAt;
  bool _initialized = false;

  bool get enabled => _enabled;
  int get timeoutSeconds => _timeoutSeconds;
  bool get locked => _locked;
  bool get authenticating => _authenticating;

  /// 启动时调用一次：读取设置，开启时先上锁
  Future<void> init() async {
    if (_initialized || !isSupportedPlatform) return;
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? false;
    _timeoutSeconds = prefs.getInt(_timeoutKey) ?? 60;
    _locked = _enabled;
    WidgetsBinding.instance.addObserver(this);
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_enabled) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // 解锁弹窗本身也会让 App 短暂失去前台，认证中不算进后台
        if (!_authenticating) _backgroundAt ??= DateTime.now();
      case AppLifecycleState.resumed:
        final since = _backgroundAt;
        _backgroundAt = null;
        if (since != null &&
            DateTime.now().difference(since).inSeconds >= _timeoutSeconds &&
            !_locked) {
          _locked = true;
          notifyListeners();
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// 弹出系统认证；成功返回 true
  Future<bool> _authenticate(String reason) async {
    if (_authenticating) return false;
    _authenticating = true;
    notifyListeners();
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
    } catch (e) {
      debugPrint('[AppLock] 认证失败: $e');
      return false;
    } finally {
      _authenticating = false;
      notifyListeners();
    }
  }

  Future<bool> unlock() async {
    final ok = await _authenticate('解锁 USCard Forum');
    if (ok) {
      _locked = false;
      notifyListeners();
    }
    return ok;
  }

  /// 设备是否能用生物识别或设备密码
  Future<bool> isAvailable() async {
    if (!isSupportedPlatform) return false;
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// 开关应用锁：开启和关闭都要先认证一次，确认是本人
  Future<bool> setEnabled(bool value) async {
    if (value == _enabled) return true;
    final ok = await _authenticate(value ? '开启应用锁' : '关闭应用锁');
    if (!ok) return false;
    _enabled = value;
    _locked = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
    if (!_initialized) await init();
    notifyListeners();
    return true;
  }

  Future<void> setTimeout(int seconds) async {
    _timeoutSeconds = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_timeoutKey, seconds);
    notifyListeners();
  }
}
