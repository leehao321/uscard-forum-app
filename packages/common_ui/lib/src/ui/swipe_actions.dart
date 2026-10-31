import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../tokens/tokens.dart';
import 'app_pressable.dart';

/// 左滑露出的一个按钮
@immutable
class SwipeActionItem {
  const SwipeActionItem({
    required this.label,
    required this.onTap,
    this.icon,
    this.background,
    this.foreground,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  /// 默认 brand/button
  final Color? background;

  /// 默认白（onBrandButton）
  final Color? foreground;
}

/// 左滑操作（设计说明 §2.6）：行向左滑露出按钮（每个 72 宽），不支持
/// 一滑到底直接触发。同一时间只展开一行；展开时点行或右滑先收起。
///
/// 收起状态下只认向左的拖动，向右的拖动留给全屏侧滑返回（风险 R8）。
/// 每个按钮也注册成 VoiceOver 自定义操作，不用滑也能执行。
class SwipeActions extends StatefulWidget {
  const SwipeActions({
    super.key,
    required this.child,
    required this.actions,
    this.enabled = true,
  });

  final Widget child;
  final List<SwipeActionItem> actions;
  final bool enabled;

  @override
  State<SwipeActions> createState() => SwipeActionsState();
}

class SwipeActionsState extends State<SwipeActions>
    with SingleTickerProviderStateMixin {
  /// 当前展开的那一行
  static SwipeActionsState? _open;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  ScrollPosition? _scrollPosition;

  double get _extent => widget.actions.length * AppSize.swipeAction;

  bool get isOpen => _controller.value > 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _scrollPosition) {
      _scrollPosition?.isScrollingNotifier.removeListener(_onScroll);
      _scrollPosition = position;
      _scrollPosition?.isScrollingNotifier.addListener(_onScroll);
    }
  }

  void _onScroll() {
    if (_scrollPosition?.isScrollingNotifier.value == true) close();
  }

  @override
  void dispose() {
    _scrollPosition?.isScrollingNotifier.removeListener(_onScroll);
    if (identical(_open, this)) _open = null;
    _controller.dispose();
    super.dispose();
  }

  void open() {
    if (!identical(_open, this)) _open?.close();
    _open = this;
    _controller.animateTo(1, curve: Curves.easeOutCubic);
  }

  void close() {
    if (identical(_open, this)) _open = null;
    _controller.animateTo(0, curve: Curves.easeOutCubic);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (!identical(_open, this)) _open?.close();
    _controller.value -= (d.primaryDelta ?? 0) / _extent;
  }

  void _onDragEnd(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    if (velocity < -300 || (velocity <= 300 && _controller.value > 0.4)) {
      open();
    } else {
      close();
    }
  }

  void _run(SwipeActionItem action) {
    close();
    action.onTap();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.actions.isEmpty) return widget.child;
    final tokens = context.tokens;
    final base = Theme.of(context).textTheme.bodySmall!.merge(tokens.text.meta);

    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final action in widget.actions)
          SizedBox(
            width: AppSize.swipeAction,
            child: ColoredBox(
              color: action.background ?? tokens.colors.brandButton,
              child: AppPressable(
                onTap: () => _run(action),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (action.icon != null) ...[
                      Icon(
                        action.icon,
                        size: AppSize.iconM,
                        color: action.foreground ?? tokens.colors.onBrandButton,
                      ),
                      const SizedBox(height: AppSpace.xs),
                    ],
                    Text(
                      action.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: base.copyWith(
                        color: action.foreground ?? tokens.colors.onBrandButton,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );

    final content = AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.translate(
        offset: Offset(-_extent * _controller.value, 0),
        child: child,
      ),
      child: widget.child,
    );

    // 整行一个朗读节点，左滑按钮挂在它的自定义操作上（VoiceOver 转子可选）
    return Semantics(
      container: true,
      customSemanticsActions: {
        for (final action in widget.actions)
          CustomSemanticsAction(label: action.label): action.onTap,
      },
      child: RawGestureDetector(
        gestures: {
          _LeftFirstDragRecognizer:
              GestureRecognizerFactoryWithHandlers<_LeftFirstDragRecognizer>(
                () => _LeftFirstDragRecognizer(isOpen: () => isOpen),
                (r) => r
                  ..onUpdate = _onDragUpdate
                  ..onEnd = _onDragEnd,
              ),
        },
        child: ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ExcludeSemantics(
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) => _controller.value == 0
                          ? const SizedBox.shrink()
                          : child!,
                      child: buttons,
                    ),
                  ),
                ),
              ),
              // 展开时点行先收起，不触发行本身的点按
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) => _controller.value > 0
                    ? Stack(
                        children: [
                          child!,
                          Positioned.fill(
                            right: _extent * _controller.value,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: close,
                              excludeFromSemantics: true,
                            ),
                          ),
                        ],
                      )
                    : child!,
                child: content,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 收起时只接受向左开始的横向拖动
class _LeftFirstDragRecognizer extends HorizontalDragGestureRecognizer {
  _LeftFirstDragRecognizer({required this.isOpen});

  final bool Function() isOpen;
  double _dx = 0;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _dx = 0;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) _dx += event.delta.dx;
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) =>
      (isOpen() || _dx < 0) &&
      super.hasSufficientGlobalDistanceToAccept(
        pointerDeviceKind,
        deviceTouchSlop,
      );
}
