import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/shortcut_provider.dart';
import '../services/dynamic_content_suspension_service.dart';

import 'package:common_ui/common_ui.dart';

// 0.4.0（v2）：对话框和半屏的遮罩统一是 32% 纯色、不模糊（设计说明 §2.2，
// 计划 P11）。各入口的 `blur` 参数只为兼容旧调用点保留，不再生效。

Future<T?> _pushShortcutManagedRoute<T>({
  required BuildContext context,
  required NavigatorState navigator,
  required Route<T> route,
  ShortcutSurfaceConfig? shortcutSurface,
}) {
  if (shortcutSurface == null) {
    return navigator.push(route);
  }

  final container = ProviderScope.containerOf(context, listen: false);
  final registry = container.read(shortcutSurfaceRegistryProvider.notifier);
  final owner = Object();

  registry.register(
    owner: owner,
    id: shortcutSurface.id,
    triggerAction: shortcutSurface.triggerAction,
    repeatActions: shortcutSurface.repeatActions,
    kind: shortcutSurface.kind,
    repeatBehavior: shortcutSurface.repeatBehavior,
    blocksShortcuts: shortcutSurface.blocksShortcuts,
    passthroughActions: shortcutSurface.passthroughActions,
    route: route,
    onClose: () {
      final routeNavigator = route.navigator;
      if (routeNavigator != null && (route.isCurrent || route.isActive)) {
        routeNavigator.pop();
      }
    },
    onFocus: () {
      final routeNavigator = route.navigator;
      if (routeNavigator == null || route.isCurrent) return;
      routeNavigator.popUntil((candidate) => identical(candidate, route));
    },
  );

  return navigator.push(route).whenComplete(() {
    registry.unregister(owner: owner);
  });
}

Future<T?> _pushOverlayRoute<T>({
  required BuildContext context,
  required NavigatorState navigator,
  required Route<T> route,
  required bool suspendDynamicContent,
  ShortcutSurfaceConfig? shortcutSurface,
}) {
  final lease = suspendDynamicContent
      ? DynamicContentSuspensionService.instance.acquire(
          reason: 'modal-overlay',
        )
      : null;
  return _pushShortcutManagedRoute(
    context: context,
    navigator: navigator,
    route: route,
    shortcutSurface: shortcutSurface,
  ).whenComplete(() => lease?.release());
}

Future<T?> pushAppRoute<T>({
  required BuildContext context,
  required Route<T> route,
  bool useRootNavigator = true,
  ShortcutSurfaceConfig? shortcutSurface,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  return _pushShortcutManagedRoute(
    context: context,
    navigator: navigator,
    route: route,
    shortcutSurface: shortcutSurface,
  );
}

/// 替代 [showDialog]：v2 遮罩（32%，不模糊）+ 淡入微缩入场。
///
/// [blur] 已不生效（见文件头）。
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  bool blur = true,
  Duration transitionDuration = const Duration(milliseconds: 200),
  ShortcutSurfaceConfig? shortcutSurface,
  bool suspendDynamicContent = true,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);

  final themes = InheritedTheme.capture(from: context, to: navigator.context);

  final route = AppDialogRoute<T>(
    pageBuilder: (buildContext, animation, secondaryAnimation) {
      final Widget pageChild = Builder(builder: builder);
      return themes.wrap(SafeArea(child: pageChild));
    },
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    barrierLabel:
        barrierLabel ??
        MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: transitionDuration,
    settings: routeSettings,
  );

  return _pushOverlayRoute(
    context: context,
    navigator: navigator,
    route: route,
    suspendDynamicContent: suspendDynamicContent,
    shortcutSurface: shortcutSurface,
  );
}

/// 替代 [showGeneralDialog]：遮罩默认 32%，转场由调用方决定（默认淡入）。
Future<T?> showAppGeneralDialog<T extends Object?>({
  required BuildContext context,
  required RoutePageBuilder pageBuilder,
  bool barrierDismissible = false,
  String? barrierLabel,
  Color? barrierColor,
  Duration transitionDuration = const Duration(milliseconds: 200),
  Duration? reverseTransitionDuration,
  RouteTransitionsBuilder? transitionBuilder,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  bool blur = true,
  ShortcutSurfaceConfig? shortcutSurface,
  bool suspendDynamicContent = true,
  VoidCallback? onDisposed,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final route = AppDialogRoute<T>(
    pageBuilder: pageBuilder,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel,
    barrierColor: barrierColor,
    transitionDuration: transitionDuration,
    reverseTransitionDuration: reverseTransitionDuration,
    transitionBuilder: transitionBuilder ?? _fadeTransition,
    settings: routeSettings,
    onDisposed: onDisposed,
  );

  return _pushOverlayRoute(
    context: context,
    navigator: navigator,
    route: route,
    suspendDynamicContent: suspendDynamicContent,
    shortcutSurface: shortcutSurface,
  );
}

Widget _fadeTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) => FadeTransition(
  opacity: CurvedAnimation(parent: animation, curve: Curves.linear),
  child: child,
);

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
  ShortcutSurfaceConfig? shortcutSurface,
  bool suspendDynamicContent = true,
}) {
  final NavigatorState navigator = Navigator.of(
    context,
    rootNavigator: useRootNavigator,
  );

  final route = AppBottomSheetRoute<T>(
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
  );

  return _pushOverlayRoute(
    context: context,
    navigator: navigator,
    route: route,
    suspendDynamicContent: suspendDynamicContent,
    shortcutSurface: shortcutSurface,
  );
}
