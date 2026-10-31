import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';

/// 用户主页的统计行（设计说明 §5.2「用户主页」）。
///
/// 上面一行「关注 N · 粉丝 N」，可点进关注 / 粉丝列表；下面是四列统计卡
/// （获赞 · 访问 · 话题 · 回复）：surface/grouped、r12，数字 17 Semibold、
/// 标签 13 meta，列间无分隔。
class ProfileStatsRow extends StatelessWidget {
  const ProfileStatsRow({
    super.key,
    required this.stats,
    this.following,
    this.followers,
    this.onFollowingTap,
    this.onFollowersTap,
  });

  /// 四列统计（数字文字、标签、原始值，用于读屏和长按提示）
  final List<ProfileStat> stats;

  final ProfileStat? following;
  final ProfileStat? followers;
  final VoidCallback? onFollowingTap;
  final VoidCallback? onFollowersTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final metaStyle = base
        .merge(tokens.text.meta)
        .copyWith(color: colors.textMeta);

    Widget link(ProfileStat stat, VoidCallback? onTap) => Semantics(
      button: onTap != null,
      label: '${stat.value} ${stat.label}',
      excludeSemantics: true,
      child: AppPressable(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSize.hit),
          child: Center(
            widthFactor: 1,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: stat.value,
                    style: base
                        .merge(tokens.text.metaStrong)
                        .copyWith(color: colors.textPrimary),
                  ),
                  TextSpan(text: ' ${stat.label}', style: metaStyle),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (following != null || followers != null)
          Row(
            children: [
              if (following != null) link(following!, onFollowingTap),
              if (following != null && followers != null)
                const SizedBox(width: AppSpace.xl),
              if (followers != null) link(followers!, onFollowersTap),
            ],
          ),
        if (stats.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.m),
            decoration: ShapeDecoration(
              color: colors.surfaceGrouped,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(tokens.radius.card),
              ),
            ),
            child: Row(
              children: [
                for (final stat in stats)
                  Expanded(
                    child: Tooltip(
                      message: '${stat.raw}',
                      child: Semantics(
                        label: '${stat.value} ${stat.label}',
                        excludeSemantics: true,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              stat.value,
                              maxLines: 1,
                              style: base
                                  .merge(tokens.text.control)
                                  .copyWith(
                                    color: colors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                            ),
                            const SizedBox(height: AppSpace.xxs),
                            Text(
                              stat.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: metaStyle,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class ProfileStat {
  const ProfileStat({
    required this.value,
    required this.label,
    required this.raw,
  });

  /// 已格式化的数字（1.2k）
  final String value;
  final String label;

  /// 原始值，长按提示
  final int raw;
}
