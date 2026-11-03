import 'package:dio/dio.dart';

import '../../auth_session.dart';

/// 会话代守卫拦截器
/// - onRequest: 将当前 generation 戳入请求 extra + 给请求一个自己的 CancelToken
/// - onResponse: 检查 generation 是否仍有效，过期则丢弃
/// - onError: 同上
class SessionGuardInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final session = AuthSession();
    options.extra['_sessionGeneration'] = session.generation;

    // 每个请求一个令牌，不共用：
    // - 取消错误要带这个请求的 options，调度器才能释放它占的槽位；
    // - dio 会在令牌上挂监听，共用的长寿命令牌会把每个响应都留到下次推进。
    final token = _RequestCancelToken(options.cancelToken);
    token.requestOptions = options;
    options.cancelToken = token;
    session.track(token);

    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final gen = response.requestOptions.extra['_sessionGeneration'] as int?;
    if (gen != null && !AuthSession().isValid(gen)) {
      // 丢弃过期会话的响应
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          type: DioExceptionType.cancel,
          error: '会话已过期 (gen=$gen, current=${AuthSession().generation})',
        ),
        true,
      );
      return;
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // 过期会话的错误转为 cancel 类型，但仍需通过 next 传播，
    // 确保后续拦截器（如 RequestSchedulerInterceptor）能正常释放资源
    final gen = err.requestOptions.extra['_sessionGeneration'] as int?;
    if (gen != null && !AuthSession().isValid(gen)) {
      handler.next(
        DioException(
          requestOptions: err.requestOptions,
          type: DioExceptionType.cancel,
          error: '会话已过期 (gen=$gen)',
        ),
      );
      return;
    }
    handler.next(err);
  }
}

/// 一个请求自己的令牌：调用方的令牌取消时跟着取消。
///
/// 监听里只抓弱引用：调用方可能长期持有同一个令牌，不能因此留住每个请求的响应。
class _RequestCancelToken extends CancelToken {
  _RequestCancelToken(CancelToken? caller) {
    if (caller == null) return;
    final self = WeakReference<CancelToken>(this);
    caller.whenCancel.then((_) {
      final token = self.target;
      if (token != null && !token.isCancelled) {
        token.cancel(caller.cancelError?.error?.toString());
      }
    });
  }
}
