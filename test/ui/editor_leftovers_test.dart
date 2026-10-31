import 'dart:async';

import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/providers/category_provider.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/message_bus/topic_tracking_providers.dart';
import 'package:fluxdo/providers/theme_provider.dart'
    show sharedPreferencesProvider;
import 'package:fluxdo/utils/copy_source_tracker.dart';
import 'package:fluxdo/widgets/markdown_editor/composer_header_actions.dart';
import 'package:fluxdo/widgets/markdown_editor/composer_object_surface.dart';
import 'package:fluxdo/widgets/post/post_item/post_item.dart';
import 'package:fluxdo/widgets/user/avatar_action_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fixtures.dart';
import 'support/ui_harness.dart';

// 0.4.0 M9.5b：M5 遗留项——楼层菜单四项、头像长按菜单、编辑器头部 ⋯ 菜单、
// 对象工具条材质、摘录来源楼层。论坛请求一律不发，数据是夹具。

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
  categoriesProvider.overrideWith((ref) async => fixtureCategories()),
  currentUserProvider.overrideWith(_FakeUser.new),
  messageBusInitProvider.overrideWith(_FakeMessageBusInit.new),
  topicTrackingStateProvider.overrideWith(_FakeTracking.new),
];

void main() {
  setUpAll(loadUiFonts);

  group('楼层菜单', () {
    Future<void> openMenu(WidgetTester tester, {required bool quote}) async {
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
              onQuotePost: quote ? () {} : null,
            ),
          ),
        ),
        overrides: _overrides(prefs),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byIcon(AppIcons.moreHoriz));
      await tester.pump(const Duration(milliseconds: 500));
    }

    testUi('复制文字、复制楼层链接常驻；传了回调才有引用回复', (tester) async {
      await openMenu(tester, quote: true);
      expect(find.text('复制文字'), findsOneWidget);
      expect(find.text('复制楼层链接'), findsOneWidget);
      expect(find.text('引用回复'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testUi('没有引用回调（未登录等）时不出现引用回复', (tester) async {
      await openMenu(tester, quote: false);
      expect(find.text('复制文字'), findsOneWidget);
      expect(find.text('引用回复'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testUi('复制文字写入剪贴板，并记录来源楼层', (tester) async {
      String? written;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              written = (call.arguments as Map)['text'] as String?;
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
        CopySourceTracker.reset();
      });
      await openMenu(tester, quote: false);
      await tester.tap(find.text('复制文字'));
      await tester.pump(const Duration(milliseconds: 600));
      // 等 Toast 的 3 秒定时器走完
      await tester.pump(const Duration(seconds: 4));
      expect(written, isNotNull);
      expect(written, contains('上周五'));
      expect(CopySourceTracker.sourceFor(written!), 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('摘录来源楼层', () {
    test('剪贴板文字和最近一次复制对得上才认', () {
      CopySourceTracker.reset();
      expect(CopySourceTracker.sourceFor('任意'), isNull);
      CopySourceTracker.noteText('  这一段  ', 12);
      expect(CopySourceTracker.sourceFor('这一段'), 12);
      expect(CopySourceTracker.sourceFor('别的文字'), isNull);
      CopySourceTracker.noteText('新的一段', 3);
      expect(CopySourceTracker.sourceFor('这一段'), isNull);
      expect(CopySourceTracker.sourceFor('新的一段'), 3);
      CopySourceTracker.reset();
    });
  });

  group('头像长按菜单', () {
    testUi('长按头像浮起并出菜单：进主页、复制用户名', (tester) async {
      var tapped = 0;
      await pumpUi(
        tester,
        Scaffold(
          body: Center(
            child: AvatarLongPressMenu(
              onTap: () => tapped++,
              itemsBuilder: () => [
                AppMenuItem(
                  icon: AppIcons.person,
                  label: '进入主页',
                  onTap: () {},
                ),
                AppMenuItem(icon: AppIcons.copy, label: '复制用户名', onTap: () {}),
              ],
              child: const SizedBox.square(
                dimension: 34,
                child: ColoredBox(color: Colors.grey),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(ColoredBox).last);
      expect(tapped, 1);
      await tester.longPress(find.byType(ColoredBox).last);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('进入主页'), findsOneWidget);
      expect(find.text('复制用户名'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('编辑器头部 ⋯ 菜单', () {
    for (final variant in [
      UiVariant.lightDefault,
      const UiVariant(Brightness.dark, 2, UiDevice.pro),
    ]) {
      testUi('预览 / 舍弃收进 AppMenu（${variant.label}）', (tester) async {
        var discarded = false;
        await pumpUi(
          tester,
          Scaffold(
            appBar: AppBar(
              actions: [
                ComposerHeaderActions(
                  availableWidth: 360,
                  submitLabel: '发布',
                  onSubmit: () {},
                  previewing: false,
                  onTogglePreview: () {},
                  showDiscard: true,
                  onDiscard: () => discarded = true,
                  minimumTitleWidth: 200,
                ),
              ],
            ),
          ),
          variant: variant,
        );
        final more = find.byKey(const ValueKey('composer-header-more'));
        if (more.evaluate().isEmpty) return; // 宽度够，全部外显
        await tester.tap(more);
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(AppMenuPanel<VoidCallback>), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('composer-header-discard')));
        await tester.pump(const Duration(milliseconds: 500));
        expect(discarded, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  });

  testUi('对象工具条材质：surface/elevated 不透明底，没有玻璃', (tester) async {
    await pumpUi(
      tester,
      const Scaffold(
        body: Center(child: ComposerObjectSurface(child: SizedBox(width: 80))),
      ),
    );
    expect(find.byType(CapsuleSurface), findsOneWidget);
    final surface = tester.widget<CapsuleSurface>(find.byType(CapsuleSurface));
    expect(
      surface.fill,
      AppTokens.resolve(brightness: Brightness.light).colors.surfaceElevated,
    );
  });
}
