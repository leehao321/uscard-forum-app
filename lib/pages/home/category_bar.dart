import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';

import '../../l10n/s.dart';

/// 首页分类条（设计说明 §3.1「分类条」）：高 44，左侧可横滑的分类项
/// （13 + 下划线，选中 brand），右侧固定「全部分类」按钮（grid 16 + 13，
/// 底色 surface/page 盖住横滑区尾部）。
///
/// 分类切换只靠点选，不再左右横滑切页。
class HomeCategoryBar extends StatelessWidget {
  const HomeCategoryBar({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    required this.onReselect,
    required this.onOpenAllCategories,
    this.dividerAfter,
  });

  /// 前面是浏览方式（全部 / 精彩 / 难绷），后面是置顶分类名
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// 再点已选中的一项：回到顶部
  final VoidCallback onReselect;
  final VoidCallback onOpenAllCategories;

  /// 「全部 · 精彩 · 难绷」与分类之间的竖线位置（最后一个浏览方式项的下标）
  final int? dividerAfter;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final insets = readableInsets(context, gutter: 0);
    return DecoratedBox(
      decoration: BoxDecoration(color: tokens.colors.surfacePage),
      child: Row(
        children: [
          Expanded(
            child: FilterTabs(
              labels: labels,
              selectedIndex: selectedIndex,
              dividerAfter: dividerAfter,
              padding: EdgeInsets.only(
                left: insets.left + AppSpace.pageMargin,
                right: AppSpace.m,
              ),
              onSelected: (i) =>
                  i == selectedIndex ? onReselect() : onSelected(i),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(right: insets.right),
            child: _AllCategoriesButton(onTap: onOpenAllCategories),
          ),
        ],
      ),
    );
  }
}

class _AllCategoriesButton extends StatelessWidget {
  const _AllCategoriesButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final label = context.l10n.category_allCategories;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: kChromeMaxTextScale,
      child: AppPressable(
        onTap: onTap,
        semanticLabel: label,
        excludeChildSemantics: true,
        child: Container(
          height: AppSize.categoryBar,
          padding: const EdgeInsets.only(left: AppSpace.m, right: AppSpace.l),
          color: tokens.colors.surfacePage,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                AppIcons.category,
                size: AppSize.iconS,
                color: tokens.colors.textPrimary,
              ),
              const SizedBox(width: AppSpace.xs),
              Text(
                label,
                maxLines: 1,
                style: Theme.of(context).textTheme.bodySmall!
                    .merge(tokens.text.meta)
                    .copyWith(color: tokens.colors.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
