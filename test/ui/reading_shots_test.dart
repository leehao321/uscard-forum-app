import 'dart:async';

import 'package:ai_model_manager/ai_model_manager.dart'
    show aiSharedPreferencesProvider;
import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/reading_toolbar.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/topic_detail_header.dart';
import 'package:fluxdo/providers/category_provider.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/message_bus/topic_tracking_providers.dart';
import 'package:fluxdo/providers/theme_provider.dart'
    show sharedPreferencesProvider;
import 'package:fluxdo/widgets/post/post_item/post_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fixtures.dart';
import 'support/ui_harness.dart';

// 0.4.0 M4/M5：阅读页由真实组件（导航栏 + 主题头 + 楼层 + 工具栏）拼出，
// 不请求论坛，数据全是夹具。设了 SHOTS_DIR 时出图，对照 Figma 3:17 / 62:1483。

class _FakeUser extends CurrentUserNotifier {
  @override
  FutureOr<User?> build() => null;
}

class _FakeTracking extends TopicTrackingStateNotifier {
  @override
  Map<int, TrackedTopicState> build() => const {};
}

class _FakeMessageBusInit extends MessageBusInitNotifier {
  @override
  void build() {}
}

List<Override> _overrides(SharedPreferences prefs) => [
  sharedPreferencesProvider.overrideWithValue(prefs),
  aiSharedPreferencesProvider.overrideWithValue(prefs),
  categoriesProvider.overrideWith((ref) async => fixtureCategories()),
  currentUserProvider.overrideWith(_FakeUser.new),
  messageBusInitProvider.overrideWith(_FakeMessageBusInit.new),
  topicTrackingStateProvider.overrideWith(_FakeTracking.new),
];

void main() {
  setUpAll(loadUiFonts);

  for (final variant in [
    UiVariant.lightDefault,
    const UiVariant(Brightness.dark, 1, UiDevice.proMax),
    const UiVariant(Brightness.light, 1.3, UiDevice.pro),
    ...UiVariant.landscape,
  ]) {
    testUi('阅读页（${variant.label}）', (tester) async {
      final prevOnError = FlutterError.onError;
      FlutterError.onError = (d) {
        debugPrint(d.toString());
        prevOnError!(d);
      };
      addTearDown(() => FlutterError.onError = prevOnError);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final detail = fixtureTopicDetail();
      final posts = detail.postStream.posts;
      final floor = ValueNotifier(2);
      await pumpUi(
        tester,
        Scaffold(
          body: Stack(
            children: [
              Column(
                children: [
                  AppNavBar(
                    title: '',
                    slotWidth: 100,
                    showDivider: true,
                    trailing: [
                      AppIconButton(
                        icon: AppIcons.search,
                        semanticLabel: '搜索',
                        onPressed: () {},
                      ),
                      AppIconButton(
                        icon: AppIcons.moreHoriz,
                        semanticLabel: '更多',
                        onPressed: () {},
                      ),
                    ],
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 120),
                      children: [
                        ReadableColumn(
                          child: TopicDetailHeader(detail: detail),
                        ),
                        for (final p in posts.take(4))
                          ReadableColumn(
                            child: PostItem(
                              post: p,
                              topicId: detail.id,
                              isTopicOwner: p.postNumber == 1,
                              onReply: ({String? initialContent}) {},
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ReadingToolbar(
                  expandedListenable: ValueNotifier(true),
                  floorListenable: floor,
                  total: posts.length,
                  isLoggedIn: true,
                  bookmarked: false,
                  notificationIcon: AppIcons.notification,
                  onReply: () {},
                  onNotification: () {},
                  onBookmark: () {},
                  onShare: () {},
                  onOpenFloorJump: () {},
                ),
              ),
            ],
          ),
        ),
        variant: variant,
        overrides: _overrides(prefs),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      final ex = tester.takeException();
      if (ex is FlutterError) debugPrint(ex.toStringDeep());
      expect(ex, isNull);
      await uiShot(tester, 'reading_${variant.label}');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  for (final byLongPress in [true, false]) {
    testUi('${byLongPress ? '长按楼层头部浮起' : '点 ⋯'}弹出同一份菜单', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final detail = fixtureTopicDetail();
      await pumpUi(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: PostItem(
              post: detail.postStream.posts.first,
              topicId: detail.id,
              onReply: ({String? initialContent}) {},
            ),
          ),
        ),
        overrides: _overrides(prefs),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('分享链接'), findsNothing);

      if (byLongPress) {
        await tester.longPress(find.text('张三'));
      } else {
        await tester.tap(find.byIcon(AppIcons.moreHoriz));
      }
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('分享链接'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppMenuPanel<VoidCallback>),
          matching: find.text('回复'),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  testUi('设计说明 §2.3 / §2.4 / §3.2 的尺寸逐项对', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final detail = fixtureTopicDetail();
    await pumpUi(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              TopicDetailHeader(detail: detail),
              PostItem(
                post: detail.postStream.posts.first,
                topicId: detail.id,
                isTopicOwner: true,
              ),
            ],
          ),
        ),
      ),
      overrides: _overrides(prefs),
      settle: false,
    );
    await tester.pump(const Duration(milliseconds: 500));
    expectNoUiException(tester);

    // 主题头：标题 22 Semibold；元信息 13；左右边距 20
    final title = tester.widget<SelectableText>(
      find.byWidgetPredicate((w) => w is SelectableText && w.textSpan != null),
    );
    expect(title.textSpan!.style!.fontSize, 22);
    expect(title.textSpan!.style!.fontWeight, FontWeight.w600);
    final headerLeft = tester.getTopLeft(find.byType(SelectableText).first).dx;
    expect(headerLeft, 20);
    final hairline = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).border is Border,
    );
    expect(hairline, findsWidgets);
    Text metaText(String t) => tester.widget<Text>(find.text(t).first);
    expect(metaText('7').style!.fontSize, 13);

    // 楼层：头像 34；名字 13 Semibold；@handle 11；正文 17 / 行高 1.75
    expect(
      tester.allRenderObjects.whereType<RenderBox>().any(
        (b) => b.hasSize && b.size == const Size(34, 34),
      ),
      isTrue,
    );
    expect(metaText('张三').style!.fontSize, 13);
    expect(metaText('张三').style!.fontWeight, FontWeight.w600);
    expect(metaText('@chase_fan').style!.fontSize, 11);
    expect(metaText('#1').style!.fontSize, 13);
    // 名字左缘 = 20（边距）+ 34（头像）+ 8
    expect(tester.getTopLeft(find.text('张三')).dx, 62);
    // 「#1」和日期在同一行
    expect(
      tester.getTopLeft(find.text('#1')).dy,
      closeTo(tester.getTopLeft(find.text('5小时前').last).dy, 1),
    );
    final tokens = tester.element(find.byType(PostItem)).tokens;
    expect(tokens.text.body.fontSize, 17);
    expect(tokens.text.body.height, 1.75);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
