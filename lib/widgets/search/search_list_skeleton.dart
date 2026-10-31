import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';

import '../common/skeleton.dart';
import '../topic/topic_list_skeleton.dart';

/// 搜索结果列表骨架屏（v2：列表行几何，分隔线左缩进 20）
class SearchListSkeleton extends StatelessWidget {
  final EdgeInsetsGeometry padding;

  const SearchListSkeleton({super.key, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: ListView.separated(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 6,
        separatorBuilder: (_, _) =>
            const AppHairline(indent: AppSpace.pageMargin),
        itemBuilder: (context, index) => const TopicRowSkeleton(),
      ),
    );
  }
}
