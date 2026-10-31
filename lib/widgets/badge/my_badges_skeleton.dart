import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';

import '../common/skeleton.dart';

/// 我的徽章页骨架屏：和加载完成后的版式一致（分组标题 + 3 列网格），
/// 不再自带顶栏——页面外层已经有导航栏（M-3）。
class MyBadgesSkeleton extends StatelessWidget {
  const MyBadgesSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: CustomScrollView(
        physics: const NeverScrollableScrollPhysics(),
        slivers: [
          const SliverPadding(padding: EdgeInsets.only(top: AppSpace.s)),
          _section(context),
          _section(context),
          const SliverPadding(padding: EdgeInsets.only(bottom: 48)),
        ],
      ),
    );
  }

  Widget _section(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.pageMargin,
            AppSpace.xl,
            AppSpace.pageMargin,
            AppSpace.m,
          ),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                SkeletonBox(width: 60, height: 15),
                const Spacer(),
                SkeletonBox(width: 28, height: 15, borderRadius: 4),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.pageMargin),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.95,
              crossAxisSpacing: AppSpace.s,
              mainAxisSpacing: AppSpace.s,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _card(context),
              childCount: 6,
            ),
          ),
        ),
      ],
    );
  }

  Widget _card(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: tokens.colors.surfaceGrouped,
        borderRadius: BorderRadius.circular(tokens.radius.card),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SkeletonCircle(size: 40),
          const SizedBox(height: AppSpace.s),
          SkeletonBox(width: 56, height: 13),
        ],
      ),
    );
  }
}
