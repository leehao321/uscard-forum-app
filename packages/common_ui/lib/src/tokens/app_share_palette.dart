import 'package:flutter/painting.dart';

/// 分享长图里不属于 11 色体系的固定色。导出的是一张图片，不跟 App 的
/// 明暗主题走，用户在预览里自选，所以是固定色（浅、深同值）。
///
/// 其余四种样式直接取 [AppColors] 的 token：经典 = 浅色 surface/grouped，
/// 深色 = 深色 surface/grouped，纯黑 = 深色 surface/page，绿野 = brand/button
/// 底 + 白字（见设计说明 §6、Figma「补充 · 话题阅读」分享图片组）。
abstract final class AppSharePalette {
  /// share/蓝调：蓝调样式的卡片底色。取自真机截图采样（估计值），浅、深同值。
  static const blue = Color(0xFFE8F4FC);
}
