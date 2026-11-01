import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';

/// 把 PromptPreset.iconRaw 渲染成一个 Widget
///
/// iconRaw 可以是：
/// - Lucide 图标名（kebab-case，如 `sparkles`、`heart-handshake`）：新建快捷词选的就是这种
/// - 历史 Material 图标名（小写下划线，如 `auto_awesome_outlined`）：内置快捷词和旧数据，
///   按 [kLegacyPresetIconNames] 换成对应的 Lucide 图标
/// - emoji 字符（首 rune >= 0x80）：旧数据里可能有，仍然按文字渲染，新建时不再提供
/// - 未知：fallback 到 sparkles
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
    return Icon(presetIconData(iconRaw), size: size, color: color);
  }

  static bool _looksLikeEmoji(String s) {
    if (s.isEmpty) return false;
    final first = s.runes.first;
    // 排除 ASCII 字母、数字、下划线、冒号等
    if (first < 0x80) return false;
    return true;
  }
}

/// 新建快捷词图标网格里默认显示的 18 个 Lucide 图标（6 列 × 3 行）
const List<String> kPresetIconGrid = [
  'image',
  'brush',
  'pen-line',
  'palette',
  'sparkles',
  'lightbulb',
  'file-text',
  'languages',
  'messages-square',
  'bot',
  'smile',
  'camera',
  'clapperboard',
  'map',
  'heart',
  'star',
  'share-2',
  'square',
];

/// 新建快捷词的默认图标
const String kDefaultPresetIcon = 'sparkles';

/// 历史 Material 图标名 → Lucide 图标名
const Map<String, String> kLegacyPresetIconNames = {
  'image_outlined': 'image',
  'brush_outlined': 'brush',
  'draw_outlined': 'pen-line',
  'palette_outlined': 'palette',
  'auto_awesome_outlined': 'sparkles',
  'lightbulb_outlined': 'lightbulb',
  'summarize_outlined': 'file-text',
  'translate_outlined': 'languages',
  'question_answer_outlined': 'messages-square',
  'smart_toy_outlined': 'bot',
  'emoji_emotions_outlined': 'smile',
  'camera_alt_outlined': 'camera',
  'movie_outlined': 'clapperboard',
  'map_outlined': 'map',
  'favorite_outline': 'heart',
  'star_outline': 'star',
  'share_outlined': 'share-2',
  'crop_din_outlined': 'square',
  'view_in_ar_outlined': 'box',
  'sticky_note_2_outlined': 'sticky-note',
  'grid_4x4': 'grid-3x3',
  // 兼容历史 chip 用的图标
  'image': 'image',
  'brush': 'brush',
  'draw': 'pen-line',
};

/// iconRaw 对应的 Lucide 图标名：历史名换成新名，已经是 Lucide 名的原样返回；
/// 认不出来返回 null（emoji、未知名）。
String? presetLucideName(String iconRaw) {
  final name = kLegacyPresetIconNames[iconRaw] ?? iconRaw;
  return lucideIconByName(name) == null ? null : name;
}

/// iconRaw 对应的图标；认不出来用 sparkles
IconData presetIconData(String iconRaw) {
  final name = presetLucideName(iconRaw);
  return lucideIconByName(name ?? kDefaultPresetIcon) ?? AppIcons.autoAwesome;
}
