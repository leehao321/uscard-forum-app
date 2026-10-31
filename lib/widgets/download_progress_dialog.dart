import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/s.dart';
import '../providers/apk_update_provider.dart';
import '../services/apk_download_service.dart';

/// APK 下载进度对话框（v2：普通对话框外壳，不再有渐变背景）
///
/// 状态完全从 [apkUpdateProvider] 读取；本身只是"观察者"，关闭弹窗不会取消下载。
class DownloadProgressDialog extends ConsumerWidget {
  const DownloadProgressDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(apkUpdateProvider);
    final tokens = context.tokens;
    final colors = tokens.colors;
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: colors.surfaceElevated,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 60),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildMainProgress(context, state),
            const SizedBox(height: AppSpace.l),
            Text(
              _statusText(state),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.merge(tokens.text.meta)
                  .copyWith(color: colors.textMeta),
            ),
            const SizedBox(height: AppSpace.xl),
            _buildBottomAction(context, ref, state),
          ],
        ),
      ),
    );
  }

  Widget _buildMainProgress(BuildContext context, ApkUpdateState state) {
    final status = state.status;
    final tokens = context.tokens;
    final colors = tokens.colors;
    final theme = Theme.of(context);

    if (status == ApkDownloadStatus.downloading) {
      return Column(
        children: [
          Text(
            '${state.progress}%',
            style: theme.textTheme.headlineMedium
                ?.merge(tokens.text.title)
                .copyWith(
                  color: colors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
          const SizedBox(height: AppSpace.m),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: state.progress / 100,
              minHeight: 4,
              color: colors.brandPrimary,
              backgroundColor: colors.avatarFill,
            ),
          ),
        ],
      );
    } else if (status == ApkDownloadStatus.verifying ||
        status == ApkDownloadStatus.idle) {
      return const SizedBox(
        height: 48,
        child: Center(child: CircularProgressIndicator.adaptive()),
      );
    } else {
      IconData icon;
      Color iconColor = colors.brandPrimary;

      switch (status) {
        case ApkDownloadStatus.installing:
          icon = AppIcons.download;
          break;
        case ApkDownloadStatus.completed:
          icon = AppIcons.checkCircle;
          break;
        case ApkDownloadStatus.error:
          icon = AppIcons.error;
          iconColor = colors.textDestructive;
          break;
        default:
          icon = AppIcons.download;
      }

      return Icon(icon, size: 48, color: iconColor);
    }
  }

  String _statusText(ApkUpdateState state) {
    final l10n = S.current;
    final assetName = state.asset?.name ?? '';
    switch (state.status) {
      case ApkDownloadStatus.idle:
        return l10n.download_connecting;
      case ApkDownloadStatus.downloading:
        return l10n.download_downloading(assetName);
      case ApkDownloadStatus.verifying:
        return l10n.download_verifying;
      case ApkDownloadStatus.installing:
        return l10n.download_installing;
      case ApkDownloadStatus.completed:
        return l10n.download_installStarted;
      case ApkDownloadStatus.error:
        return state.error ?? l10n.common_error;
    }
  }

  Widget _buildBottomAction(
    BuildContext context,
    WidgetRef ref,
    ApkUpdateState state,
  ) {
    final l10n = S.current;

    switch (state.status) {
      case ApkDownloadStatus.error:
        final asset = state.asset;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: () {
                ref.read(apkUpdateProvider.notifier).reset();
                Navigator.of(context).pop();
              },
              child: Text(l10n.common_close),
            ),
            const SizedBox(width: AppSpace.m),
            TextButton(
              onPressed: asset == null
                  ? null
                  : () => ref.read(apkUpdateProvider.notifier).start(asset),
              child: Text(l10n.common_retry),
            ),
          ],
        );

      case ApkDownloadStatus.completed:
      case ApkDownloadStatus.installing:
        return TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.common_close),
        );

      case ApkDownloadStatus.idle:
      case ApkDownloadStatus.verifying:
      case ApkDownloadStatus.downloading:
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () async {
                await ref.read(apkUpdateProvider.notifier).cancel();
                if (context.mounted) Navigator.of(context).pop();
              },
              child: Text(l10n.common_cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.update_continueInBackground),
            ),
          ],
        );
    }
  }
}
