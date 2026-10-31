import 'package:flutter/material.dart';

import '../predictive_back_cupertino_transitions.dart';
import '../tokens/tokens.dart';

/// 对话框入场：淡入，同时从 1.04 缩到 1（iOS 提醒框的观感）；退场只淡出。
/// 系统「减弱动态效果」时只淡入淡出。
Widget appDialogTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
  if (MediaQuery.disableAnimationsOf(context) ||
      animation.status == AnimationStatus.reverse) {
    return FadeTransition(opacity: fade, child: child);
  }
  return FadeTransition(
    opacity: fade,
    child: ScaleTransition(
      scale: Tween<double>(
        begin: 1.04,
        end: 1,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

/// v2 对话框路由：遮罩 32% 纯色、不模糊（设计说明 §2.2）。主 app 和
/// ai_model_manager 的 showAppDialog 都用它。
class AppDialogRoute<T> extends PopupRoute<T> {
  AppDialogRoute({
    required this.pageBuilder,
    bool barrierDismissible = true,
    String? barrierLabel,
    Color? barrierColor,
    Duration transitionDuration = const Duration(milliseconds: 200),
    Duration? reverseTransitionDuration,
    RouteTransitionsBuilder? transitionBuilder,
    super.settings,
    this.onDisposed,
  }) : _barrierDismissible = barrierDismissible,
       _barrierLabel = barrierLabel,
       _barrierColor = barrierColor ?? AppMaterials.scrim,
       _transitionDuration = transitionDuration,
       _reverseTransitionDuration = reverseTransitionDuration,
       _transitionBuilder = transitionBuilder ?? appDialogTransition;

  final RoutePageBuilder pageBuilder;
  final bool _barrierDismissible;
  final String? _barrierLabel;
  final Color _barrierColor;
  final Duration _transitionDuration;
  final Duration? _reverseTransitionDuration;
  final RouteTransitionsBuilder _transitionBuilder;
  final VoidCallback? onDisposed;

  @override
  bool get barrierDismissible => _barrierDismissible;

  @override
  String? get barrierLabel => _barrierLabel;

  @override
  Color get barrierColor => _barrierColor;

  @override
  Duration get transitionDuration => _transitionDuration;

  @override
  Duration get reverseTransitionDuration =>
      _reverseTransitionDuration ?? _transitionDuration;

  @override
  void dispose() {
    onDisposed?.call();
    super.dispose();
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => pageBuilder(context, animation, secondaryAnimation);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _transitionBuilder(context, animation, secondaryAnimation, child);
}

/// v2 半屏路由：遮罩 32%（主题 bottomSheetTheme.modalBarrierColor），
/// 宽度上限 640 居中（Material 默认）；Android 预测返回手势跟手下滑。
class AppBottomSheetRoute<T> extends ModalBottomSheetRoute<T> {
  AppBottomSheetRoute({
    required super.builder,
    super.capturedThemes,
    super.barrierLabel,
    super.backgroundColor,
    super.elevation,
    super.shape,
    super.clipBehavior,
    super.constraints,
    super.modalBarrierColor,
    super.isDismissible,
    super.enableDrag,
    super.showDragHandle,
    required super.isScrollControlled,
    super.settings,
    super.transitionAnimationController,
    super.anchorPoint,
    super.useSafeArea,
    super.sheetAnimationStyle,
  });

  /// 慢划边缘时 sheet 跟手下滑，与手指下拉关闭是同一套动画：sheet 位移
  /// 本就绑 route.animation，手势进度喂进去即跟手。只认领手势、不包视觉
  /// widget，见 [wrapPredictiveBackForModalRoute]。
  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return wrapPredictiveBackForModalRoute(
      route: this,
      child: super.buildTransitions(
        context,
        animation,
        secondaryAnimation,
        child,
      ),
    );
  }
}
