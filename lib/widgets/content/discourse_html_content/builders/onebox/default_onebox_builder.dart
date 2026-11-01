import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';

import '../../../../../services/discourse_cache_manager.dart';
import '../../../../../utils/link_launcher.dart';
import 'onebox_base.dart';

/// 构建默认链接预览卡片（补充稿 11）
///
/// 模板：预览图（整宽、高 160、圆角 12，没有图就不画）→ 标题 17 Semibold
/// （最多 2 行）→ 摘要 13 meta（最多 2 行）→ 站点行（图标 16 + 站点名 13 meta，
/// 右端点击数）。GitHub 等专用卡片共用同一层外壳（[OneboxContainer]）。
Widget buildDefaultOnebox({
  required BuildContext context,
  required ThemeData theme,
  required dynamic element,
  List<LinkCount>? linkCounts,
}) {
  // 提取点击数（支持 data-clicks 属性）
  final clickCount = extractClickCountFromOnebox(
    element,
    linkCounts: linkCounts,
  );

  // 提取标题
  final h4Element = element.querySelector('h4');
  final h3Element = element.querySelector('h3');
  final titleLink =
      h4Element?.querySelector('a') ?? h3Element?.querySelector('a');
  final title = titleLink?.text ?? h3Element?.text ?? h4Element?.text ?? '';
  // titleLink 可能为空（如 Google Play onebox 的 h3 不含 <a>），回退到 extractUrl
  final url = titleLink?.attributes['href'] ?? extractUrl(element);

  // 提取描述
  final descElement = element.querySelector('p');
  final description = descElement?.text ?? '';

  // 提取图标
  final iconElement = element.querySelector('img.site-icon');
  final iconUrl = iconElement?.attributes['src'] ?? '';

  // 提取来源
  final sourceElement = element.querySelector('.source a');
  final sourceName = sourceElement?.text ?? '';

  // 提取缩略图
  final thumbnailElement = element.querySelector('.thumbnail');
  final thumbnailUrl = thumbnailElement?.attributes['src'] ?? '';

  return OneboxContainer(
    onTap: () async {
      if (url.isNotEmpty) {
        await launchContentLink(context, url);
      }
    },
    child: DefaultOneboxCard(
      title: title,
      description: description,
      thumbnailUrl: thumbnailUrl,
      sourceName: sourceName,
      iconUrl: iconUrl,
      clickCount: clickCount,
    ),
  );
}

/// 默认链接预览卡片的内容（不含外壳）
class DefaultOneboxCard extends StatelessWidget {
  const DefaultOneboxCard({
    super.key,
    required this.title,
    required this.description,
    required this.thumbnailUrl,
    required this.sourceName,
    required this.iconUrl,
    this.clickCount,
  });

  final String title;
  final String description;
  final String thumbnailUrl;
  final String sourceName;
  final String iconUrl;
  final String? clickCount;

  /// 预览图高度
  static const double thumbnailHeight = 160;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final metaStyle = theme.textTheme.bodySmall!
        .merge(tokens.text.meta)
        .copyWith(color: colors.textMeta);
    final hasSite =
        sourceName.isNotEmpty || iconUrl.isNotEmpty || clickCount != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (thumbnailUrl.isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(tokens.radius.card),
            child: SizedBox(
              height: thumbnailHeight,
              // 底色垫在图下面：图还没到的时候就是一块 surface/grouped
              child: ColoredBox(
                color: colors.surfaceGrouped,
                child: Image(
                  image: discourseImageProvider(thumbnailUrl),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Center(
                    child: Icon(
                      AppIcons.image,
                      size: AppSize.iconL,
                      color: colors.textMeta,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.s),
        ],
        if (title.isNotEmpty)
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium!
                .merge(tokens.text.headline)
                .copyWith(color: colors.textPrimary),
          ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          Text(
            description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: metaStyle,
          ),
        ],
        if (hasSite) ...[
          const SizedBox(height: AppSpace.s),
          Row(
            children: [
              if (iconUrl.isNotEmpty)
                Image(
                  image: discourseImageProvider(iconUrl),
                  width: AppSize.iconS,
                  height: AppSize.iconS,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    AppIcons.globe,
                    size: AppSize.iconS,
                    color: colors.textMeta,
                  ),
                )
              else
                Icon(
                  AppIcons.globe,
                  size: AppSize.iconS,
                  color: colors.textMeta,
                ),
              const SizedBox(width: AppSpace.s),
              Expanded(
                child: Text(
                  sourceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: metaStyle,
                ),
              ),
              if (clickCount != null) ...[
                const SizedBox(width: AppSpace.s),
                OneboxClickCount(count: clickCount!),
              ],
            ],
          ),
        ],
      ],
    );
  }
}
