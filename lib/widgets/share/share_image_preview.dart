import 'package:flutter/material.dart';
import 'package:common_ui/common_ui.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_ui/m3e_ui.dart';

import '../../models/topic.dart';
import '../../providers/preferences_provider.dart';
import '../../services/discourse/discourse_service.dart';
import '../../l10n/s.dart';
import '../../services/toast_service.dart';
import '../../utils/dialog_utils.dart';
import '../../utils/image_save_utils.dart';
import '../../utils/screenshot_utils.dart';
import 'share_image_theme.dart';
import 'share_image_widget.dart';

/// 分享图片预览页
/// 以 BottomSheet 形式展示，支持保存和分享
class ShareImagePreview extends ConsumerStatefulWidget {
  /// 话题详情
  final TopicDetail detail;

  /// 帖子（如果为 null，则显示主帖）
  final Post? post;

  const ShareImagePreview({super.key, required this.detail, this.post});

  /// 显示预览 Sheet
  static Future<void> show(
    BuildContext context,
    TopicDetail detail, {
    Post? post,
  }) {
    return showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ShareImagePreview(detail: detail, post: post),
    );
  }

  @override
  ConsumerState<ShareImagePreview> createState() => _ShareImagePreviewState();
}

class _ShareImagePreviewState extends ConsumerState<ShareImagePreview> {
  final GlobalKey _repaintBoundaryKey = GlobalKey();
  bool _isSaving = false;
  bool _isSharing = false;
  late ShareImageTheme _selectedTheme;

  /// 当前要分享的帖子（可能需要从 API 获取）
  Post? _targetPost;
  bool _isLoadingPost = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    // 从偏好设置中读取上次选择的主题
    final savedIndex = ref.read(preferencesProvider).shareImageThemeIndex;
    _selectedTheme = ShareImageTheme.fromIndex(savedIndex);

    // 初始化帖子数据
    _initPost();
  }

  /// 初始化帖子数据
  void _initPost() {
    if (widget.post != null) {
      // 直接使用传入的帖子
      _targetPost = widget.post;
      return;
    }

    // 尝试从已加载的帖子中查找主帖
    final mainPost = widget.detail.postStream.posts
        .where((p) => p.postNumber == 1)
        .firstOrNull;

    if (mainPost != null) {
      _targetPost = mainPost;
      return;
    }

    // 需要从 API 获取主帖
    _fetchMainPost();
  }

  /// 从 API 获取主帖
  Future<void> _fetchMainPost() async {
    if (_isLoadingPost) return;

    setState(() {
      _isLoadingPost = true;
      _loadError = null;
    });

    try {
      final service = DiscourseService();
      // stream 中第一个就是主帖的 ID
      final mainPostId = widget.detail.postStream.stream.firstOrNull;
      if (mainPostId == null) {
        throw Exception(S.current.share_cannotGetPostId);
      }

      final postStream = await service.getPosts(widget.detail.id, [mainPostId]);
      final mainPost = postStream.posts.firstOrNull;

      if (mainPost != null && mounted) {
        setState(() {
          _targetPost = mainPost;
          _isLoadingPost = false;
        });
      } else {
        throw Exception(S.current.share_getPostFailed);
      }
    } catch (e) {
      debugPrint('[ShareImagePreview] fetchMainPost error: $e');
      if (mounted) {
        setState(() {
          _loadError = S.current.common_loadFailedRetry;
          _isLoadingPost = false;
        });
      }
    }
  }

  void _selectTheme(ShareImageTheme theme) {
    setState(() => _selectedTheme = theme);
    // 保存到偏好设置
    ref.read(preferencesProvider.notifier).setShareImageThemeIndex(theme.index);
  }

  /// 构建预览内容（预览卡片：圆角 16，不带阴影）
  Widget _buildPreviewContent(ThemeData theme) {
    // 加载中
    if (_isLoadingPost) {
      return SizedBox(
        height: _placeholderHeight,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: AppSpace.l),
              Text(S.current.share_loadingPost),
            ],
          ),
        ),
      );
    }

    // 加载失败
    if (_loadError != null) {
      return SizedBox(
        height: _placeholderHeight,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(AppIcons.error, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: AppSpace.l),
              Text(_loadError!),
              const SizedBox(height: AppSpace.l),
              FilledButton.icon(
                onPressed: _fetchMainPost,
                icon: const Icon(AppIcons.refresh),
                label: Text(S.current.common_retry),
              ),
            ],
          ),
        ),
      );
    }

    // 显示预览：整张图的底色就是所选样式的底色，不跟随 App 深浅色
    return SingleChildScrollView(
      child: Center(
        child: ClipRRect(
          key: const ValueKey('share_preview_card'),
          borderRadius: BorderRadius.circular(context.tokens.radius.sheet),
          // 使用 Theme 包裹，亮度与文字色按所选样式
          child: Theme(
            data: _selectedTheme.buildThemeData(theme),
            child: ShareImageWidget(
              detail: widget.detail,
              post: _targetPost,
              repaintBoundaryKey: _repaintBoundaryKey,
              shareTheme: _selectedTheme,
            ),
          ),
        ),
      ),
    );
  }

  /// 加载中 / 失败时预览区的高度
  static const double _placeholderHeight = 240;

  Future<Uint8List?> _captureImage() async {
    // 等待一帧确保渲染完成
    await Future.delayed(const Duration(milliseconds: 50));
    return ScreenshotUtils.captureWidget(_repaintBoundaryKey);
  }

  Future<void> _saveImage() async {
    if (_isSaving || _targetPost == null) return;
    setState(() => _isSaving = true);

    try {
      final bytes = await _captureImage();
      if (bytes == null) {
        throw Exception(S.current.share_screenshotFailed);
      }
      // 成功/失败/权限提示由 ImageSaveUtils 统一给出，这里只管 loading 状态
      await ScreenshotUtils.saveToGallery(bytes);
    } catch (e) {
      debugPrint('[ShareImagePreview] saveImage error: $e');
      if (mounted) {
        ToastService.showError(S.current.share_saveFailed);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _shareImage() async {
    if (_isSharing || _targetPost == null) return;
    setState(() => _isSharing = true);

    try {
      final bytes = await _captureImage();
      if (bytes == null) {
        throw Exception(S.current.share_screenshotFailed);
      }

      await ScreenshotUtils.shareImage(bytes);
    } catch (e) {
      debugPrint('[ShareImagePreview] shareImage error: $e');
      if (mounted) {
        ToastService.showError(S.current.common_shareFailed);
      }
    } finally {
      if (mounted) {
        setState(() => _isSharing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 半屏外壳：标题 + 右上 x；预览区可滚动，色板与按钮固定在底部
    return AppSheetScaffold(
      title: context.l10n.share_shareImageTitle,
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.pageMargin,
          AppSpace.xxl,
          AppSpace.pageMargin,
          0,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 样式色板
            ShareThemeSwatches(
              selected: _selectedTheme,
              onSelected: _selectTheme,
            ),
            const SizedBox(height: AppSpace.xxl),
            // 底部操作按钮：保存（次按钮）+ 分享（主按钮），48 高
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (_isSaving || _targetPost == null)
                        ? null
                        : _saveImage,
                    icon: _isSaving
                        ? const LoadingSpinner(size: 18)
                        : const Icon(AppIcons.saveAlt),
                    label: Text(ImageSaveUtils.actionLabel),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(AppSize.replyButton),
                    ).merge(AppButtonStyles.secondary(context)),
                  ),
                ),
                const SizedBox(width: AppSpace.m),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (_isSharing || _targetPost == null)
                        ? null
                        : _shareImage,
                    icon: _isSharing
                        ? const LoadingSpinner(
                            size: 18,
                            color: AppFixedColors.white,
                          )
                        : const Icon(AppIcons.share),
                    label: Text(context.l10n.common_share),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(AppSize.replyButton),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      child: _buildPreviewContent(theme),
    );
  }
}
