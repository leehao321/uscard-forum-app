import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 界面整体缩放（显示密度）。
///
/// 卡片内边距、头像、图标大多是写死的数字，只调字号或 VisualDensity 带不动它们，所以在
/// 最底层改 RenderView 用的设备像素比：比例 1.2 时，App 以为屏幕的逻辑尺寸小了 1.2 倍，
/// 所有东西画出来就大 1.2 倍。
///
/// 没有用 Transform 或 FittedBox 包一层：App 里有上百处用全局坐标定位弹层（长按菜单、
/// 选区工具栏、表情面板），包一层之后全局坐标和弹层坐标不再是同一个坐标系，弹层全会错位。
/// 这样改，坐标系还是一个。代价是三处要配套：
/// - 触摸点：系统按真实像素比换算，要再除一次（[scalePointer]）；
/// - MediaQuery：框架按真实像素比算，要改写（[AppUiScaleScope]）；
/// - 直接读 `FlutterView` 的代码要用 [logicalRatioOf]，不能直接除 `devicePixelRatio`。
class AppUiScale {
  AppUiScale._();

  static const prefKey = 'pref_ui_scale';

  /// 紧凑、标准、舒适、放大
  static const levels = [0.9, 1.0, 1.1, 1.2];

  static final ValueNotifier<double> factor = ValueNotifier(1.0);

  /// 读保存的比例。要在第一帧之前调用。
  static void load(SharedPreferences prefs) {
    factor.value = normalize(prefs.getDouble(prefKey));
  }

  /// 不认识的值（比如备份里来的）回到标准。
  static double normalize(double? value) =>
      levels.contains(value) ? value! : 1.0;

  static Future<void> set(SharedPreferences prefs, double value) async {
    final next = normalize(value);
    factor.value = next;
    await prefs.setDouble(prefKey, next);
    WidgetsBinding.instance.handleMetricsChanged();
  }

  /// 把 `FlutterView` 上的物理像素换成 App 里的逻辑像素时用的比例。
  static double logicalRatioOf(ui.FlutterView view) =>
      view.devicePixelRatio * factor.value;

  static ViewConfiguration configurationFor(ui.FlutterView view, double scale) {
    final ratio = view.devicePixelRatio * scale;
    final physical = BoxConstraints.fromViewConstraints(view.physicalConstraints);
    return ViewConfiguration(
      physicalConstraints: physical,
      logicalConstraints: physical / ratio,
      devicePixelRatio: ratio,
    );
  }

  static PointerEvent scalePointer(PointerEvent event, double scale) {
    if (scale == 1.0) return event;
    return event.copyWith(
      position: event.position / scale,
      delta: event.delta / scale,
    );
  }

  static MediaQueryData scaleMedia(MediaQueryData data, double scale) {
    if (scale == 1.0) return data;
    return data.copyWith(
      size: data.size / scale,
      devicePixelRatio: data.devicePixelRatio * scale,
      padding: data.padding / scale,
      viewPadding: data.viewPadding / scale,
      viewInsets: data.viewInsets / scale,
      systemGestureInsets: data.systemGestureInsets / scale,
    );
  }
}

/// 让 MediaQuery 和 RenderView 的尺寸对上。放在 MaterialApp.builder 的最外层。
class AppUiScaleScope extends StatelessWidget {
  const AppUiScaleScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final data = MediaQuery.of(context);
    return ValueListenableBuilder<double>(
      valueListenable: AppUiScale.factor,
      builder: (context, scale, child) => MediaQuery(
        data: AppUiScale.scaleMedia(data, scale),
        child: child!,
      ),
      child: child,
    );
  }
}
