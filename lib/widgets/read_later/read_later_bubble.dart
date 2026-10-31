import 'package:flutter/material.dart';

import '../../l10n/s.dart';

import 'package:common_ui/common_ui.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/read_later_provider.dart';
import '../floating_widget_mixin.dart';
import 'read_later_overlay.dart';

/// 稍后阅读浮窗气泡
class ReadLaterBubble extends ConsumerStatefulWidget {
  const ReadLaterBubble({super.key});

  @override
  ConsumerState<ReadLaterBubble> createState() => _ReadLaterBubbleState();
}

class _ReadLaterBubbleState extends ConsumerState<ReadLaterBubble>
    with TickerProviderStateMixin, FloatingWidgetMixin {
  static const double _bubbleSize = 48.0;

  bool _isOverlayOpen = false;
  bool _isPressed = false;

  @override
  double get floatingOverlap => 16.0;

  @override
  double get floatingBottomMargin => 80.0;

  @override
  double get initialRelativeY => 0.7;

  @override
  void initState() {
    super.initState();
    initFloating();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    updateFloatingDependencies();
  }

  @override
  void dispose() {
    disposeFloating();
    super.dispose();
  }

  void _handleTap() async {
    setState(() => _isOverlayOpen = true);
    await ReadLaterOverlay.show();
    if (mounted) {
      setState(() => _isOverlayOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appReady = ref.watch(appReadyProvider);
    final items = ref.watch(readLaterProvider);

    // 应用未就绪或列表为空时彻底移除;打开浮层期间保留组件,
    // 用缩放动画隐藏/恢复,与浮层入退场衔接
    if (!appReady || items.isEmpty) return const SizedBox.shrink();

    final pos = floatingPosition();
    final visible = floatingIsInitialized && !_isOverlayOpen;

    return Positioned(
      left: pos.left,
      top: pos.top,
      right: pos.right,
      // 浮球挂在 MaterialApp.builder 的 Stack 上,没有 Material 祖先,
      // 文本会回落到 DefaultTextStyle 的下划线样式,这里补一层
      child: Material(
        type: MaterialType.transparency,
        child: IgnorePointer(
          ignoring: !visible,
          child: AnimatedScale(
            scale: visible ? (_isPressed ? 0.88 : 1.0) : 0.0,
            duration: Duration(milliseconds: _isPressed ? 90 : 220),
            curve: visible && !_isPressed
                ? Curves.easeOutBack
                : Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: visible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 180),
              child: GestureDetector(
                onPanStart: onFloatingPanStart,
                onPanUpdate: onFloatingPanUpdate,
                onPanEnd: onFloatingPanEnd,
                onTapDown: (_) => setState(() => _isPressed = true),
                onTapUp: (_) => setState(() => _isPressed = false),
                onTapCancel: () => setState(() => _isPressed = false),
                onTap: _handleTap,
                // v2：浮动胶囊材质的圆球，layers 20 + 条数 11，不用红色角标
                child: Semantics(
                  button: true,
                  label:
                      '${context.l10n.topicDetail_addToReadLater} ${items.length}',
                  excludeSemantics: true,
                  child: SizedBox(
                    width: _bubbleSize,
                    height: _bubbleSize,
                    child: CapsuleSurface(
                      shape: const CircleBorder(),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            AppIcons.readLater,
                            size: AppSize.iconM,
                            color: context.tokens.colors.textPrimary,
                          ),
                          Text(
                            '${items.length}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.merge(context.tokens.text.caption)
                                .copyWith(
                                  color: context.tokens.colors.textMeta,
                                  decoration: TextDecoration.none,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
