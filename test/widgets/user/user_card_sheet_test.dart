import 'dart:async';

import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/fluxdo_render.dart' show FluxdoRender;
import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/selected_topic_provider.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:fluxdo/widgets/common/skeleton.dart';
import 'package:fluxdo/widgets/user/user_card.dart';

import '../../ui/support/ui_harness.dart';

// 用户卡片半屏（补充稿 27）与加载骨架（补充稿 28）。手机上点楼层头像弹出半屏，
// 读者不离开当前楼；「查看主页」才进用户主页。加载中是同结构的骨架，200ms 后才出现。
// 数据是示例，请求用假服务，不联网。

class _LoggedIn extends CurrentUserNotifier {
  @override
  FutureOr<User?> build() => User.fromJson({
    'id': 99,
    'username': 'me',
    'avatar_template': '',
    'trust_level': 1,
  });
}

class _FakeService extends Fake implements DiscourseService {
  /// 用户卡片请求；测试里自己决定什么时候返回
  final pending = Completer<User>();

  @override
  Future<User> getUserCard(String username, {int? includePostCountFor}) =>
      pending.future;
}

User _user({bool canMessage = true}) => User.fromJson({
  'id': 7,
  'username': 'example',
  'name': '示例用户',
  'avatar_template': '',
  'trust_level': 2,
  'bio_cooked': '<p>示例数据：个人简介一行。</p>',
  'can_send_private_message_to_user': canMessage,
});

/// 打开半屏：和楼层头像一样，从一个页面里的按钮调 showUserCard
Future<ProviderContainer> _open(
  WidgetTester tester,
  _FakeService service, {
  UiVariant variant = UiVariant.lightDefault,
}) async {
  await pumpUi(
    tester,
    EmbeddedStackScope(
      stackProvider: selectedMessageProvider,
      child: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showUserCard(
                context: context,
                anchorRect: Rect.zero,
                username: 'example',
                nameFallback: '示例用户',
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ),
    variant: variant,
    overrides: [
      discourseServiceProvider.overrideWithValue(service),
      currentUserProvider.overrideWith(_LoggedIn.new),
    ],
  );
  await tester.tap(find.text('打开'));
  // 半屏进场动画；加载中的请求一直没返回，不能 pumpAndSettle
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
}

final _skeletonButton = find.byKey(const ValueKey('user_card_skeleton_button'));

void main() {
  setUpAll(loadUiFonts);

  group('半屏（28 加载骨架）', () {
    testUi('请求 200ms 内不出骨架，之后出现；结构：头像圆 + 名字条 + 文字条 + 按钮块', (tester) async {
      final service = _FakeService();
      await _open(tester, service);
      // 进场动画后约 100ms：还没到 200ms
      expect(find.byType(SkeletonCircle), findsOneWidget);
      // 占着位置但不可见（Opacity 0）
      final fade = tester.widget<Opacity>(
        find.ancestor(
          of: find.byType(SkeletonCircle),
          matching: find.byType(Opacity),
        ),
      );
      expect(fade.opacity, 0, reason: '200ms 内骨架不出现');

      await tester.pump(const Duration(milliseconds: 250));
      final shown = find.ancestor(
        of: find.byType(SkeletonCircle),
        matching: find.byType(Opacity),
      );
      expect(shown, findsNothing, reason: '200ms 后骨架直接显示，不再套透明层');
      expect(find.byType(SkeletonCircle), findsOneWidget);
      expect(find.byType(SkeletonBox), findsNWidgets(3), reason: '名字条 + 两条文字条');
      expect(_skeletonButton, findsOneWidget);
      expectNoUiException(tester);
    });

    testUi('超过 3 秒出「正在等待论坛响应」，骨架还在', (tester) async {
      final service = _FakeService();
      await _open(tester, service);
      await tester.pump(const Duration(seconds: 3, milliseconds: 100));
      expect(find.text('正在等待论坛响应'), findsOneWidget);
      expect(find.byType(SkeletonCircle), findsOneWidget);
    });

    testUi('请求返回后骨架换成内容', (tester) async {
      final service = _FakeService();
      await _open(tester, service);
      await tester.pump(const Duration(milliseconds: 250));
      service.pending.complete(_user());
      await tester.pumpAndSettle();
      expect(find.byType(SkeletonCircle), findsNothing);
      expect(find.byType(SkeletonBox), findsNothing);
      expect(find.text('示例用户'), findsOneWidget);
    });
  });

  group('半屏（27 用户卡片）', () {
    testUi('内容：名字、@handle · 信任等级、简介、查看主页 + 私信、右上角 x', (tester) async {
      final service = _FakeService();
      await _open(tester, service);
      service.pending.complete(_user());
      await tester.pumpAndSettle();
      expectNoUiException(tester);
      expect(find.text('示例用户'), findsOneWidget);
      expect(find.text('@example'), findsOneWidget);
      // 简介走正文渲染器（文字不是普通 Text，只能认渲染器本身）
      expect(find.byType(FluxdoRender), findsOneWidget);
      expect(find.text('查看主页'), findsOneWidget);
      expect(find.text('私信'), findsOneWidget);
      expect(find.byType(AppCloseButton), findsOneWidget);
      expect(find.byType(AppSheetScaffold), findsOneWidget);
    });

    testUi('不能私信的用户：只有「查看主页」', (tester) async {
      final service = _FakeService();
      await _open(tester, service);
      service.pending.complete(_user(canMessage: false));
      await tester.pumpAndSettle();
      expect(find.text('查看主页'), findsOneWidget);
      expect(find.text('私信'), findsNothing);
    });

    testUi('点「查看主页」：半屏关闭，并打开该用户主页', (tester) async {
      final service = _FakeService();
      final container = await _open(tester, service);
      service.pending.complete(_user());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('user_card_view_profile')));
      await tester.pumpAndSettle();
      expect(find.byType(AppSheetScaffold), findsNothing, reason: '半屏已关');
      final stack = container.read(selectedMessageProvider).stack;
      expect(stack, hasLength(1));
      expect(stack.single.kind, PaneKind.profile);
      expect(stack.single.username, 'example');
    });

    testUi('点 x：半屏关闭，不打开主页', (tester) async {
      final service = _FakeService();
      final container = await _open(tester, service);
      service.pending.complete(_user());
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AppCloseButton));
      await tester.pumpAndSettle();
      expect(find.byType(AppSheetScaffold), findsNothing);
      expect(container.read(selectedMessageProvider).stack, isEmpty);
    });
  });
}
