import 'dart:async';

import 'package:app_icons/app_icons.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';

import '../tokens/tokens.dart';

/// 等待提示（设计说明 §4）：44 高居中，系统菊花 16 +「正在等待论坛响应」
/// 13 meta。放在原内容顶部，骨架保留；出现时 VoiceOver 播报。
class WaitingHint extends StatelessWidget {
  const WaitingHint({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: SizedBox(
          height: AppSize.hit,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CupertinoActivityIndicator(radius: AppSize.iconS / 2),
              const SizedBox(width: AppSpace.s),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall!
                      .merge(tokens.text.meta)
                      .copyWith(color: tokens.colors.textMeta),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 加载阶段（设计说明 §1-6）：200ms 内什么都不显示，之后出骨架，
/// 超过 3 秒在骨架上方加等待提示。
enum LoadingPhase { quiet, skeleton, waiting }

/// 按时间推进 [LoadingPhase]。只在加载中挂它，加载完换成内容即可。
class DelayedLoading extends StatefulWidget {
  const DelayedLoading({
    super.key,
    required Widget this.skeleton,
    required String this.waitingLabel,
    this.skeletonDelay = const Duration(milliseconds: 200),
    this.waitingDelay = const Duration(seconds: 3),
  }) : builder = null;

  /// 自定义三个阶段的样子（sliver 列表等）
  const DelayedLoading.builder({
    super.key,
    required Widget Function(BuildContext context, LoadingPhase phase)
    this.builder,
    this.skeletonDelay = const Duration(milliseconds: 200),
    this.waitingDelay = const Duration(seconds: 3),
  }) : skeleton = null,
       waitingLabel = null;

  final Widget? skeleton;
  final String? waitingLabel;
  final Widget Function(BuildContext context, LoadingPhase phase)? builder;
  final Duration skeletonDelay;
  final Duration waitingDelay;

  @override
  State<DelayedLoading> createState() => _DelayedLoadingState();
}

class _DelayedLoadingState extends State<DelayedLoading> {
  LoadingPhase _phase = LoadingPhase.quiet;
  final _timers = <Timer>[];

  @override
  void initState() {
    super.initState();
    _timers
      ..add(Timer(widget.skeletonDelay, () => _advance(LoadingPhase.skeleton)))
      ..add(Timer(widget.waitingDelay, () => _advance(LoadingPhase.waiting)));
  }

  void _advance(LoadingPhase phase) {
    if (!mounted || phase.index <= _phase.index) return;
    setState(() => _phase = phase);
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final builder = widget.builder;
    if (builder != null) return builder(context, _phase);
    return switch (_phase) {
      LoadingPhase.quiet => const SizedBox.shrink(),
      LoadingPhase.skeleton => widget.skeleton!,
      LoadingPhase.waiting => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WaitingHint(label: widget.waitingLabel!),
          Flexible(child: widget.skeleton!),
        ],
      ),
    };
  }
}

/// 空 / 错状态（设计说明 §4）：居中列、间距 8、左右 40：48 圆
/// （surface/grouped）里 24 的 meta 图标 → 标题 17 Regular → 说明 13 meta
/// → 可选按钮（错误态固定是 44 高的次按钮「重试」）。
///
/// 错误是原地显示的，出现时 VoiceOver 播报标题。
class AppStateView extends StatelessWidget {
  const AppStateView({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.action,
    this.announce = false,
  });

  final String title;
  final String? message;
  final IconData? icon;

  /// 一般是 FilledButton（次按钮样式）
  final Widget? action;

  /// 错误态：出现时播报
  final bool announce;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.surfaceGrouped,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon ?? AppIcons.info,
              size: AppSize.iconL,
              color: colors.textMeta,
            ),
          ),
        ),
        const SizedBox(height: AppSpace.s),
        Semantics(
          liveRegion: announce,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: base
                .merge(tokens.text.control)
                .copyWith(color: colors.textPrimary),
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: AppSpace.s),
          Text(
            message!,
            textAlign: TextAlign.center,
            style: base
                .merge(tokens.text.meta)
                .copyWith(color: colors.textMeta),
          ),
        ],
        if (action != null) ...[const SizedBox(height: AppSpace.s), action!],
      ],
    );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.x40,
          vertical: AppSpace.xxl,
        ),
        child: column,
      ),
    );
  }
}
