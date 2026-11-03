import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 全局会话代管理器
/// 每次登录/登出状态变更时递增 generation，所有旧请求自动失效
class AuthSession {
  static final AuthSession _instance = AuthSession._internal();
  factory AuthSession() => _instance;
  AuthSession._internal();

  static const _minPruneThreshold = 256;

  int _generation = 0;

  /// 在途请求的令牌，推进时逐个取消。
  ///
  /// 只留弱引用：令牌身上挂着 dio 的取消监听，监听又抓着响应。强引用会把这个
  /// 会话里的每个响应都留到下次推进。请求在途时令牌由 RequestOptions 持有，不会被回收。
  final List<WeakReference<CancelToken>> _tracked = [];
  int _pruneThreshold = _minPruneThreshold;

  /// 当前会话代
  int get generation => _generation;

  /// 登记一个请求的令牌，下次 [advance] 时取消它
  void track(CancelToken token) {
    if (_tracked.length >= _pruneThreshold) {
      _tracked.removeWhere((ref) => ref.target == null);
      _pruneThreshold = _tracked.length * 2 < _minPruneThreshold
          ? _minPruneThreshold
          : _tracked.length * 2;
    }
    _tracked.add(WeakReference(token));
  }

  /// 推进到新的会话代，取消所有旧请求
  /// 返回新的 generation
  int advance() {
    _generation++;
    final reason = '[AuthSession] 会话代变更: $_generation';
    final tokens = _tracked.toList(growable: false);
    _tracked.clear();
    _pruneThreshold = _minPruneThreshold;
    for (final ref in tokens) {
      final token = ref.target;
      if (token != null && !token.isCancelled) token.cancel(reason);
    }
    debugPrint('[AuthSession] 推进到 generation=$_generation');
    return _generation;
  }

  /// 检查给定的 generation 是否仍然有效
  bool isValid(int gen) => gen == _generation;
}
