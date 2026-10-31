import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';

/// 模型 / 服务商头像（v2，设计说明 §5.3「AI 模型服务」）：
/// 34 方块（r8）、avatar/fill 底、首字母 17 Semibold text/meta。
///
/// 不再按品牌上色（旧版用 lobe-icons 品牌图 + 哈希色，11 色体系里没有）。
/// 取首字母时优先用模型名，没有就用服务商名。
class ModelIcon extends StatelessWidget {
  const ModelIcon({
    super.key,
    required this.providerName,
    required this.modelName,
    this.size = 34,
    this.withBackground = true,
  });

  final String providerName;
  final String modelName;
  final double size;
  final bool withBackground;

  static String _letter(String modelName, String providerName) {
    final source = modelName.trim().isNotEmpty ? modelName : providerName;
    final trimmed = source.trim();
    if (trimmed.isEmpty) return '?';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: withBackground ? colors.avatarFill : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          _letter(modelName, providerName),
          style: TextStyle(
            fontSize: size * 0.5,
            fontWeight: FontWeight.w600,
            height: 1,
            color: colors.textMeta,
          ),
        ),
      ),
    );
  }
}
