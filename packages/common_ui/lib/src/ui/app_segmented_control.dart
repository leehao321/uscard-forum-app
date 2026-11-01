import 'package:flutter/material.dart';

import '../tokens/tokens.dart';
import 'app_pressable.dart';

/// 分段控件（补充稿「图像 / 文本」）：灰底轨道（`surface/grouped`、r10、内边距 4），
/// 选中的一段是 32 高 r8 的 `surface/page` 底、13 Medium `text/primary`，
/// 未选中 13 Regular `text/meta`。
///
/// 视觉高 40；每一段的点击区域撑到 56 高（上下各 8，和稿里的外框一致），
/// 满足 44 的最小热区。两段以上等分宽度。
class AppSegmentedControl extends StatelessWidget {
  const AppSegmentedControl({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpace.pageMargin),
  });

  final List<String> labels;
  final int selectedIndex;

  /// null：整个控件不可点（内置快捷词的类型不能改）
  final ValueChanged<int>? onSelected;

  /// 控件外的左右内边距，默认页边距 20
  final EdgeInsetsGeometry padding;

  /// 轨道上下留出的点击区域
  static const double _hitInset = 8;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final base = Theme.of(context).textTheme.bodyMedium!.merge(tokens.text.meta);
    return Padding(
      padding: padding,
      child: SizedBox(
        height: 40 + 2 * _hitInset,
        child: Stack(
          children: [
            Positioned.fill(
              top: _hitInset,
              bottom: _hitInset,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceGrouped,
                  borderRadius: BorderRadius.circular(tokens.radius.field),
                ),
              ),
            ),
            Positioned.fill(
              left: AppSpace.xs,
              right: AppSpace.xs,
              child: Row(
                children: [
                  for (var i = 0; i < labels.length; i++)
                    Expanded(
                      child: AppPressable(
                        onTap: onSelected == null ? null : () => onSelected!(i),
                        selected: i == selectedIndex,
                        inMutuallyExclusiveGroup: true,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: _hitInset + AppSpace.xs,
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: i == selectedIndex
                                  ? colors.surfacePage
                                  : null,
                              borderRadius: BorderRadius.circular(
                                tokens.radius.table,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                labels[i],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: base.copyWith(
                                  fontWeight: i == selectedIndex
                                      ? FontWeight.w500
                                      : FontWeight.w400,
                                  color: i == selectedIndex
                                      ? colors.textPrimary
                                      : colors.textMeta,
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
      ),
    );
  }
}
