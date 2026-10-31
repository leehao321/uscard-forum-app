import 'package:flutter/material.dart';
import 'package:common_ui/common_ui.dart';

// 主 app 同名入口（lib/utils/dialog_utils.dart）的子包副本。0.4.0（v2）起
// 遮罩统一是 32% 纯色、不模糊；`blur` 参数只为兼容旧调用点保留，不再生效。

/// 替代 [showDialog]：v2 遮罩 + 淡入微缩入场。
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  bool blur = true,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final themes = InheritedTheme.capture(from: context, to: navigator.context);

  return navigator.push<T>(
    AppDialogRoute<T>(
      pageBuilder: (buildContext, animation, secondaryAnimation) {
        final Widget pageChild = Builder(builder: builder);
        return themes.wrap(SafeArea(child: pageChild));
      },
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor,
      barrierLabel:
          barrierLabel ??
          MaterialLocalizations.of(context).modalBarrierDismissLabel,
      settings: routeSettings,
    ),
  );
}

/// 替代 [showModalBottomSheet]：v2 遮罩（主题里的 32%），Android 预测返回
/// 跟手。外壳用 [AppSheetScaffold]。
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  String? barrierLabel,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  Color? barrierColor,
  bool isScrollControlled = false,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useSafeArea = false,
  RouteSettings? routeSettings,
  AnimationController? transitionAnimationController,
  Offset? anchorPoint,
  AnimationStyle? sheetAnimationStyle,
  bool blur = true,
}) {
  final NavigatorState navigator = Navigator.of(
    context,
    rootNavigator: useRootNavigator,
  );

  return navigator.push(
    AppBottomSheetRoute<T>(
      builder: builder,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      isScrollControlled: isScrollControlled,
      barrierLabel:
          barrierLabel ??
          MaterialLocalizations.of(context).modalBarrierDismissLabel,
      modalBarrierColor:
          barrierColor ?? Theme.of(context).bottomSheetTheme.modalBarrierColor,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      showDragHandle: showDragHandle,
      backgroundColor: backgroundColor,
      elevation: elevation,
      shape: shape,
      clipBehavior: clipBehavior,
      constraints: constraints,
      settings: routeSettings,
      transitionAnimationController: transitionAnimationController,
      anchorPoint: anchorPoint,
      useSafeArea: useSafeArea,
      sheetAnimationStyle: sheetAnimationStyle,
    ),
  );
}
