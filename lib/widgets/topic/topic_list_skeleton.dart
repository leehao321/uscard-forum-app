import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';

import '../common/skeleton.dart';

/// 话题列表骨架屏（v2，共享状态画板「骨架 · 200ms 后才出现」）：
/// 按列表行的几何画——pad 12 20，标题条 16 高（两行时第二行短一些），
/// 元信息条 12 高，左边「分类 · 作者 · 时间」、右边计数；行间 0.5 发丝线
/// 左缩进 20。
class TopicListSkeleton extends StatelessWidget {
  final EdgeInsetsGeometry padding;

  /// 私信列表用头像行骨架（字母头像 34 + 标题 + 元信息）
  final bool messageStyle;

  const TopicListSkeleton({
    super.key,
    this.padding = EdgeInsets.zero,
    this.messageStyle = false,
  });

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: ListView.separated(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 8,
        separatorBuilder: (_, _) => AppHairline(
          indent: messageStyle
              ? AvatarRow.separatorIndent
              : AppSpace.pageMargin,
        ),
        itemBuilder: (context, index) => messageStyle
            ? const AvatarRowSkeleton()
            : TopicRowSkeleton(twoLines: index.isEven),
      ),
    );
  }
}

/// 列表行骨架
class TopicRowSkeleton extends StatelessWidget {
  const TopicRowSkeleton({super.key, this.twoLines = true});

  final bool twoLines;

  @override
  Widget build(BuildContext context) {
    // 条宽按行内可用宽度的比例算（侧栏、宽屏里列表不一定占满屏幕）
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpace.pageMargin,
        vertical: context.tokens.rowPadV,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: width * (twoLines ? 0.92 : 0.75), height: 16),
              if (twoLines) ...[
                const SizedBox(height: AppSpace.s),
                SkeletonBox(width: width * 0.6, height: 16),
              ],
              const SizedBox(height: AppSpace.s),
              Row(
                children: [
                  SkeletonBox(width: width * 0.4, height: 12),
                  const Spacer(),
                  SkeletonBox(width: width * 0.15, height: 12),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 头像行骨架（通知、私信、用户结果）
class AvatarRowSkeleton extends StatelessWidget {
  const AvatarRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpace.pageMargin,
        vertical: context.tokens.rowPadV,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonCircle(size: AppSize.avatarS),
          const SizedBox(width: AppSpace.m),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: width * 0.8, height: 16),
                    const SizedBox(height: AppSpace.s),
                    SkeletonBox(width: width * 0.5, height: 12),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
