import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';

import '../../l10n/s.dart';
import '../../services/app_logger.dart';
import '../../services/cf_challenge_service.dart';
import '../../services/network/exceptions/api_exception.dart';
import '../../services/toast_service.dart';
import '../../utils/error_utils.dart';

/// 原地错误（v2，设计说明 §1-6、§4「空 / 错状态」）。
///
/// 居中列：48 圆底图标 → 标题 17 → 说明 13 meta → 次按钮「重试」。
/// Cloudflare 验证类错误的主操作是「手动验证」。HTTP 状态码、堆栈这类
/// 技术细节不在这里出现：第一次显示某个错误时写进应用日志（关于 ›
/// 应用日志，M8 起是「高级 › 诊断」）。
class ErrorView extends StatefulWidget {
  const ErrorView({
    super.key,
    required this.error,
    this.stackTrace,
    this.onRetry,
    this.icon,
    this.iconSize = 48,
    this.title,
    this.retryLabel,
    this.showDetails = true,
  });

  /// 错误对象
  final Object error;

  /// 堆栈跟踪（可选）
  final StackTrace? stackTrace;

  /// 重试回调
  final VoidCallback? onRetry;

  /// 自定义图标
  final IconData? icon;

  /// 旧参数，v2 固定 48 圆底 + 24 图标，不再生效
  final double iconSize;

  /// 自定义标题（默认为"加载失败"）
  final String? title;

  /// 自定义重试按钮文案（默认为"重试"）
  final String? retryLabel;

  /// 是否把错误详情写进应用日志（「查看详情」移到诊断，计划 §4）
  final bool showDetails;

  @override
  State<ErrorView> createState() => _ErrorViewState();
}

class _ErrorViewState extends State<ErrorView> {
  @override
  void initState() {
    super.initState();
    _logDetails();
  }

  @override
  void didUpdateWidget(ErrorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.error, widget.error)) _logDetails();
  }

  void _logDetails() {
    if (!widget.showDetails) return;
    AppLogger.warning(
      ErrorUtils.getErrorDetails(widget.error, widget.stackTrace),
      tag: 'ErrorView',
    );
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.error;
    final errorInfo = ErrorUtils.getErrorInfo(error);

    Widget? action;
    if (_isCfChallengeError(error)) {
      action = FilledButton(
        onPressed: () => _runManualCfVerify(context),
        child: Text(context.l10n.cf_manualVerifyAction),
      );
    } else if (widget.onRetry != null) {
      action = FilledButton(
        style: AppButtonStyles.secondary(context),
        onPressed: widget.onRetry,
        child: Text(widget.retryLabel ?? context.l10n.common_retry),
      );
    }

    return AppStateView(
      icon: widget.icon ?? errorInfo.icon,
      title: widget.title ?? errorInfo.title,
      message: errorInfo.message,
      action: action,
      announce: true,
    );
  }

  bool _isCfChallengeError(Object error) {
    if (error is CfChallengeException) return true;
    if (error is DioException && error.error is CfChallengeException) {
      return true;
    }
    return false;
  }

  Future<void> _runManualCfVerify(BuildContext context) async {
    final result = await CfChallengeService().showManualVerifyNow(
      context,
      true,
    );
    if (!context.mounted) return;

    if (result == true) {
      ToastService.showSuccess(S.current.cfVerify_success);
      widget.onRetry?.call();
      return;
    }

    if (result == false) {
      ToastService.showError(S.current.cf_verifyIncomplete);
      return;
    }

    ToastService.showError(S.current.cf_cannotOpenVerifyPage);
  }
}

/// 错误详情半屏（诊断等开发向入口用）：等宽字，可复制。
class ErrorDetailsSheet extends StatelessWidget {
  const ErrorDetailsSheet({super.key, required this.details});

  final String details;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return AppSheetScaffold(
      title: context.l10n.common_errorDetails,
      contentPadding: EdgeInsets.zero,
      actions: [
        AppIconButton(
          icon: AppIcons.copy,
          size: AppSize.iconM,
          semanticLabel: context.l10n.common_copy,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: details));
            ToastService.showSuccess(S.current.common_copiedToClipboard);
          },
        ),
      ],
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.pageMargin),
        child: SelectableText(
          details,
          style: Theme.of(context).textTheme.bodySmall!
              .merge(tokens.text.mono)
              .copyWith(color: tokens.colors.textPrimary),
        ),
      ),
    );
  }
}

/// Sliver 版本的错误视图（用于 CustomScrollView）
class SliverErrorView extends StatelessWidget {
  const SliverErrorView({
    super.key,
    required this.error,
    this.stackTrace,
    this.onRetry,
    this.icon,
    this.iconSize = 48,
    this.title,
    this.retryLabel,
    this.showDetails = true,
  });

  final Object error;
  final StackTrace? stackTrace;
  final VoidCallback? onRetry;
  final IconData? icon;
  final double iconSize;
  final String? title;
  final String? retryLabel;
  final bool showDetails;

  @override
  Widget build(BuildContext context) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: ErrorView(
        error: error,
        stackTrace: stackTrace,
        onRetry: onRetry,
        icon: icon,
        iconSize: iconSize,
        title: title,
        retryLabel: retryLabel,
        showDetails: showDetails,
      ),
    );
  }
}

/// 行内错误：卡片内 / 列表项内的局部错误，不占满整屏。
///
/// v2：surface/grouped 底、r12；图标 16 meta + 13 字 + 可选文字按钮
/// 「重试」（brand）。和 [ErrorView] 共用同一套错误文案。
class InlineErrorView extends StatelessWidget {
  const InlineErrorView({
    super.key,
    required this.error,
    this.onRetry,
    this.message,
    this.compact = false,
  });

  /// 错误对象
  final Object error;

  /// 重试回调
  final VoidCallback? onRetry;

  /// 自定义错误文案。null 时取 ErrorUtils.getErrorInfo(error).title。
  final String? message;

  /// 紧凑模式：内边距更小，适合放在小卡片里。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final errorInfo = ErrorUtils.getErrorInfo(error);
    final base = Theme.of(context).textTheme.bodySmall!.merge(tokens.text.meta);

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpace.m,
          vertical: compact ? AppSpace.xs : AppSpace.s,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceGrouped,
          borderRadius: BorderRadius.circular(tokens.radius.card),
        ),
        child: Row(
          children: [
            Icon(errorInfo.icon, size: AppSize.iconS, color: colors.textMeta),
            const SizedBox(width: AppSpace.s),
            Expanded(
              child: Text(
                message ?? errorInfo.title,
                style: base.copyWith(color: colors.textPrimary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(width: AppSpace.s),
              AppPressable(
                onTap: onRetry,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: AppSize.hit,
                    minHeight: AppSize.hit,
                  ),
                  child: Center(
                    child: Text(
                      context.l10n.common_retry,
                      style: base.copyWith(color: colors.brandPrimary),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
