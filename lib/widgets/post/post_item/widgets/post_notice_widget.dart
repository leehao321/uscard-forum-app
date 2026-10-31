import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:common_ui/common_ui.dart';

import '../../../../l10n/s.dart';
import '../../../../models/topic.dart';
import '../../../../utils/fluxdo_render_callbacks.dart';
import '../../../../utils/time_utils.dart';

/// 帖子提示横条（新用户首发帖、回归用户、自定义通知）
class PostNoticeWidget extends StatelessWidget {
  final PostNotice notice;
  final String username;

  const PostNoticeWidget({
    super.key,
    required this.notice,
    required this.username,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isCustom = notice.type == 'custom';

    // custom 类型用浅红色，其他用浅蓝色
    final bgColor = isCustom
        ? (isDark
              ? context.tokens.colors.textDestructive.withValues(alpha: 0.1)
              : context.tokens.colors.textDestructive.withValues(alpha: 0.06))
        : (isDark
              ? context.tokens.colors.brandPrimary.withValues(alpha: 0.1)
              : context.tokens.colors.brandPrimary.withValues(alpha: 0.06));
    final borderColor = isCustom
        ? context.tokens.colors.textDestructive.withValues(alpha: 0.2)
        : context.tokens.colors.brandPrimary.withValues(alpha: 0.2);
    final iconColor = isCustom
        ? (isDark
              ? context.tokens.colors.textDestructive
              : context.tokens.colors.textDestructive)
        : (isDark
              ? context.tokens.colors.brandPrimary
              : context.tokens.colors.brandPrimary);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: _buildContent(theme, iconColor),
    );
  }

  Widget _buildContent(ThemeData theme, Color iconColor) {
    switch (notice.type) {
      case 'new_user':
        return _buildTextNotice(
          theme,
          icon: AppIcons.handHeart,
          iconColor: iconColor,
          text: S.current.post_firstPostNotice(username),
        );
      case 'returning_user':
        final lastTime = TimeUtils.parseUtcTime(notice.lastPostedAt);
        final timeText = lastTime != null
            ? TimeUtils.formatRelativeTime(lastTime)
            : S.current.post_longTimeAgo;
        return _buildTextNotice(
          theme,
          icon: AppIcons.forward,
          iconColor: iconColor,
          text: S.current.post_returningUserNotice(username, timeText),
        );
      case 'custom':
        if (notice.cooked != null && notice.cooked!.isNotEmpty) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  AppIcons.warning,
                  size: 14,
                  color: iconColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child:
                    FluxdoRenderCallbacks.generic(
                      heroTagNamespace: 'post_notice',
                    ).render(
                      cookedHtml: notice.cooked!,
                      baseTextStyle: theme.textTheme.bodySmall?.copyWith(
                        height: 1.5,
                      ),
                      selectionEnabled: false,
                    ),
              ),
            ],
          );
        }
        return const SizedBox.shrink();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTextNotice(
    ThemeData theme, {
    required IconData icon,
    required Color iconColor,
    required String text,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 14, color: iconColor),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
          ),
        ),
      ],
    );
  }
}
