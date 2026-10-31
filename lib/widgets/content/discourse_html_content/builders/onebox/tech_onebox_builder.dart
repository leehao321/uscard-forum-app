import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';

import '../../../../../utils/link_launcher.dart';
import 'onebox_base.dart';

/// 技术平台 Onebox 构建器
class TechOneboxBuilder {
  /// 构建 Stack Exchange 问答卡片
  static Widget buildStackExchange({
    required BuildContext context,
    required ThemeData theme,
    required dynamic element,
    List<LinkCount>? linkCounts,
  }) {
    final url = extractUrl(element);
    final clickCount = extractClickCountFromOnebox(
      element,
      linkCounts: linkCounts,
    );

    // 提取标题
    final h4Element = element.querySelector('h4');
    final h3Element = element.querySelector('h3');
    final titleLink =
        h4Element?.querySelector('a') ?? h3Element?.querySelector('a');
    final title = titleLink?.text ?? '';

    // 提取描述/摘要
    final descElement =
        element.querySelector('p') ??
        element.querySelector('.question-summary');
    final description = descElement?.text ?? '';

    // 提取投票数
    final voteElement =
        element.querySelector('.vote-count') ?? element.querySelector('.votes');
    final votes = voteElement?.text?.trim() ?? '';

    // 提取答案数
    final answerElement =
        element.querySelector('.answer-count') ??
        element.querySelector('.answers');
    final answers = answerElement?.text?.trim() ?? '';

    // 检查是否已有被接受的答案
    final hasAccepted =
        element.querySelector('.accepted-answer') != null ||
        element.classes?.contains('accepted') == true;

    // 提取标签
    final tagElements =
        element.querySelectorAll('.tag') +
        element.querySelectorAll('.post-tag');
    final tags = tagElements
        .map((tag) => tag.text?.trim())
        .where((text) => text != null && text.isNotEmpty)
        .cast<String>()
        .toList();

    // 提取提问者和时间
    final userElement =
        element.querySelector('.user-info') ?? element.querySelector('.author');
    final userInfo = userElement?.text?.trim() ?? '';

    // 判断是 Stack Overflow 还是其他 SE 站点
    final isStackOverflow = url.contains('stackoverflow.com');

    return OneboxContainer(
      onTap: () => _launchUrl(context, url),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 投票和答案统计
          Column(
            children: [
              // 投票数
              _StatBox(
                value: votes.isNotEmpty ? votes : '0',
                label: 'votes',
                theme: theme,
              ),
              const SizedBox(height: 8),
              // 答案数
              _StatBox(
                value: answers.isNotEmpty ? answers : '0',
                label: 'answers',
                theme: theme,
                isHighlighted: hasAccepted,
                highlightColor: AppRawColors.cFF5EBA7D,
              ),
            ],
          ),
          const SizedBox(width: 12),
          // 问题内容
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 站点标识
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isStackOverflow
                            ? AppRawColors.cFFF48024
                            : AppRawColors.cFF0077CC,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isStackOverflow ? 'Stack Overflow' : 'Stack Exchange',
                        style: const TextStyle(
                          color: AppFixedColors.white,
                          fontSize: AppFontSize.caption,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (clickCount != null && clickCount.isNotEmpty)
                      OneboxClickCount(count: clickCount),
                  ],
                ),
                const SizedBox(height: 8),
                // 标题
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppRawColors.cFF0077CC,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                // 描述
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                // 标签
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: tags.take(5).map((tag) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppRawColors.cFFE1ECF4,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          tag,
                          style: const TextStyle(
                            color: AppRawColors.cFF39739D,
                            fontSize: AppFontSize.caption,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
                // 用户信息
                if (userInfo.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    userInfo,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建 Hacker News 卡片
  static Widget buildHackernews({
    required BuildContext context,
    required ThemeData theme,
    required dynamic element,
    List<LinkCount>? linkCounts,
  }) {
    final url = extractUrl(element);
    final clickCount = extractClickCountFromOnebox(
      element,
      linkCounts: linkCounts,
    );

    // 提取标题
    final h4Element = element.querySelector('h4');
    final h3Element = element.querySelector('h3');
    final titleLink =
        h4Element?.querySelector('a') ?? h3Element?.querySelector('a');
    final title = titleLink?.text ?? '';

    // 提取来源 URL
    final sourceElement =
        element.querySelector('.source') ?? element.querySelector('.hn-source');
    final source = sourceElement?.text?.trim() ?? '';

    // 提取分数
    final scoreElement =
        element.querySelector('.score') ?? element.querySelector('.hn-score');
    final score = scoreElement?.text?.trim() ?? '';

    // 提取评论数
    final commentsElement =
        element.querySelector('.comments') ??
        element.querySelector('.hn-comments');
    final comments = commentsElement?.text?.trim() ?? '';

    // 提取作者和时间
    final authorElement =
        element.querySelector('.author') ?? element.querySelector('.hn-author');
    final author = authorElement?.text?.trim() ?? '';

    final timeElement =
        element.querySelector('time') ?? element.querySelector('.hn-time');
    final time = timeElement?.text?.trim() ?? '';

    return OneboxContainer(
      onTap: () => _launchUrl(context, url),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HN 标识
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: AppRawColors.cFFFF6600,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: const Center(
                  child: Text(
                    'Y',
                    style: TextStyle(
                      color: AppFixedColors.white,
                      fontSize: AppFontSize.meta,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Hacker News',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (source.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  '($source)',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          // 标题
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          // 统计信息
          Row(
            children: [
              if (score.isNotEmpty)
                OneboxStatItem(
                  icon: AppIcons.up,
                  value: score,
                  iconColor: AppRawColors.cFFFF6600,
                ),
              if (score.isNotEmpty && comments.isNotEmpty)
                const SizedBox(width: 16),
              if (comments.isNotEmpty)
                OneboxStatItem(icon: AppIcons.chatBubble, value: comments),
              if (clickCount != null && clickCount.isNotEmpty) ...[
                const SizedBox(width: 16),
                OneboxClickCount(count: clickCount),
              ],
              const Spacer(),
              if (author.isNotEmpty || time.isNotEmpty)
                Text(
                  [
                    if (author.isNotEmpty) 'by $author',
                    if (time.isNotEmpty) time,
                  ].join(' · '),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建 Pastebin 代码卡片
  static Widget buildPastebin({
    required BuildContext context,
    required ThemeData theme,
    required dynamic element,
    List<LinkCount>? linkCounts,
  }) {
    final url = extractUrl(element);
    final isDark = theme.brightness == Brightness.dark;
    final clickCount = extractClickCountFromOnebox(
      element,
      linkCounts: linkCounts,
    );

    // 提取标题
    final h4Element = element.querySelector('h4');
    final h3Element = element.querySelector('h3');
    final titleLink =
        h4Element?.querySelector('a') ?? h3Element?.querySelector('a');
    final title = (titleLink?.text ?? '').isEmpty
        ? 'Untitled'
        : titleLink!.text;

    // 提取代码预览
    final codeElement =
        element.querySelector('pre') ?? element.querySelector('code');
    final codeText = codeElement?.text ?? '';

    // 提取语言
    final langElement =
        element.querySelector('.syntax') ?? element.querySelector('.language');
    final language = langElement?.text?.trim() ?? '';

    final bgColor = isDark ? AppRawColors.cFF1E1E1E : AppRawColors.cFFF5F5F5;
    final borderColor = theme.colorScheme.outlineVariant.withValues(alpha: 0.3);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: bgColor,
        border: Border.all(color: borderColor),
      ),
      child: InkWell(
        onTap: () => _launchUrl(context, url),
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 头部
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppRawColors.cFF02589D,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(7),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    AppIcons.paste,
                    size: 16,
                    color: AppFixedColors.white,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: AppFixedColors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (clickCount != null && clickCount.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppFixedColors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            AppIcons.visibility,
                            size: 10,
                            color: AppFixedColors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            clickCount,
                            style: const TextStyle(
                              color: AppFixedColors.white,
                              fontSize: AppFontSize.caption,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (language.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppFixedColors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        language.toUpperCase(),
                        style: const TextStyle(
                          color: AppFixedColors.white,
                          fontSize: AppFontSize.caption,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // 代码预览
            if (codeText.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 150),
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        codeText,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: AppFontSize.meta,
                          color: isDark
                              ? AppFixedColors.white70
                              : AppFixedColors.black87,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 统计数字框组件
class _StatBox extends StatelessWidget {
  final String value;
  final String label;
  final ThemeData theme;
  final bool isHighlighted;
  final Color? highlightColor;

  const _StatBox({
    required this.value,
    required this.label,
    required this.theme,
    this.isHighlighted = false,
    this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isHighlighted
        ? (highlightColor ?? theme.colorScheme.primary)
        : theme.colorScheme.surfaceContainerHigh;
    final textColor = isHighlighted
        ? AppFixedColors.white
        : theme.colorScheme.onSurface;

    return Container(
      width: 48,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: isHighlighted
            ? null
            : Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: AppFontSize.body,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: AppFontSize.caption,
              color: textColor.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

// ============== 辅助函数 ==============

Future<void> _launchUrl(BuildContext context, String url) async {
  if (url.isEmpty) return;
  await launchContentLink(context, url);
}
