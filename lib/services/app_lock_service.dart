import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'toast_service.dart';

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
  bool _obscured = false;
  bool _authenticating = false;
  DateTime? _backgroundAt;
  bool _initialized = false;

  bool get enabled => _enabled;
  int get timeoutSeconds => _timeoutSeconds;
  bool get locked => _locked;
  bool get authenticating => _authenticating;

  /// 离开前台时盖上的隐私遮罩（不弹认证）：多任务缩略图和回前台的第一帧
  /// 都看不到内容。回到前台没超时就撤掉，超时就转为上锁。
  bool get obscured => _obscured;

  /// 界面当前被遮住（上锁或隐私遮罩），阅读计时等应当暂停。
  bool get covering => _locked || _obscured;

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
        if (!_authenticating) {
          _backgroundAt ??= DateTime.now();
          _setObscured(true);
        }
      case AppLifecycleState.inactive:
        // iOS 进多任务、拉控制中心前都会先 inactive：先盖上遮罩再截缩略图。
        // 桌面端 inactive 只是窗口失去焦点，不盖（最小化时走 hidden）。
        if (!_authenticating && !kIsWeb && Platform.isIOS) _setObscured(true);
      case AppLifecycleState.resumed:
        final since = _backgroundAt;
        _backgroundAt = null;
        if (since != null &&
            DateTime.now().difference(since).inSeconds >= _timeoutSeconds &&
            !_locked) {
          _locked = true;
        }
        _obscured = false;
        notifyListeners();
      case AppLifecycleState.detached:
        break;
    }
  }

  void _setObscured(bool value) {
    if (_obscured == value) return;
    _obscured = value;
    notifyListeners();
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
      return true;
    }
    // 设备已经没有 Face ID / 密码（开锁后在系统里关掉了密码）时认证永远失败，
    // 锁屏又挡住了设置页：自动关闭应用锁，避免把用户永久锁在 App 外。
    if (!await isAvailable()) {
      _enabled = false;
      _locked = false;
      _obscured = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, false);
      notifyListeners();
      ToastService.showInfo('这台设备没有设置密码，应用锁已自动关闭');
      return true;
    }
    return false;
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
    _obscured = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
    if (!_initialized) await init();
    notifyListeners();
    return true;
  }

  /// 测试用：直接设定状态，绕过系统认证
  @visibleForTesting
  void debugSetState({
    bool enabled = false,
    bool locked = false,
    bool obscured = false,
    int timeoutSeconds = 60,
  }) {
    _enabled = enabled;
    _locked = locked;
    _obscured = obscured;
    _timeoutSeconds = timeoutSeconds;
    _backgroundAt = null;
    _authenticating = false;
    notifyListeners();
  }

  Future<void> setTimeout(int seconds) async {
    _timeoutSeconds = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_timeoutKey, seconds);
    notifyListeners();
  }
}
