import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/dev/ui_gallery_page.dart';
import 'package:fluxdo/utils/dialog_utils.dart';
import 'package:fluxdo/widgets/common/app_bottom_sheet.dart';
import 'package:fluxdo/widgets/common/error_view.dart';
import 'package:m3e_ui/m3e_ui.dart';

import 'support/ui_harness.dart';

// 0.4.0 M2：v2 共享组件与共用外壳（计划 §4、§5 M2、§8、§9）。
// 组件样本页跑全矩阵（浅 / 深 × 1.0 / 1.3 / 2.0 × 440 / 393）不溢出，
// 再逐个断言关键尺寸、颜色和朗读。

AppColors _colors(Brightness b) => AppColors.resolve(b, AccentPreset.meika);

/// 把页面滚到底，每一屏都检查异常；设了 SHOTS_DIR 时出图
Future<void> _scrollThrough(
  WidgetTester tester,
  String label, {
  bool shots = false,
  bool a11y = false,
}) async {
  final list = find.byType(Scrollable).first;
  for (var page = 0; page < 30; page++) {
    expectNoUiException(tester);
    if (a11y) await expectUiAccessibility(tester, textContrast: false);
    if (shots) await uiShot(tester, 'm2_gallery_${label}_p$page');
    final position = tester.state<ScrollableState>(list).position;
    if (position.pixels >= position.maxScrollExtent) break;
    position.jumpTo(
      (position.pixels + position.viewportDimension * 0.8).clamp(
        0,
        position.maxScrollExtent,
      ),
    );
    // 页里有一直在转的系统菊花，等不到 settle：按帧推进
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  setUpAll(loadUiFonts);

  group('组件样本页', () {
    for (final variant in UiVariant.portrait) {
      testUi('全部组件不溢出（${variant.label}）', (tester) async {
        await pumpUi(
          tester,
          const UiGalleryPage(),
          variant: variant,
          settle: false,
        );
        await tester.pump(const Duration(milliseconds: 300));
        final shots =
            variant.textScale != 1.3 || variant.device == UiDevice.proMax;
        await _scrollThrough(tester, variant.label, shots: shots);
      });
    }

    for (final b in Brightness.values) {
      testUi('无障碍三条 guideline（${b.name}）', (tester) async {
        await pumpUi(
          tester,
          const UiGalleryPage(),
          variant: UiVariant(b, 1, UiDevice.proMax),
          settle: false,
        );
        await tester.pump(const Duration(milliseconds: 300));
        await _scrollThrough(tester, 'a11y_${b.name}', a11y: true);
      });
    }
  });

  group('按钮', () {
    for (final b in Brightness.values) {
      testUi('主按钮 brand/button 白字、次按钮 avatar/fill（${b.name}）', (tester) async {
        late BuildContext ctx;
        await pumpUi(
          tester,
          Scaffold(
            body: Builder(
              builder: (context) {
                ctx = context;
                return Column(
                  children: [
                    FilledButton(onPressed: () {}, child: const Text('主要')),
                    FilledButton(
                      style: AppButtonStyles.secondary(context),
                      onPressed: () {},
                      child: const Text('次要'),
                    ),
                    OutlinedButton(onPressed: () {}, child: const Text('描边')),
                  ],
                );
              },
            ),
          ),
          variant: UiVariant(b, 1, UiDevice.proMax),
        );
        final c = _colors(b);
        Color bg(String text) => tester
            .widget<Material>(
              find
                  .ancestor(
                    of: find.text(text),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .color!;
        expect(bg('主要'), c.brandButton);
        expect(
          DefaultTextStyle.of(tester.element(find.text('主要'))).style.color,
          c.onBrandButton,
        );
        expect(bg('次要'), c.avatarFill);
        expect(bg('描边'), c.avatarFill);
        expect(tester.getSize(find.byType(FilledButton).first).height, 44);
        expect(ctx.tokens.brightness, b);
      });
    }
  });

  group('导航栏', () {
    testUi('44 高 + 状态栏，标题居中，返回按钮朗读「返回」，标题字号封顶 1.3', (tester) async {
      await pumpUi(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppNavBar(
                        title: '阅读设置',
                        trailing: [
                          AppIconButton(
                            icon: AppIcons.moreHoriz,
                            semanticLabel: '更多',
                            onPressed: () {},
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        variant: const UiVariant(Brightness.light, 2, UiDevice.proMax),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final bar = tester.getRect(find.byType(AppNavBar));
      expect(bar.height, 44 + 62);
      // 标题在两槽之间居中：内容区是 16…420（pad 0 20 0 16），中心 218，
      // 和 Figma「导航 · 单行」一致
      expect(tester.getCenter(find.text('阅读设置')).dx, closeTo(218, 0.5));
      // 字号 2.0 时标题只放大到 1.3 倍
      final title = tester.renderObject<RenderParagraph>(find.text('阅读设置'));
      expect(title.textScaler.scale(17), closeTo(17 * 1.3, 0.01));
      expect(find.bySemanticsLabel('返回'), findsOneWidget);
      expect(find.bySemanticsLabel('更多'), findsOneWidget);
      // 返回图标视觉左缘 16，热区 44
      expect(
        tester.getTopLeft(find.byIcon(AppIcons.back)).dx,
        closeTo(16, 0.5),
      );
      expect(
        tester.getSize(
          find
              .ancestor(
                of: find.byIcon(AppIcons.back),
                matching: find.byType(SizedBox),
              )
              .first,
        ),
        const Size(44, 44),
      );
      // 右侧 more 的视觉右缘对齐页边距 20
      expect(
        tester.getTopRight(find.byIcon(AppIcons.moreHoriz)).dx,
        closeTo(440 - 20, 0.5),
      );
      expectNoUiException(tester);
    });
  });

  group('对话框', () {
    for (final b in Brightness.values) {
      testUi('宽 320、r16、半屏底色；按钮行 44，破坏性按钮红字（${b.name}）', (tester) async {
        await pumpUi(
          tester,
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showAppDialog<void>(
                    context: context,
                    builder: (ctx) => AppAlertDialog(
                      title: const Text('退出登录？'),
                      content: const Text('本机的草稿、笔记和已存帖子会保留。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('取消'),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Theme.of(ctx).colorScheme.error,
                          ),
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('退出'),
                        ),
                      ],
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          variant: UiVariant(b, 1, UiDevice.proMax),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await uiShot(tester, 'm2_dialog_${b.name}');

        final c = _colors(b);
        final dialog = tester.widget<Dialog>(find.byType(Dialog));
        expect(
          dialog.backgroundColor,
          b == Brightness.dark ? c.surfaceGrouped : c.surfacePage,
        );
        expect(
          dialog.shape,
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        );
        expect(
          tester
              .getSize(
                find
                    .descendant(
                      of: find.byType(Dialog),
                      matching: find.byType(Material),
                    )
                    .first,
              )
              .width,
          320,
        );
        // 遮罩 32%，不模糊
        expect(find.byType(BackdropFilter), findsNothing);
        final barrier = tester.widget<ModalBarrier>(
          find.byType(ModalBarrier).last,
        );
        expect(barrier.color, AppMaterials.scrim);

        // 旧 TextButton 被拆成对话框按钮：44 高，破坏性的是红字
        expect(find.byType(TextButton), findsOneWidget); // 只剩 open
        expect(tester.getSize(find.byType(AppDialogAction).first).height, 44);
        Color textColor(String text) =>
            DefaultTextStyle.of(tester.element(find.text(text))).style.color!;
        expect(textColor('取消'), c.brandPrimary);
        expect(textColor('退出'), c.textDestructive);
        // 标题 17 Semibold、说明 13 meta，都居中
        final title = DefaultTextStyle.of(tester.element(find.text('退出登录？')));
        expect(title.style.fontSize, 17);
        expect(title.style.fontWeight, FontWeight.w600);
        expect(title.textAlign, TextAlign.center);
        final body = DefaultTextStyle.of(
          tester.element(find.text('本机的草稿、笔记和已存帖子会保留。')),
        );
        expect(body.style.fontSize, 13);
        expect(body.style.color, c.textMeta);

        // 语义：对话框是一个有名字的路由
        expect(
          tester.getSemantics(find.byType(AppAlertDialog)),
          isSemantics(label: '退出登录？', scopesRoute: true, namesRoute: true),
        );
        await expectUiAccessibility(tester, textContrast: false);

        await tester.tap(find.text('退出'));
        await tester.pumpAndSettle();
        expect(find.byType(AppAlertDialog), findsNothing);
      });
    }
  });

  group('半屏', () {
    for (final b in Brightness.values) {
      testUi('底色、16 顶角、拖拽条、左对齐标题 + 关闭；里面的分组用 elevated（${b.name}）', (
        tester,
      ) async {
        await pumpUi(
          tester,
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => AppBottomSheet.show<void>(
                    context: context,
                    title: '分享',
                    builder: (_) => const SegmentedCardGroup(
                      children: [
                        ListTile(
                          leading: Icon(AppIcons.copy),
                          title: Text('复制链接'),
                        ),
                        ListTile(
                          leading: Icon(AppIcons.image),
                          title: Text('生成分享图片'),
                        ),
                      ],
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          variant: UiVariant(b, 1, UiDevice.proMax),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await uiShot(tester, 'm2_sheet_${b.name}');

        final c = _colors(b);
        final shell = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(AppSheetScaffold),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(
          shell.color,
          b == Brightness.dark ? c.surfaceGrouped : c.surfacePage,
        );
        expect(
          shell.borderRadius,
          const BorderRadius.vertical(top: Radius.circular(16)),
        );
        final group = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(SegmentedCardGroup),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(group.color, c.surfaceElevated);
        expect(tester.getTopLeft(find.text('分享')).dx, 20);
        expect(
          tester.getSemantics(find.byType(AppCloseButton)),
          isSemantics(label: '关闭', isButton: true, hasTapAction: true),
        );
        // 遮罩 32%
        final barrier = tester.widget<ModalBarrier>(
          find.byType(ModalBarrier).last,
        );
        expect(barrier.color, AppMaterials.scrim);
        // 语义：外壳（Material 往上第一个节点）用标题命名路由
        expect(
          tester.getSemantics(
            find
                .descendant(
                  of: find.byType(AppSheetScaffold),
                  matching: find.byType(Material),
                )
                .first,
          ),
          isSemantics(label: '分享', scopesRoute: true, namesRoute: true),
        );
        await expectUiAccessibility(tester, textContrast: false);

        await tester.tap(find.byType(AppCloseButton));
        await tester.pumpAndSettle();
        expect(find.byType(AppSheetScaffold), findsNothing);
      });
    }
  });

  group('菜单', () {
    testUi('锚点在右半边时右对齐、在下方；子菜单原位切换；选中返回值', (tester) async {
      int? picked;
      await pumpUi(
        tester,
        Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 80, right: 10),
              child: AppMenuButton<int>(
                icon: AppIcons.moreHoriz,
                semanticLabel: '更多',
                sectionsBuilder: (_) => const [
                  [
                    AppMenuItem(
                      label: '加入稍后阅读',
                      value: 1,
                      icon: AppIcons.bookmark,
                    ),
                    AppMenuItem(
                      label: '导出文章',
                      icon: AppIcons.download,
                      submenu: [
                        [AppMenuItem(label: 'Markdown', value: 31)],
                      ],
                    ),
                  ],
                  [AppMenuItem(label: '举报', value: 5, destructive: true)],
                ],
                onSelected: (v) => picked = v,
              ),
            ),
          ),
        ),
      );
      final anchor = tester.getRect(find.bySemanticsLabel('更多'));
      await tester.tap(find.bySemanticsLabel('更多'));
      await tester.pumpAndSettle();
      final panel = tester.getRect(find.byType(AppMenuPanel<int>));
      expect(panel.width, 240);
      expect(panel.top, closeTo(anchor.bottom + 4, 0.5));
      // 右缘：锚点右缘和页边距 20 里取能放下的那个
      expect(panel.right, lessThanOrEqualTo(440 - 20 + 0.5));
      final row = find.ancestor(
        of: find.text('加入稍后阅读'),
        matching: find.byType(AppPressable),
      );
      expect(tester.getSize(row).height, greaterThanOrEqualTo(44));
      expect(
        tester.widget<Text>(find.text('举报')).style!.color,
        _colors(Brightness.light).textDestructive,
      );
      await uiShot(tester, 'm2_menu_light');

      await tester.tap(find.text('导出文章'));
      await tester.pumpAndSettle();
      expect(find.text('Markdown'), findsOneWidget);
      expect(find.text('加入稍后阅读'), findsNothing);
      await tester.tap(find.text('Markdown'));
      await tester.pumpAndSettle();
      expect(picked, 31);
      expect(find.byType(AppMenuPanel<int>), findsNothing);
    });

    testUi('长按浮起：遮罩 + 模糊，卡片和菜单都在屏内', (tester) async {
      int? picked;
      await pumpUi(
        tester,
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.only(top: 700, left: 20, right: 20),
            child: LiftedContextMenu<int>(
              sectionsBuilder: (_) => const [
                [
                  AppMenuItem(label: '回复这层', value: 1),
                  AppMenuItem(label: '复制文字', value: 2),
                  AppMenuItem(label: '添加笔记', value: 3),
                ],
              ],
              onSelected: (v) => picked = v,
              child: const SizedBox(height: 120, child: Text('楼层内容')),
            ),
          ),
        ),
      );
      await tester.longPress(find.text('楼层内容'));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsOneWidget);
      final menu = tester.getRect(find.byType(AppMenuPanel<int>));
      expect(menu.width, 260);
      expect(menu.bottom, lessThanOrEqualTo(956 - 34 - 20 + 0.5));
      // 菜单在浮起卡片下方 8（卡片被往上推了）
      final card = tester.getRect(find.text('楼层内容').last);
      expect(menu.top, greaterThan(card.top));
      expect(find.text('楼层内容'), findsNWidgets(2));
      await uiShot(tester, 'm2_lifted_light');
      await tester.tap(find.text('复制文字'));
      await tester.pumpAndSettle();
      expect(picked, 2);
    });
  });

  group('筛选', () {
    testUi('分类条项热区 ≥ 44，选中项朗读为选中，字号封顶', (tester) async {
      var selected = 0;
      await pumpUi(
        tester,
        StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: SafeArea(
              child: FilterTabs(
                labels: const ['全部', '精彩', '难绷'],
                selectedIndex: selected,
                onSelected: (i) => setState(() => selected = i),
              ),
            ),
          ),
        ),
        variant: const UiVariant(Brightness.light, 2, UiDevice.pro),
      );
      for (final label in ['全部', '精彩', '难绷']) {
        final item = find.ancestor(
          of: find.text(label),
          matching: find.byType(AppPressable),
        );
        expect(tester.getSize(item).height, greaterThanOrEqualTo(44));
        expect(tester.getSize(item).width, greaterThanOrEqualTo(44));
      }
      await tester.tap(find.text('精彩'));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(
          find.ancestor(
            of: find.text('精彩'),
            matching: find.byType(AppPressable),
          ),
        ),
        isSemantics(
          label: '精彩',
          isButton: true,
          isSelected: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      final text = tester.renderObject<RenderParagraph>(find.text('精彩'));
      expect(text.textScaler.scale(13), closeTo(13 * 1.3, 0.01));
      expectNoUiException(tester);
    });
  });

  group('档位滑块', () {
    testUi('朗读为滑块，上下轻扫 ±1 档；点按轨道跳档', (tester) async {
      var value = 1;
      await pumpUi(
        tester,
        StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: StepSlider(
                  value: value,
                  count: 4,
                  labels: const ['小', '标准', '大', '特大'],
                  semanticLabel: '字号',
                  onChanged: (v) => setState(() => value = v),
                ),
              ),
            ),
          ),
        ),
      );
      final semantics = tester.getSemantics(find.byType(StepSlider));
      expect(
        semantics,
        isSemantics(
          label: '字号',
          value: '标准',
          increasedValue: '大',
          decreasedValue: '小',
          isSlider: true,
          hasIncreaseAction: true,
          hasDecreaseAction: true,
        ),
      );
      tester.semantics.performAction(
        find.semantics.byLabel('字号'),
        SemanticsAction.increase,
      );
      await tester.pumpAndSettle();
      expect(value, 2);
      final track = tester.getRect(
        find
            .descendant(
              of: find.byType(StepSlider),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      await tester.tapAt(Offset(track.right - 2, track.center.dy));
      await tester.pumpAndSettle();
      expect(value, 3);
    });
  });

  group('加载', () {
    testUi('200ms 内不出骨架，之后出骨架，3 秒后加等待提示', (tester) async {
      await pumpUi(
        tester,
        const Scaffold(
          body: DelayedLoading(
            skeleton: SizedBox(height: 100, child: Text('骨架')),
            waitingLabel: '正在等待论坛响应',
          ),
        ),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('骨架'), findsNothing);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('骨架'), findsOneWidget);
      expect(find.byType(WaitingHint), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(WaitingHint), findsOneWidget);
      expect(find.text('骨架'), findsOneWidget);
      expect(tester.getSize(find.byType(WaitingHint)).height, 44);
      await tester.pumpWidget(const SizedBox());
    });

    testUi('原地错误：标题、说明、44 高次按钮「重试」，不再有「查看详情」', (tester) async {
      var retried = false;
      await pumpUi(
        tester,
        Scaffold(
          body: ErrorView(
            error: Exception('boom'),
            onRetry: () => retried = true,
            showDetails: false,
          ),
        ),
      );
      expect(find.text('查看详情'), findsNothing);
      final retry = find.widgetWithText(FilledButton, '重试');
      expect(retry, findsOneWidget);
      expect(tester.getSize(retry).height, 44);
      final bg = tester
          .widget<Material>(
            find.descendant(of: retry, matching: find.byType(Material)).first,
          )
          .color;
      expect(bg, _colors(Brightness.light).avatarFill);
      await tester.tap(retry);
      expect(retried, isTrue);
      await expectUiAccessibility(tester, textContrast: false);
    });
  });

  group('左滑操作', () {
    testUi('左滑露出 72 宽按钮；收起时向右拖不响应；按钮注册成自定义操作', (tester) async {
      var bookmarked = 0;
      await pumpUi(
        tester,
        Scaffold(
          body: ListView(
            children: [
              SwipeActions(
                actions: [
                  SwipeActionItem(label: '书签', onTap: () => bookmarked++),
                  SwipeActionItem(label: '标为已读', onTap: () {}),
                ],
                child: const SizedBox(height: 72, child: Text('话题行')),
              ),
            ],
          ),
        ),
      );
      final rowLeft = tester.getTopLeft(find.text('话题行')).dx;
      // 向右拖：不动（留给侧滑返回）
      await tester.drag(find.text('话题行'), const Offset(120, 0));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('话题行')).dx, rowLeft);
      // 向左拖：展开 2 × 72
      await tester.drag(find.text('话题行'), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('话题行')).dx, rowLeft - 144);
      expect(
        tester
            .getSize(
              find
                  .ancestor(
                    of: find.text('书签'),
                    matching: find.byType(SizedBox),
                  )
                  .first,
            )
            .width,
        72,
      );
      await tester.tap(find.text('书签'));
      await tester.pumpAndSettle();
      expect(bookmarked, 1);
      expect(tester.getTopLeft(find.text('话题行')).dx, rowLeft);

      final node = tester.getSemantics(find.byType(SwipeActions));
      final actions = node.getSemanticsData().customSemanticsActionIds!;
      expect(actions, hasLength(2));
    });
  });

  group('阅读列', () {
    for (final (device, expected) in [
      (UiDevice.proMax, 20.0),
      (UiDevice.landscape, (956 - 640) / 2 + 20),
      (UiDevice.landscapePro, (852 - 640) / 2 + 20),
    ]) {
      testUi('readableInsets：${device.name} 左右 $expected', (tester) async {
        late EdgeInsets insets;
        await pumpUi(
          tester,
          Builder(
            builder: (context) {
              insets = readableInsets(context);
              return const SizedBox();
            },
          ),
          variant: UiVariant(Brightness.light, 1, device),
        );
        expect(insets.left, expected);
        expect(insets.right, expected);
      });
    }
  });

  group('Tab 胶囊与搜索胶囊', () {
    testUi('58 高胶囊；Tab 项 62 宽，字号 2.0 时高度不变', (tester) async {
      await pumpUi(
        tester,
        Scaffold(
          body: Center(
            child: Row(
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
                  currentIndex: 0,
                  onTap: (_) {},
                ),
                Expanded(
                  child: SearchCapsule(placeholder: '搜索话题', onTap: () {}),
                ),
              ],
            ),
          ),
        ),
        variant: const UiVariant(Brightness.dark, 2, UiDevice.proMax),
      );
      expect(tester.getSize(find.byType(FloatingTabBar)).height, 58);
      expect(tester.getSize(find.byType(SearchCapsule)).height, 58);
      expect(
        tester.getSemantics(
          find.ancestor(
            of: find.text('首页'),
            matching: find.byType(AppPressable),
          ),
        ),
        isSemantics(
          label: '首页',
          isButton: true,
          isSelected: true,
          isEnabled: true,
          hasTapAction: true,
          isInMutuallyExclusiveGroup: true,
        ),
      );
      expectNoUiException(tester);
      await uiShot(tester, 'm2_capsules_dark_2x');
    });
  });
}
