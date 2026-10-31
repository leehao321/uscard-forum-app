import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';

/// 把 PromptPreset.iconRaw 渲染成一个 Widget
///
/// iconRaw 可以是：
/// - emoji 字符（首 rune > 0xFF）：直接用 Text 渲染
/// - Material icon name（小写下划线）：查表
/// - 未知：fallback 到 AppIcons.autoAwesome
class PresetIcon extends StatelessWidget {
  const PresetIcon({
    super.key,
    required this.iconRaw,
    this.size = 18,
    this.color,
  });

  final String iconRaw;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (_looksLikeEmoji(iconRaw)) {
      // emoji 用 Text，字号略小一点保证视觉等高
      return Text(
        iconRaw,
        style: TextStyle(fontSize: size * 0.95, height: 1),
      );
    }
    final icon = _materialIconMap[iconRaw] ?? AppIcons.autoAwesome;
    return Icon(icon, size: size, color: color);
  }

  static bool _looksLikeEmoji(String s) {
    if (s.isEmpty) return false;
    final first = s.runes.first;
    // 排除 ASCII 字母、数字、下划线、冒号等
    if (first < 0x80) return false;
    return true;
  }
}

/// 暴露给 IconEmojiPicker 使用的 outlined icon 候选集
const List<String> kBuiltInIconNames = [
  'image_outlined',
  'brush_outlined',
  'draw_outlined',
  'palette_outlined',
  'auto_awesome_outlined',
  'lightbulb_outlined',
  'summarize_outlined',
  'translate_outlined',
  'question_answer_outlined',
  'smart_toy_outlined',
  'emoji_emotions_outlined',
  'camera_alt_outlined',
  'movie_outlined',
  'map_outlined',
  'favorite_outline',
  'star_outline',
  'share_outlined',
  'crop_din_outlined',
  'view_in_ar_outlined',
  'sticky_note_2_outlined',
  'grid_4x4',
];

/// Material icon name → IconData 映射
const Map<String, IconData> _materialIconMap = {
  'image_outlined': AppIcons.image,
  'brush_outlined': AppIcons.brush,
  'draw_outlined': AppIcons.brush,
  'palette_outlined': AppIcons.palette,
  'auto_awesome_outlined': AppIcons.autoAwesome,
  'lightbulb_outlined': AppIcons.lightbulb,
  'summarize_outlined': AppIcons.description,
  'translate_outlined': AppIcons.language,
  'question_answer_outlined': AppIcons.forum,
  'smart_toy_outlined': AppIcons.bot,
  'emoji_emotions_outlined': AppIcons.emoji,
  'camera_alt_outlined': AppIcons.camera,
  'movie_outlined': AppIcons.videoLibrary,
  'map_outlined': AppIcons.mapIcon,
  'favorite_outline': AppIcons.favorite,
  'star_outline': AppIcons.star,
  'share_outlined': AppIcons.share,
  'crop_din_outlined': AppIcons.checkBox,
  'view_in_ar_outlined': AppIcons.cube,
  'sticky_note_2_outlined': AppIcons.note,
  'grid_4x4': AppIcons.grid,
  // 兼容历史 chip 用的图标（防止预设 iconRaw 找不到时降级）
  'image': AppIcons.image,
  'brush': AppIcons.brush,
  'draw': AppIcons.brush,
};
