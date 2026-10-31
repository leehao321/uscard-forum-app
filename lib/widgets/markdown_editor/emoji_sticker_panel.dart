import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';

import '../../models/emoji.dart';
import '../../utils/platform_utils.dart';
import 'emoji_picker.dart';
import 'sticker_picker.dart';
import '../../../../../l10n/s.dart';

/// 表情/表情包面板容器
///
/// 通过顶部页内筛选或左右滑动切换"内置表情"和"表情包"两种模式。
/// 顶部是页内筛选，下面是两页内容。
class EmojiStickerPanel extends StatefulWidget {
  /// 选中内置表情的回调
  final ValueChanged<Emoji> onEmojiSelected;

  /// 选中表情包的回调，参数为 Markdown 图片文本
  final ValueChanged<String> onStickerSelected;

  /// 退格回调(移动端表情键盘标配:面板打开时软键盘收起,没有它
  /// 就只能切回键盘删)。null 或桌面端不显示退格键(桌面端焦点常驻
  /// 输入框,物理退格直接可用)。
  final VoidCallback? onBackspace;

  /// 搜索用内联视图(桌面悬浮弹层场景:bottomSheet 会被压在
  /// OverlayEntry 弹层下面,且交互割裂),false 走 bottomSheet。
  final bool inlineSearch;

  /// 紧凑模式(桌面悬浮弹层):切换胶囊/间距按小窗比例收紧,
  /// 圆角背景交给弹层壳,面板自身不再画顶部圆角。
  final bool compact;

  /// 请求宿主收起面板(桌面悬浮弹层:面板内要弹 Navigator 层的 sheet
  /// 时先收弹层,否则 sheet 被 root overlay 的弹层压住)
  final VoidCallback? onDismissRequested;

  /// 从编辑器 `:` 浮层的「更多」进来时带的搜索词:非空则自动弹出
  /// 搜索面板并预填。
  final String? initialSearch;

  const EmojiStickerPanel({
    super.key,
    required this.onEmojiSelected,
    required this.onStickerSelected,
    this.onBackspace,
    this.inlineSearch = false,
    this.compact = false,
    this.onDismissRequested,
    this.initialSearch,
  });

  @override
  State<EmojiStickerPanel> createState() => _EmojiStickerPanelState();
}

class _EmojiStickerPanelState extends State<EmojiStickerPanel> {
  late final PageController _pageController;
  int _currentPage = 0;

  /// 两个 picker 页面的实例缓存。
  ///
  /// 悬浮 Tab 显隐(滚动阈值触发)和翻页都会 setState ——
  /// 如果每次 build 都 new EmojiPicker/StickerPicker,这些 setState 会让
  /// PageView 子树整体 rebuild,grid 里几百个 cell 在滚动中途一帧内全部
  /// 重建,体感就是"滚一段卡一下"。缓存实例后 updateChild 直接跳过子树。
  List<Widget>? _pages;
  double? _pagesBottomPadding;

  List<Widget> _buildPages(double bottomPadding) {
    if (_pages == null || _pagesBottomPadding != bottomPadding) {
      _pagesBottomPadding = bottomPadding;
      _pages = [
        EmojiPicker(
          onEmojiSelected: widget.onEmojiSelected,
          bottomPadding: bottomPadding,
          inlineSearch: widget.inlineSearch,
          compact: widget.compact,
          initialSearch: widget.initialSearch,
        ),
        StickerPicker(
          onStickerSelected: widget.onStickerSelected,
          bottomPadding: bottomPadding,
          compact: widget.compact,
          onDismissRequested: widget.onDismissRequested,
        ),
      ];
    }
    return _pages!;
  }

  @override
  void didUpdateWidget(EmojiStickerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 回调变了必须重建缓存页,否则点选回调指向旧闭包
    if (widget.onEmojiSelected != oldWidget.onEmojiSelected ||
        widget.onStickerSelected != oldWidget.onStickerSelected) {
      _pages = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;

    // v2（设计说明 §3.2 表情面板）：顶部页内筛选「表情 · 表情包」（44 高），
    // 下面是 8 列表情网格；退格键悬在右下。不再有底部悬浮切换胶囊。
    return Column(
      children: [
        FilterTabs(
          labels: [S.current.emoji_tab, S.current.sticker_tab],
          selectedIndex: _currentPage,
          scrollable: false,
          onSelected: (index) => _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              PageView(
                controller: _pageController,
                onPageChanged: (index) => setState(() => _currentPage = index),
                children: _buildPages(safeBottom),
              ),

              // 悬浮退格键(仅移动端，靠右)
              if (widget.onBackspace != null && PlatformUtils.isMobile)
                Positioned(
                  right: 12,
                  bottom: safeBottom + 4,
                  child: CapsuleSurface(
                    shape: const CircleBorder(),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: widget.onBackspace,
                        child: SizedBox(
                          width: AppSize.hit,
                          height: AppSize.hit,
                          child: Center(
                            // backspace 字形视觉重心偏右(左侧是箭头尖),
                            // 几何居中后看着偏右,向左 1px 光学补偿。
                            child: Transform.translate(
                              offset: const Offset(-1, 0),
                              child: Icon(
                                AppIcons.backspace,
                                size: 20,
                                color: context.tokens.colors.textMeta,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
