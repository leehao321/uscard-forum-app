import 'package:dio/dio.dart';

import 'flux_request_spec.dart';

/// 一次「安静」的只读请求：调用方自己管次数和限流，不要网络层替它做任何事。
///
/// - 不弹错误提示（[FluxRequestKeys.isSilent]）；
/// - 不自动恢复：遇到 429 / 5xx 不等待、不重放，原样把错误抛回来（[FluxRequestKeys.noRecovery]）；
/// - 不弹人工验证页（[FluxRequestKeys.skipCfChallenge]）；
/// - 可取消：[cancelToken] 触发后底层请求立即断开；
/// - [skipTrackVisit] 给读取用户资料的请求用，不给对方记一次资料页浏览。
class QuietRequest {
  const QuietRequest({this.cancelToken, this.skipTrackVisit = false});

  final CancelToken? cancelToken;
  final bool skipTrackVisit;

  /// 在 [base] 的基础上加上「安静」语义
  Options options([Options? base]) {
    final b = base ?? Options();
    return b.copyWith(
      extra: {
        ...?b.extra,
        FluxRequestKeys.isSilent: true,
        FluxRequestKeys.noRecovery: true,
        FluxRequestKeys.skipCfChallenge: true,
      },
    );
  }
}
