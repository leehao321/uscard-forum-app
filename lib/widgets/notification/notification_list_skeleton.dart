import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';

import '../common/skeleton.dart';
import '../topic/topic_list_skeleton.dart';

/// 通知列表骨架屏（v2：头像行几何，分隔线左缩进 66）
class NotificationListSkeleton extends StatelessWidget {
  const NotificationListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: ListView.separated(
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 10,
        separatorBuilder: (_, _) =>
            const AppHairline(indent: AvatarRow.separatorIndent),
        itemBuilder: (context, index) => const AvatarRowSkeleton(),
      ),
    );
  }
}
