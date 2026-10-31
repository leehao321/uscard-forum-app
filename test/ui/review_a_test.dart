import 'dart:convert';
import 'dart:io';

import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/navigation/nav_action_bus.dart' show NavEntryIds;
import 'package:fluxdo/navigation/nav_entry_registry.dart';
import 'package:fluxdo/utils/responsive.dart';
import 'package:fluxdo/widgets/layout/master_detail_layout.dart';

import 'support/ui_harness.dart';

// 审阅核实 A（Gemini 报告 S-3 ~ S-7、D-10）：每条问题一个会在旧代码上失败的测试。
// 数据全是假的，不请求论坛。

Widget _probe(void Function(BuildContext) read) => Builder(
  builder: (context) {
    read(context);
    return const SizedBox.shrink();
  },
);

void main() {
  setUpAll(loadUiFonts);

  group('S-3 手机横屏按手机处理（短边 < 600）', () {
    for (final device in [UiDevice.landscape, UiDevice.landscapePro]) {
      testUi('${device.name} 是手机，不进双栏、不出侧栏', (tester) async {
        late DeviceType type;
        late bool both;
        late bool rail;
        await pumpUi(
          tester,
          _probe((c) {
            type = Responsive.getDeviceType(c);
            both = MasterDetailLayout.canShowBothPanesFor(c);
            rail = Responsive.showNavigationRail(c);
          }),
          variant: UiVariant(Brightness.light, 1, device),
        );
        expect(type, DeviceType.mobile);
        expect(both, isFalse);
        expect(rail, isFalse);
      });
    }

    testUi('宽屏平板（短边 ≥ 600）仍是平板', (tester) async {
      late DeviceType type;
      await pumpUi(
        tester,
        _probe((c) => type = Responsive.getDeviceType(c)),
      );
      // pumpUi 按手机设了屏幕尺寸，这里改成 iPad 横屏再量一次
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size(1024 * 2, 768 * 2);
      addTearDown(tester.view.reset);
      await tester.pump();
      expect(type, DeviceType.tablet);
    });
  });

  group('S-4 浮起菜单在横屏不被裁掉、避开安全区', () {
    testUi('956×440：12 项菜单底边在屏内，左缘让开刘海', (tester) async {
      const device = UiDevice.landscape;
      await pumpUi(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                // 贴着左边：不让开安全区就会进刘海
                padding: const EdgeInsets.only(top: 150),
                child: LiftedContextMenu<int>(
                  sectionsBuilder: (_) => [
                    [
                      for (var i = 0; i < 12; i++)
                        AppMenuItem(label: '菜单项 $i', value: i),
                    ],
                  ],
                  child: const SizedBox(
                    width: 300,
                    height: 120,
                    child: Text('楼层内容'),
                  ),
                ),
              ),
            ),
          ),
        ),
        variant: const UiVariant(Brightness.light, 1, device),
      );
      await tester.longPress(find.text('楼层内容'));
      await tester.pumpAndSettle();
      final menu = tester.getRect(find.byType(AppMenuPanel<int>));
      final screen = device.size;
      final padding = device.padding;
      expect(menu.bottom, lessThanOrEqualTo(screen.height - padding.bottom));
      expect(menu.left, greaterThanOrEqualTo(padding.left + AppSpace.pageMargin));
      // 放不下的菜单项在菜单里滚动，而不是掉出屏幕
      expect(tester.takeException(), isNull);
    });
  });

  group('S-5 Firebase 占位配置在仓库里', () {
    test('google-services.json 被 git 跟踪，且是占位内容', () {
      final file = File('android/app/google-services.json');
      expect(file.existsSync(), isTrue);
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect((json['project_info'] as Map)['project_id'], 'dummy-project-id');
      final tracked = Process.runSync('git', [
        'ls-files',
        'android/app/google-services.json',
      ]);
      expect((tracked.stdout as String).trim(), isNotEmpty);
    });
  });

  group('S-6 导航栏右槽放得下多个按钮', () {
    for (final count in [2, 3]) {
      testUi('393 宽右侧 $count 个按钮不溢出，图标视觉间距 24', (tester) async {
        await pumpUi(
          tester,
          Scaffold(
            appBar: AppNavBar(
              title: '书签',
              trailing: [
                for (var i = 0; i < count; i++)
                  AppIconButton(
                    key: ValueKey('btn$i'),
                    icon: AppIcons.search,
                    semanticLabel: '按钮 $i',
                    onPressed: () {},
                  ),
              ],
            ),
          ),
          variant: const UiVariant(Brightness.light, 1, UiDevice.pro),
        );
        expect(tester.takeException(), isNull);
        final a = tester.getCenter(find.byKey(const ValueKey('btn0')));
        final b = tester.getCenter(find.byKey(const ValueKey('btn1')));
        // 图标 24、中心距 = 24 + 24 = 48
        expect(b.dx - a.dx, 48);
        // 标题仍然居中
        final title = tester.getCenter(find.text('书签'));
        // 设计的左右内边距是 16 / 20，标题比屏幕中线偏 2
        expect(title.dx, closeTo(UiDevice.pro.size.width / 2, 3));
      });
    }
  });

  group('S-7 393 宽底栏里搜索胶囊不截断成「…」', () {
    Future<void> pumpBar(WidgetTester tester, int tabs) => pumpUi(
      tester,
      Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                FloatingTabBar(
                  items: [
                    for (var i = 0; i < tabs; i++)
                      FloatingTabItem(icon: AppIcons.home, label: '首页'),
                  ],
                  currentIndex: 0,
                  onTap: (_) {},
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SearchCapsule(
                    placeholder: '搜索话题',
                    compactPlaceholder: '搜索',
                    onTap: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      variant: const UiVariant(Brightness.light, 1, UiDevice.pro),
    );

    testUi('3 个标签：完整显示「搜索话题」', (tester) async {
      await pumpBar(tester, 3);
      expect(tester.takeException(), isNull);
      expect(find.text('搜索话题'), findsOneWidget);
    });

    testUi('4 个标签：收成「搜索」或只留放大镜，不出现被省略的文字', (tester) async {
      await pumpBar(tester, 4);
      expect(tester.takeException(), isNull);
      expect(find.text('搜索话题'), findsNothing);
      // 放得下「搜索」就显示，放不下只剩图标，绝不是被省略号截断的半截文字
      final compact = find.text('搜索');
      if (compact.evaluate().isNotEmpty) {
        final text = tester.widget<Text>(compact);
        final box = tester.renderObject<RenderParagraph>(compact);
        expect(box.didExceedMaxLines, isFalse);
        expect(text.overflow, TextOverflow.ellipsis);
      }
      expect(find.byIcon(AppIcons.search), findsOneWidget);
    });
  });

  group('D-10 未登录也有通知 Tab', () {
    test('通知入口不需要登录，未登录时仍在可用列表里', () {
      final entry = NavEntryRegistry.byId(NavEntryIds.notifications)!;
      expect(entry.requiresLogin, isFalse);
      expect(NavEntryRegistry.isAvailable(entry, null), isTrue);
    });
  });
}
