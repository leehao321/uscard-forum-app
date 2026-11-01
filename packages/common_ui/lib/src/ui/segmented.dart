import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/tokens.dart';
import 'app_nav_bar.dart' show kChromeMaxTextScale;
import 'app_pressable.dart';

/// 分段控件（补充稿「并发与限流」「快捷词管理」的分段）：
/// 底 surface/grouped、r10、内边距 4；选中项是 surface/page 的圆角块，
/// 文字 13 Semibold text/primary，未选 13 Regular text/meta。
///
/// 整条 44 高（视觉 40，上下各 2 的透明热区），每一段都是一个 ≥44 的点击区。
/// 无障碍：每段读成按钮 + 选中状态，同组互斥。
class AppSegmented extends StatelessWidget {
  const AppSegmented({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  }) : assert(labels.length >= 2);

  final List<String> labels;

  /// 当前选中段；-1 表示一段都不选
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  /// 视觉高度（热区上下各多 2，凑足 44）
  static const double visualHeight = 40;

  static const double _pillInset =
      (AppSize.hit - visualHeight) / 2 + AppSpace.xs;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final base = Theme.of(context).textTheme.bodySmall!;
    final pillRadius = BorderRadius.circular(tokens.radius.table);
    final bar = SizedBox(
      height: AppSize.hit,
      child: Stack(
        children: [
          Positioned.fill(
            top: (AppSize.hit - visualHeight) / 2,
            bottom: (AppSize.hit - visualHeight) / 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.colors.surfaceGrouped,
                borderRadius: BorderRadius.circular(tokens.radius.field),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
            child: Row(
              children: [
                for (var i = 0; i < labels.length; i++)
                  Expanded(
                    child: AppPressable(
                      selected: i == selectedIndex,
                      inMutuallyExclusiveGroup: true,
                      onTap: () {
                        if (i == selectedIndex) return;
                        HapticFeedback.selectionClick();
                        onChanged(i);
                      },
                      child: Padding(
                        // 热区 44 高；视觉块 = 轨道 40 里上下各缩 4
                        padding: const EdgeInsets.symmetric(
                          vertical: _pillInset,
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: i == selectedIndex
                                ? tokens.colors.surfacePage
                                : Colors.transparent,
                            borderRadius: pillRadius,
                          ),
                          child: Center(
                            child: Text(
                              labels[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: base
                                  .merge(
                                    i == selectedIndex
                                        ? tokens.text.metaStrong
                                        : tokens.text.meta,
                                  )
                                  .copyWith(
                                    color: i == selectedIndex
                                        ? tokens.colors.textPrimary
                                        : tokens.colors.textMeta,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: kChromeMaxTextScale,
      child: bar,
    );
  }
}
