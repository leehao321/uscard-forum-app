import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/s.dart';
import '../providers/connectivity_provider.dart';
import '../services/connectivity_service.dart';

/// 离线提示条（占位式，放在列表上方，内容自然下移）
///
/// 仅负责 UI 显示，Toast 通知由 main.dart 全局处理
class OfflineIndicator extends ConsumerWidget {
  const OfflineIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connAsync = ref.watch(isConnectedProvider);
    // 初始状态（无数据）视为已连接
    final isConnected = connAsync.value ?? true;

    final theme = Theme.of(context);
    final tokens = context.tokens;
    final colors = tokens.colors;

    // v2：13 meta 一行 + 44 刷新钮，不再用色块
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: isConnected
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(
                left: AppSpace.pageMargin,
                right: AppSpace.xs,
              ),
              child: Row(
                children: [
                  Icon(
                    AppIcons.wifiOff,
                    size: AppSize.iconS,
                    color: colors.textMeta,
                  ),
                  const SizedBox(width: AppSpace.s),
                  Expanded(
                    child: Text(
                      context.l10n.common_networkDisconnected,
                      style: theme.textTheme.bodySmall
                          ?.merge(tokens.text.meta)
                          .copyWith(color: colors.textMeta),
                    ),
                  ),
                  AppIconButton(
                    icon: AppIcons.refresh,
                    semanticLabel: context.l10n.common_refresh,
                    onPressed: () => ConnectivityService().check(),
                  ),
                ],
              ),
            ),
    );
  }
}
