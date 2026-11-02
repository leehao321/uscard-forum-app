import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import '../../services/network/exceptions/api_exception.dart';
import '../../widgets/common/error_view.dart';

/// 话题打不开时的替代内容（扩展点）。
///
/// 话题详情页遇到「话题已不可见或暂时受限」的最终结果（404 / 410 / 429 / 403）时，
/// 会把原来的错误页和话题 id、状态码交给这里注册的 [TopicUnavailableFallback.builder]，
/// 由它决定画什么：想显示替代内容就返回自己的组件（拿不到内容时应继续显示传进来的
/// [TopicUnavailableInfo.errorView]）；没有注册时仍然是原来的错误页。
///
/// 替代内容自己不应该再向论坛发请求。
@immutable
class TopicUnavailableInfo {
  const TopicUnavailableInfo({
    required this.topicId,
    required this.statusCode,
    required this.errorView,
  });

  final int topicId;

  /// 论坛最终返回的状态码：404 / 410 / 429 / 403
  final int statusCode;

  /// 原来的错误页（带重试），拿不到替代内容时继续显示它
  final Widget errorView;
}

typedef TopicUnavailableBuilder =
    Widget Function(BuildContext context, TopicUnavailableInfo info);

abstract final class TopicUnavailableFallback {
  /// 注册的替代内容构建函数；null 表示没有替代内容
  static TopicUnavailableBuilder? builder;
}

/// 话题加载失败的最终状态码里，属于「话题不可用」的那几个；其它情况返回 null。
///
/// 只认论坛真正返回的 404 / 410 / 429 / 403：
/// - Cloudflare 验证（含被它包成 403 的响应）不算，走原来的验证流程；
/// - 网络错误、超时、5xx 不算。
int? topicUnavailableStatusOf(Object error) {
  if (error is CfChallengeException) return null;
  if (error is RateLimitException) return 429;
  if (error is DioException) {
    final inner = error.error;
    if (inner is CfChallengeException) return null;
    if (inner is RateLimitException) return 429;
    if (inner is ServerException) return null;
    final code = error.response?.statusCode;
    if (code == 404 || code == 410 || code == 429 || code == 403) return code;
  }
  return null;
}

/// 话题详情页加载失败时的内容：普通错误页；遇到「话题不可用」且注册了替代内容时，
/// 交给 [TopicUnavailableFallback.builder]。
class TopicLoadErrorContent extends StatelessWidget {
  const TopicLoadErrorContent({
    super.key,
    required this.topicId,
    required this.error,
    this.onRetry,
  });

  final int topicId;
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final errorView = CustomScrollView(
      slivers: [SliverErrorView(error: error, onRetry: onRetry)],
    );
    final build = TopicUnavailableFallback.builder;
    final status = topicUnavailableStatusOf(error);
    if (build == null || status == null) return errorView;
    return build(
      context,
      TopicUnavailableInfo(
        topicId: topicId,
        statusCode: status,
        errorView: errorView,
      ),
    );
  }
}
