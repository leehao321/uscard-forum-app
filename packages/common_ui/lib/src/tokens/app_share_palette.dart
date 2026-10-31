import 'package:flutter/painting.dart';

/// 分享长图的预设底色。导出的是一张图片，不跟 App 的明暗主题走，
/// 用户在预览里自选，所以是固定色。
abstract final class AppSharePalette {
  static const classicBg = Color(0xFFF9F1E4);
  static const lightBg = Color(0xFFFFFFFF);
  static const lightCard = Color(0xFFF5F5F5);
  static const darkBg = Color(0xFF1E1E1E);
  static const darkCard = Color(0xFF2D2D2D);
  static const blackBg = Color(0xFF000000);
  static const blackCard = Color(0xFF1A1A1A);
  static const blueBg = Color(0xFFE8F4FC);
  static const greenBg = Color(0xFFE8F5E9);
}
