import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../../l10n/s.dart';
import '../../models/topic.dart';
import '../../pages/image_viewer_page.dart';
import '../../services/discourse_cache_manager.dart';
import '../../services/toast_service.dart';
import '../../utils/image_save_utils.dart';
import '../../utils/platform_utils.dart';
import '../../utils/quote_builder.dart';
import '../../utils/share_utils.dart';
import '../content/discourse_html_content/image_utils.dart';
import 'app_bottom_sheet.dart';

/// 浮起菜单源信息包：调用方汇总传入，避免参数发散。
class ImageLiftSpec {
  const ImageLiftSpec({
    required this.sourceContext,
    required this.previewBuilder,
    this.sourceRadius = 0,
    this.onPreviewTap,
  });

  /// 源图 BuildContext（取源矩形）。
  final BuildContext sourceContext;

  /// 预览内容 builder（填满浮起卡片，复用源图缓存零闪烁）。
  final WidgetBuilder previewBuilder;

  /// 源图圆角（网格瓦片 4）。
  final double sourceRadius;

  /// 保留字段：v2 浮起菜单里「查看大图」是菜单项，不再有点预览打开。
  final VoidCallback? onPreviewTap;
}

/// 图片浮起会话的状态：源图处监听 [activeSource]，值与自身 context 相同时
/// 以 Opacity(0) 隐藏（iOS lift 语义：源视图被「拿走」浮起，原位空缺）。
class ImageLiftMenu {
  ImageLiftMenu._();

  static final ValueNotifier<BuildContext?> _activeSource =
      ValueNotifier<BuildContext?>(null);

  static ValueListenable<BuildContext?> get activeSource => _activeSource;
}

/// 图片上下文菜单（v2）
///
/// 内容页和图片查看页复用。桌面右键：在鼠标位置弹 AppMenu；
/// 移动端长按：图片浮起 + 菜单（showLiftedContextMenu），取不到源矩形时
/// 回退成底部半屏的操作列表。
class ImageContextMenu {
  ImageContextMenu._();

  /// 显示图片上下文菜单
  ///
  /// [imageUrl] 图片 URL（会自动转换为原图 URL）
  /// [showViewFullImage] 是否显示「查看大图」选项（图片查看页内不需要）
  /// [post] 帖子对象（用于引用功能，为 null 时隐藏引用选项）
  /// [topicId] 话题 ID（用于引用功能）
  /// [onQuoteImage] 引用回调（打开回复框），为 null 时隐藏「引用」选项
  /// [position] 鼠标全局位置（桌面端右键时传入，用于定位菜单）
  /// [onClose] 关闭回调（图片查看页内传入，显示「关闭」选项）
  /// [heroTag] 源缩略图的 Hero tag（「查看大图」打开查看器时飞行转场用）
  /// [lift] 浮起源信息（移动端长按）；null（如图片查看页）走底部半屏
  static void show({
    required BuildContext context,
    required String imageUrl,
    bool showViewFullImage = true,
    Post? post,
    int? topicId,
    void Function(String quote, Post post)? onQuoteImage,
    Offset? position,
    VoidCallback? onClose,
    // 引用 / 复制引用用的 markdown（理想情况是 `![alt](upload://sha1.ext)`，
    // 对齐 Web 端「复制引用」原样保留图片格式的行为）。为 null 时降级用
    // `![image](CDN 完整 URL)`。
    String? quoteMarkdown,
    String? heroTag,
    ImageLiftSpec? lift,

    /// 原始文件名（接口 / cooked 提供）：分享与「查看大图」的命名依据。
    String? fileName,
  }) {
    final originalUrl = DiscourseImageUtils.getOriginalUrl(imageUrl);
    final items = _items(
      context: context,
      originalUrl: originalUrl,
      imageUrl: imageUrl,
      showViewFullImage: showViewFullImage,
      post: post,
      topicId: topicId,
      onQuoteImage: onQuoteImage,
      quoteMarkdown: quoteMarkdown,
      heroTag: heroTag,
      fileName: fileName,
      onClose: onClose,
    );

    if (PlatformUtils.isDesktop && position != null) {
      showAppMenu<VoidCallback>(
        context: context,
        anchor: position & Size.zero,
        sections: [items],
      );
      return;
    }

    if (lift != null && lift.sourceContext.mounted) {
      final sourceContext = lift.sourceContext;
      ImageLiftMenu._activeSource.value = sourceContext;
      showLiftedContextMenu<VoidCallback>(
        context: sourceContext,
        sourceRect: globalRectOf(sourceContext),
        liftedBuilder: (ctx) => ClipRRect(
          borderRadius: BorderRadius.circular(lift.sourceRadius),
          child: lift.previewBuilder(ctx),
        ),
        sections: [items],
      ).whenComplete(() {
        if (ImageLiftMenu._activeSource.value == sourceContext) {
          ImageLiftMenu._activeSource.value = null;
        }
      });
      return;
    }

    _showSheet(context, items);
  }

  /// 动作（浮起菜单、桌面菜单、底部半屏共用同一份顺序与语义）。
  static List<AppMenuItem<VoidCallback>> _items({
    required BuildContext context,
    required String originalUrl,
    required String imageUrl,
    required bool showViewFullImage,
    Post? post,
    int? topicId,
    void Function(String quote, Post post)? onQuoteImage,
    String? quoteMarkdown,
    String? heroTag,
    String? fileName,
    VoidCallback? onClose,
  }) {
    final s = S.current;
    String quoteOf(Post post, int topicId) => QuoteBuilder.build(
      markdown: quoteMarkdown ?? '![image]($originalUrl)',
      displayName: post.name,
      username: post.username,
      postNumber: post.postNumber,
      topicId: topicId,
    );
    return [
      if (showViewFullImage)
        AppMenuItem(
          icon: AppIcons.search,
          label: s.image_viewFull,
          onTap: () {
            if (!context.mounted) return;
            ImageViewerPage.open(
              context,
              originalUrl,
              thumbnailUrl: imageUrl,
              heroTag: heroTag,
              filenames: [fileName],
            );
          },
        ),
      AppMenuItem(
        icon: AppIcons.copy,
        label: s.image_copyImage,
        onTap: () => _copyImage(originalUrl),
      ),
      AppMenuItem(
        icon: AppIcons.link,
        label: s.image_copyLink,
        onTap: () {
          Clipboard.setData(ClipboardData(text: originalUrl));
          ToastService.showSuccess(s.common_linkCopied);
        },
      ),
      AppMenuItem(
        icon: AppIcons.saveAlt,
        label: ImageSaveUtils.actionLabel,
        onTap: () => _saveImage(originalUrl, fileName: fileName),
      ),
      // Linux 上 share_plus 不支持分享文件，隐藏该项（保存仍可用）
      if (ShareUtils.canShareFiles)
        AppMenuItem(
          icon: AppIcons.share,
          label: s.common_shareImage,
          onTap: () => _shareImage(originalUrl, fileName: fileName),
        ),
      if (post != null && topicId != null && onQuoteImage != null)
        AppMenuItem(
          icon: AppIcons.formatQuote,
          label: s.common_quote,
          onTap: () => onQuoteImage(quoteOf(post, topicId), post),
        ),
      if (post != null && topicId != null)
        AppMenuItem(
          icon: AppIcons.copy,
          label: s.common_copyQuote,
          onTap: () {
            Clipboard.setData(ClipboardData(text: quoteOf(post, topicId)));
            ToastService.showSuccess(s.common_quoteCopied);
          },
        ),
      if (onClose != null)
        AppMenuItem(
          icon: AppIcons.close,
          label: s.common_close,
          onTap: onClose,
        ),
    ];
  }

  /// 没有浮起源（如图片查看页，图已全屏）时：底部半屏的操作列表。
  static void _showSheet(
    BuildContext context,
    List<AppMenuItem<VoidCallback>> items,
  ) {
    AppBottomSheet.show(
      context: context,
      contentPadding: EdgeInsets.zero,
      builder: (ctx) {
        final colors = ctx.tokens.colors;
        final base = Theme.of(ctx).textTheme.bodyMedium!;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in items)
              AppPressable(
                highlight: true,
                onTap: () {
                  Navigator.pop(ctx);
                  item.onTap?.call();
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: AppSize.row48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.pageMargin,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          item.icon,
                          size: AppSize.iconM,
                          color: colors.textPrimary,
                        ),
                        const SizedBox(width: AppSpace.m),
                        Expanded(
                          child: Text(
                            item.label,
                            style: base
                                .merge(ctx.tokens.text.control)
                                .copyWith(color: colors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// 复制图片到剪贴板
  static Future<void> _copyImage(String imageUrl) async {
    try {
      final bytes = await BlobImageCache.fetch(
        BlobImageCache.contentBucket,
        imageUrl,
      );
      if (bytes.isEmpty) {
        ToastService.showError(S.current.image_fetchFailed);
        return;
      }
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) {
        ToastService.showError(S.current.common_clipboardUnavailable);
        return;
      }
      final item = DataWriterItem();
      item.add(Formats.png(bytes));
      await clipboard.write([item]);
      ToastService.showSuccess(S.current.image_copied);
    } catch (e) {
      debugPrint('[ImageContextMenu] copyImage error: $e');
      ToastService.showError(S.current.image_copyFailed);
    }
  }

  /// 保存图片（移动端进相册、桌面端另存为文件）
  static Future<void> _saveImage(String imageUrl, {String? fileName}) async {
    try {
      final bytes = await BlobImageCache.fetch(
        BlobImageCache.contentBucket,
        imageUrl,
      );
      // 命名与分享同口径：原始文件名 → URL 末段 → 时间戳，逐级回退
      final base =
          ShareUtils.safeFileBaseName(fileName) ??
          'fluxdo_${DateTime.now().millisecondsSinceEpoch}';
      final ext = BlobImageCache.httpUrlExtension(imageUrl);
      await ImageSaveUtils.saveBytes(bytes, fileName: '$base.$ext');
    } catch (e) {
      debugPrint('[ImageContextMenu] saveImage error: $e');
      ToastService.showError(S.current.share_saveFailed);
    }
  }

  /// 分享图片
  static Future<void> _shareImage(String imageUrl, {String? fileName}) async {
    try {
      final file = await BlobImageCache.getFile(
        BlobImageCache.contentBucket,
        imageUrl,
      );
      // 复制为可读文件名的临时文件再分享(缓存文件按 md5 寻址):
      // 原始文件名(接口/cooked) → URL 末段 → 时间戳,逐级回退。
      await ShareUtils.shareImageFile(
        file,
        ext: BlobImageCache.httpUrlExtension(imageUrl),
        fileName: fileName,
        urlHint: imageUrl,
      );
    } catch (e) {
      debugPrint('[ImageContextMenu] shareImage error: $e');
      ToastService.showError(S.current.common_shareFailed);
    }
  }
}
