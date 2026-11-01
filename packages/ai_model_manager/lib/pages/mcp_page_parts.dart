import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';

/// MCP 设置页共用的小部件和颜色。

/// 风险 / 明文警示用的警告色。设计 token 里没有「警告」这一档（只有破坏性操作的红色），
/// 这里按明暗各取一个橙色：和报错红区分开，对比度够用。
Color mcpWarningColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? const Color(0xFFFFB454) : const Color(0xFFB45309);

/// 图标随系统字号放大（封顶，免得撑爆行）
double mcpIconSize(BuildContext context, [double base = AppSize.iconS]) =>
    MediaQuery.textScalerOf(context).scale(base).clamp(base, base * 1.8);

/// 分组卡片：一组行放进一个圆角卡片，行之间细分隔线。服务列表和工具列表共用。
class McpGroupCard extends StatelessWidget {
  const McpGroupCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.colors.surfaceElevated,
        borderRadius: BorderRadius.circular(tokens.radius.card),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tokens.radius.card),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Padding(padding: EdgeInsets.only(left: AppSpace.m), child: AppHairline()),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// 小徽标：brand 淡底 + brand 字（「只读」）
class McpBadge extends StatelessWidget {
  const McpBadge(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs + 2, vertical: 1),
      decoration: BoxDecoration(
        color: colors.brandPrimary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(tokens.radius.tag),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall!.merge(tokens.text.metaStrong).copyWith(color: colors.brandPrimary),
      ),
    );
  }
}

/// 警示标签：图标 + 文字，警告色（不用报错红）
class McpWarning extends StatelessWidget {
  const McpWarning(this.text, {super.key, this.compact = false});

  final String text;

  /// 紧凑：用在列表行里的单独标签（带淡底）
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = mcpWarningColor(context);
    final style = Theme.of(context).textTheme.bodySmall!.merge(tokens.text.meta).copyWith(color: color);
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(AppIcons.warning, size: mcpIconSize(context), color: color),
        ),
        const SizedBox(width: AppSpace.xs),
        Flexible(child: Text(text, style: style)),
      ],
    );
    if (!compact) return row;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(tokens.radius.tag),
      ),
      child: row,
    );
  }
}
