import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';

import '../../l10n/s.dart';

/// 列表顶部的「新话题」提示条（Figma「首页 · 新话题提示条」）。
///
/// 40 高的胶囊：surface/grouped 底、圆角 20；外框左右 20、上下 8，内边距 16；
/// 上箭头 16 + 13 号 medium brand 文字，整体居中。文案不显示数量。
/// 点按后由调用方刷新并回到列表顶部；[loading] 时显示菊花并忽略点按。
class TopicListUpdateBanner extends StatelessWidget {
  const TopicListUpdateBanner({
    super.key,
    required this.count,
    required this.loading,
    required this.onTap,
  });

  /// 待显示的新 / 更新话题数。只用来决定是否出现提示条，文案里不显示
  final int count;
  final bool loading;
  final VoidCallback onTap;

  /// 胶囊高度
  static const double height = 40;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final label = context.l10n.topics_newOrUpdatedHint;
    return Semantics(
      liveRegion: true,
      child: AppPressable(
        onTap: loading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.pageMargin,
            vertical: AppSpace.s,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceGrouped,
              borderRadius: BorderRadius.circular(AppRadius.pill(height)),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: height),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.l),
                child: Center(
                  child: loading
                      ? const CupertinoActivityIndicator(
                          radius: AppSize.iconS / 2,
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              AppIcons.up,
                              size: AppSize.iconS,
                              color: colors.brandPrimary,
                            ),
                            const SizedBox(width: AppSpace.s),
                            Flexible(
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall!
                                    .merge(tokens.text.meta)
                                    .copyWith(
                                      color: colors.brandPrimary,
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
