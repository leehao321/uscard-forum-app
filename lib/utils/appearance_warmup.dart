import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 外观设置页首帧开销的预热。
///
/// **MiSans 懒加载** — 引擎读 `FontManifest.json` 时只登记 family → asset
/// 映射（`AssetManagerFontProvider::RegisterAsset`），真正读取并解析 asset
/// 字体发生在首次匹配该 family 时。字体分组里那行 `TextStyle(fontFamily:
/// 'MiSans')` 是用户未选 MiSans 时全 App 唯一的 MiSans 用点，于是 19MB
/// 可变字体的读取与 typeface 创建全落在这一帧，实测约 35ms。
///
/// 预热挂在进入设置页时：此时界面静止，且用户还要再点一次才进外观页，
/// 用 idle 优先级排队，不与转场动画抢帧。（0.4.0 去掉调色板后，种子
/// 配色的预计算也一起去掉了。）
class AppearanceWarmup {
  AppearanceWarmup._();

  static bool _scheduled = false;

  static void schedule() {
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.scheduleTask(
      _warmUpMiSansTypeface,
      Priority.idle,
    );
  }

  /// 排版一次 MiSans 文本，触发字体 asset 的读取与 typeface 创建。
  static void _warmUpMiSansTypeface() {
    TextPainter(
        text: const TextSpan(
          text: 'MiSans',
          style: TextStyle(fontFamily: 'MiSans'),
        ),
        textDirection: TextDirection.ltr,
      )
      ..layout()
      ..dispose();
  }
}
