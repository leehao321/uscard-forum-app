/// 登录态检查的判定规则：什么算服务端明确说「这个会话没了」。
///
/// 只有明确的信号才能登出。Cloudflare 的 403、代理或门户返回的 200 网页、网络
/// 失败、请求被取消都说明不了会话的状态，把它们当成失效会把正常用户踢下线。
abstract final class AuthProbeRules {
  static bool _isNotLoggedInBody(Object? data) =>
      data is Map && data['error_type'] == 'not_logged_in';

  /// 登录态检查返回 200、但没拿到 current_user 时：只有 JSON 才算确认失效，
  /// 网页、空响应都不算。
  static bool isRejectedOk(Object? data) => data is Map;

  /// 登录态检查返回错误时：404 表示没有这个用户；401、403 必须带 not_logged_in。
  static bool isRejectedError(int? status, Object? data) {
    if (status == 404) return true;
    if (status == 401 || status == 403) return _isNotLoggedInBody(data);
    return false;
  }

  /// 会话探测结论不明确时，累积的 strike 够不够升级为登出。
  ///
  /// strike 只说明之前有过可疑信号，这一次也要有服务端的明确回答才能登出。
  static bool shouldEscalateInconclusive({
    required int strikes,
    required int? status,
    required Object? data,
  }) {
    if (strikes < 2) return false;
    return (status == 401 || status == 403) && _isNotLoggedInBody(data);
  }
}
