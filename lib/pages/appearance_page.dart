import 'package:flutter/material.dart';

import '../l10n/s.dart';
import '../settings/definitions/appearance_defs.dart';
import '../widgets/settings/appearance_widgets.dart';
import '../widgets/settings/settings_group_page.dart';

/// 外观：顶部固定实时预览卡，下面是预设 / 模式 / 强调色 / 字体 / 微调等分组
class AppearancePage extends StatelessWidget {
  final String? highlightId;

  const AppearancePage({super.key, this.highlightId});

  @override
  Widget build(BuildContext context) {
    return SettingsGroupPage(
      title: context.l10n.appearance_title,
      groupsBuilder: buildAppearanceGroups,
      highlightId: highlightId,
      pinnedHeader: const AppearancePreviewCard(),
    );
  }
}
