import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:m3e_ui/m3e_ui.dart';

import '../../l10n/s.dart';
import '../../services/toast_service.dart';
import '../../utils/dialog_utils.dart';
import '../../widgets/common/app_bottom_sheet.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/notification_level_button.dart';
import '../../widgets/common/paged_list_footer.dart';
import '../../widgets/topic/topic_list_skeleton.dart';

/// 组件样本（开发者模式，0.4.0 计划 §4）：一页看完全部 v2 共享组件，
/// 真机上切浅色 / 深色、调系统字号对照 Figma。
///
/// 开发者自用的样本页：示例文字（按钮名、假数据）不进多语言。
class UiGalleryPage extends StatefulWidget {
  const UiGalleryPage({super.key});

  @override
  State<UiGalleryPage> createState() => _UiGalleryPageState();
}

class _UiGalleryPageState extends State<UiGalleryPage> {
  int _tab = 0;
  int _filter = 0;
  int _step = 1;
  bool _switch = true;
  bool _pill = true;
  int _radio = 0;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      appBar: AppNavBar(title: context.l10n.about_uiGallery, showDivider: true),
      body: ListView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom + AppSpace.x40,
        ),
        children: [
          const _Header('颜色'),
          _ColorSwatches(colors: tokens.colors),
          const _Header('字号'),
          const _TextSamples(),
          const _Header('按钮'),
          _Pad(
            Wrap(
              spacing: AppSpace.m,
              runSpacing: AppSpace.m,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton(onPressed: () {}, child: const Text('主要')),
                FilledButton(
                  style: AppButtonStyles.secondary(context),
                  onPressed: () {},
                  child: const Text('次要'),
                ),
                TextButton(onPressed: () {}, child: const Text('文字')),
                FilledButton(
                  style: AppButtonStyles.large,
                  onPressed: () {},
                  child: const Text('48 高'),
                ),
                const FilledButton(onPressed: null, child: Text('不可用')),
              ],
            ),
          ),
          const _Header('开关 · 滑块 · 进度'),
          SegmentedCardGroupPadding(
            child: SegmentedCardGroup(
              children: [
                SwitchListTile.adaptive(
                  title: const Text('开关'),
                  value: _switch,
                  onChanged: (v) => setState(() => _switch = v),
                ),
              ],
            ),
          ),
          _Pad(
            StepSlider(
              value: _step,
              count: 4,
              labels: const ['小', '标准', '大', '特大'],
              semanticLabel: '字号',
              showTextSizeEnds: true,
              onChanged: (v) => setState(() => _step = v),
            ),
          ),
          const _Pad(LinearProgressIndicator(value: 0.4)),
          const _Header('分类条 · 筛选胶囊'),
          FilterTabs(
            labels: const ['全部', '精彩', '难绷', '玩卡', '旅行', '理财', '败家', '生活'],
            selectedIndex: _filter,
            dividerAfter: 2,
            onSelected: (i) => setState(() => _filter = i),
          ),
          _Pad(
            Wrap(
              spacing: AppSpace.s,
              children: [
                FilterPill(
                  label: '相关度',
                  selected: _pill,
                  onTap: () => setState(() => _pill = !_pill),
                ),
                FilterPill(label: '不限时间', onTap: () {}),
              ],
            ),
          ),
          const _Header('头像 · 头像行'),
          const _Pad(
            Row(
              children: [
                LetterAvatar(name: 'bpllpb'),
                SizedBox(width: AppSpace.m),
                LetterAvatar(name: '陈一一', size: AppSize.avatarM),
                SizedBox(width: AppSpace.m),
                LetterAvatar(name: 'Lucasya', size: AppSize.avatarL),
                SizedBox(width: AppSpace.m),
                UnreadDot(),
              ],
            ),
          ),
          AvatarRow(
            avatar: const LetterAvatar(name: 'Jason'),
            title: const Text('Jason 回复了你：是不是只要手中有钱有时间就不会缺女生'),
            meta: const Text('回复 · 9 小时前'),
            unread: true,
            readState: '未读',
            onTap: () {},
          ),
          const AppHairline(indent: AvatarRow.separatorIndent),
          AvatarRow(
            avatar: const LetterAvatar(name: 'bossdao'),
            title: const Text('bossdao 赞了你的帖子'),
            meta: const Text('点赞 · 昨天'),
            readState: '已读',
            onTap: () {},
          ),
          const _Header('分组列表'),
          SegmentedCardGroupPadding(
            child: SegmentedCardGroup(
              children: [
                ListTile(
                  leading: Icon(
                    AppIcons.palette,
                    color: tokens.colors.brandPrimary,
                  ),
                  title: const Text('图标 + 值 + 箭头'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('默认'),
                      const SizedBox(width: AppSpace.xs),
                      Icon(
                        AppIcons.chevronRight,
                        size: AppSize.iconS,
                        color: tokens.colors.textMeta,
                      ),
                    ],
                  ),
                  onTap: () {},
                ),
                SwitchListTile.adaptive(
                  title: const Text('无图标 + 副标题'),
                  subtitle: const Text('副标题 13 meta'),
                  value: _switch,
                  onChanged: (v) => setState(() => _switch = v),
                ),
                for (var i = 0; i < 2; i++)
                  ListTile(
                    title: Text(i == 0 ? '单选 A' : '单选 B'),
                    trailing: _radio == i
                        ? Icon(
                            AppIcons.check,
                            size: AppSize.iconM,
                            color: tokens.colors.brandPrimary,
                          )
                        : null,
                    onTap: () => setState(() => _radio = i),
                  ),
                ListTile(
                  title: Text(
                    '危险操作',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: tokens.colors.textDestructive),
                  ),
                  onTap: () {},
                ),
              ],
            ),
          ),
          const _Header('浮层'),
          _Pad(
            Wrap(
              spacing: AppSpace.s,
              runSpacing: AppSpace.s,
              children: [
                _GalleryButton('对话框', () => _showDialog(context)),
                _GalleryButton('操作表', () => _showActionSheet(context)),
                _GalleryButton(
                  '本帖通知',
                  () => showNotificationLevelSelectionSheet<int>(
                    context: context,
                    currentLevel: 2,
                    options: [
                      for (final (v, l, d) in const [
                        (3, '关注', '每个新回复都通知'),
                        (2, '跟踪', '显示未读数；被 @ 或被回复时通知'),
                        (1, '常规', '只在被 @ 或被回复时通知'),
                        (0, '静音', '不接收这个话题的任何通知'),
                      ])
                        NotificationLevelOption(
                          value: v,
                          icon: notificationLevelIcon(v),
                          label: l,
                          description: d,
                        ),
                    ],
                    onSelected: (_) {},
                  ),
                ),
                _GalleryButton(
                  'Toast',
                  () => ToastService.showSuccess('链接已复制'),
                ),
                _GalleryButton(
                  '错误 Toast',
                  () => ToastService.showError('没有连上论坛'),
                ),
                _GalleryButton('下载 Toast', _demoDownload),
                AppMenuButton<int>(
                  icon: AppIcons.moreHoriz,
                  semanticLabel: '更多',
                  sectionsBuilder: (_) => [
                    const [
                      AppMenuItem(
                        label: '加入稍后阅读',
                        value: 1,
                        icon: AppIcons.bookmark,
                      ),
                      AppMenuItem(
                        label: 'AI 总结',
                        value: 2,
                        icon: AppIcons.autoAwesome,
                      ),
                      AppMenuItem(
                        label: '导出文章',
                        icon: AppIcons.download,
                        submenu: [
                          [
                            AppMenuItem(label: 'Markdown', value: 31),
                            AppMenuItem(label: 'Notion', value: 32),
                          ],
                        ],
                      ),
                    ],
                    const [
                      AppMenuItem(label: '最新', value: 4, checked: true),
                      AppMenuItem(
                        label: '举报',
                        value: 5,
                        icon: AppIcons.flag,
                        destructive: true,
                      ),
                    ],
                  ],
                  onSelected: (v) => ToastService.showInfo('选了 $v'),
                ),
              ],
            ),
          ),
          _Pad(
            LiftedContextMenu<int>(
              sectionsBuilder: (_) => const [
                [
                  AppMenuItem(label: '回复这层', value: 1, icon: AppIcons.reply),
                  AppMenuItem(label: '复制文字', value: 2, icon: AppIcons.copy),
                ],
                [
                  AppMenuItem(
                    label: '举报',
                    value: 3,
                    icon: AppIcons.flag,
                    destructive: true,
                  ),
                ],
              ],
              onSelected: (v) => ToastService.showInfo('选了 $v'),
              child: Container(
                padding: const EdgeInsets.all(AppSpace.m),
                decoration: BoxDecoration(
                  color: tokens.colors.surfaceGrouped,
                  borderRadius: BorderRadius.circular(tokens.radius.card),
                ),
                child: const Text('长按这里：浮起 + 上下文菜单'),
              ),
            ),
          ),
          const _Header('加载 · 空 / 错'),
          WaitingHint(label: context.l10n.common_waitingForForum),
          const SizedBox(height: 240, child: TopicListSkeleton()),
          SizedBox(
            height: 260,
            child: ErrorView(
              error: Exception('gallery'),
              onRetry: () {},
              showDetails: false,
            ),
          ),
          const SizedBox(
            height: 220,
            child: AppStateView(
              icon: AppIcons.bookmark,
              title: '还没有书签',
              message: '在帖子底部或工具栏点书签图标即可收藏',
            ),
          ),
          PagedListFooter(
            hasMore: true,
            isLoadingMore: false,
            isLoadMoreFailed: true,
            onRetry: () {},
          ),
          PagedListFooter(
            hasMore: false,
            isLoadingMore: false,
            isLoadMoreFailed: false,
            onRetry: () {},
          ),
          const _Header('左滑操作'),
          SwipeActions(
            actions: [
              SwipeActionItem(
                label: '书签',
                icon: AppIcons.bookmark,
                background: tokens.colors.avatarFill,
                foreground: tokens.colors.textPrimary,
                onTap: () => ToastService.showInfo('书签'),
              ),
              SwipeActionItem(
                label: '标为已读',
                icon: AppIcons.checkAll,
                onTap: () => ToastService.showInfo('标为已读'),
              ),
            ],
            child: ColoredBox(
              color: tokens.colors.surfacePage,
              child: const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpace.pageMargin,
                  vertical: AppSpace.m,
                ),
                child: Text('向左滑这一行'),
              ),
            ),
          ),
          const _Header('Tab 胶囊 · 搜索胶囊'),
          _Pad(
            Row(
              children: [
                FloatingTabBar(
                  items: const [
                    FloatingTabItem(icon: AppIcons.home, label: '首页'),
                    FloatingTabItem(
                      icon: AppIcons.notification,
                      label: '通知',
                      showDot: true,
                    ),
                    FloatingTabItem(icon: AppIcons.person, label: '我的'),
                  ],
                  currentIndex: _tab,
                  onTap: (i) => setState(() => _tab = i),
                ),
                const SizedBox(width: AppSpace.m),
                Expanded(
                  child: SearchCapsule(placeholder: '搜索话题', onTap: () {}),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _demoDownload() async {
    final handle = ToastService.showDownload('report.pdf');
    for (var i = 1; i <= 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      handle.updateProgress(i / 10);
    }
    handle.complete('已保存到文件');
  }

  void _showDialog(BuildContext context) {
    showAppDialog<void>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: const Text('退出登录？'),
        content: const Text('本机的草稿、笔记和已存帖子会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.l10n.common_cancel),
          ),
          AppDialogAction.text(
            onPressed: () => Navigator.pop(ctx),
            label: '退出',
            destructive: true,
          ),
        ],
      ),
    );
  }

  void _showActionSheet(BuildContext context) {
    AppBottomSheet.show<void>(
      context: context,
      title: '分享',
      contentPadding: EdgeInsets.zero,
      builder: (ctx) {
        final tokens = ctx.tokens;
        Widget row(IconData icon, String label, {String? detail}) =>
            AppPressable(
              highlight: true,
              onTap: () => Navigator.pop(ctx),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppSize.row48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.pageMargin,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        icon,
                        size: AppSize.iconM,
                        color: tokens.colors.textPrimary,
                      ),
                      const SizedBox(width: AppSpace.m),
                      Expanded(
                        child: Text(
                          label,
                          style: Theme.of(ctx).textTheme.bodyLarge,
                        ),
                      ),
                      if (detail != null)
                        Text(detail, style: Theme.of(ctx).textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            );
        const divider = AppHairline(
          indent: AppSpace.pageMargin,
          endIndent: AppSpace.pageMargin,
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            row(AppIcons.copy, '复制链接'),
            divider,
            row(AppIcons.image, '生成分享图片'),
            divider,
            row(AppIcons.article, '导出文章', detail: 'Markdown · Notion'),
            divider,
            row(AppIcons.openInNew, '用浏览器打开'),
            divider,
            row(AppIcons.share, '更多…', detail: '系统分享'),
          ],
        );
      },
    );
  }
}

/// 分组列表左右 20
class SegmentedCardGroupPadding extends StatelessWidget {
  const SegmentedCardGroupPadding({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpace.pageMargin),
    child: child,
  );
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.x32,
        AppSpace.xxl,
        AppSpace.x32,
        AppSpace.s,
      ),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall!
              .merge(tokens.text.meta)
              .copyWith(color: tokens.colors.textMeta),
        ),
      ),
    );
  }
}

class _Pad extends StatelessWidget {
  const _Pad(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpace.pageMargin,
      vertical: AppSpace.s,
    ),
    child: child,
  );
}

class _GalleryButton extends StatelessWidget {
  const _GalleryButton(this.label, this.onPressed);

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
    style: AppButtonStyles.secondary(context),
    onPressed: onPressed,
    child: Text(label),
  );
}

class _ColorSwatches extends StatelessWidget {
  const _ColorSwatches({required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final entries = <(String, Color)>[
      ('brand/primary', colors.brandPrimary),
      ('brand/button', colors.brandButton),
      ('text/primary', colors.textPrimary),
      ('text/meta', colors.textMeta),
      ('text/destructive', colors.textDestructive),
      ('surface/page', colors.surfacePage),
      ('surface/grouped', colors.surfaceGrouped),
      ('surface/elevated', colors.surfaceElevated),
      ('separator', colors.separator),
      ('quote/rule', colors.quoteRule),
      ('avatar/fill', colors.avatarFill),
    ];
    final style = Theme.of(context).textTheme.labelSmall!
        .merge(context.tokens.text.caption)
        .copyWith(color: colors.textMeta);
    return _Pad(
      Wrap(
        spacing: AppSpace.m,
        runSpacing: AppSpace.m,
        children: [
          for (final (name, color) in entries)
            SizedBox(
              width: 88,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(
                        context.tokens.radius.table,
                      ),
                      border: Border.all(
                        color: colors.separator,
                        width: AppSpace.hairline,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(name, style: style),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TextSamples extends StatelessWidget {
  const _TextSamples();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final base = Theme.of(context).textTheme.bodyMedium!
        .copyWith(color: tokens.colors.textPrimary);
    return _Pad(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('22 Semibold 主题标题', style: base.merge(tokens.text.title)),
          Text('17 Semibold 列表标题', style: base.merge(tokens.text.headline)),
          Text(
            '17 Regular 正文，行高跟着行高档走。坛友们，今年有拿到 Chase retention offer 的吗？',
            style: base.merge(tokens.text.body),
          ),
          Text(
            '13 Regular 元信息',
            style: base
                .merge(tokens.text.meta)
                .copyWith(color: tokens.colors.textMeta),
          ),
          Text(
            '11 Regular 标签 @handle',
            style: base
                .merge(tokens.text.caption)
                .copyWith(color: tokens.colors.textMeta),
          ),
        ],
      ),
    );
  }
}
