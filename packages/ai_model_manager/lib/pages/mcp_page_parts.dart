import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';

/// MCP 设置页共用的小部件和颜色。

/// 风险 / 明文警示用的警告色。主题色里没有「警告」这一档（只有报错红），
/// 这里按明暗各取一个橙色：和报错红区分开，对比度够用。
Color mcpWarningColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFFFB454)
    : const Color(0xFFB45309);

/// 分组卡片：一组行放进一个圆角卡片，行之间细分隔线。服务列表和工具列表共用。
class McpGroupCard extends StatelessWidget {
  const McpGroupCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// 小徽标：主色淡底 + 主色字（「只读」）
class McpBadge extends StatelessWidget {
  const McpBadge(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
        ),
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
    final color = mcpWarningColor(context);
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(Symbols.warning_rounded, size: 16, color: color),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
    if (!compact) return row;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: row,
    );
  }
}
