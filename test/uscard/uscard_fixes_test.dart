import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/config/sites/uscard.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/services/app_lock_service.dart';
import 'package:fluxdo/services/network/cookie/cookie_jar_service.dart';
import 'package:fluxdo/services/webview_session_cookie_refresh_service.dart';
import 'package:fluxdo/storage/topic_note_store.dart';
import 'package:fluxdo/widgets/app_lock_gate.dart';
import 'package:fluxdo/widgets/notes/topic_note_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('美卡站点开关', () {
    test('没有树形回复插件、没有会话 bootstrap 插件', () {
      expect(uscardCustomization.supportsNestedView, isFalse);
      expect(uscardCustomization.hasSessionBootstrapPlugin, isFalse);
    });

    test('会话 bootstrap 直接视为已同步，不起 WebView', () async {
      final result = await WebViewSessionCookieRefreshService.instance
          .ensureSynced(reason: 'test');
      expect(result.ok, isTrue);
      expect(
        WebViewSessionCookieRefreshService.instance.lastSuccessAt,
        isNotNull,
      );
    });
  });

  test('主站带 www 时，根域上的 cookie（cf_clearance）也算主站', () {
    for (final domain in [
      '.uscardforum.com',
      'uscardforum.com',
      'www.uscardforum.com',
      '.www.uscardforum.com',
      'cdn.www.uscardforum.com',
      null,
    ]) {
      expect(CookieJarService.matchesAppHost(domain), isTrue, reason: domain);
    }
    for (final domain in ['com', '.com', 'notuscardforum.com', 'linux.do']) {
      expect(CookieJarService.matchesAppHost(domain), isFalse, reason: domain);
    }
  });

  group('没装回应插件时用 actions_summary 表示点赞', () {
    test('自己点过赞', () {
      final r = PostReaction.likesFromActionsSummary({
        'actions_summary': [
          {'id': 2, 'count': 3, 'acted': true, 'can_undo': true},
        ],
      });
      expect(r.reactions.single.id, 'heart');
      expect(r.reactions.single.count, 3);
      expect(r.current?.id, 'heart');
    });

    test('别人点过、自己没点；没有 count 时用 like_count', () {
      final r = PostReaction.likesFromActionsSummary({
        'like_count': 2,
        'actions_summary': [
          {'id': 2, 'can_act': true},
        ],
      });
      expect(r.reactions.single.count, 2);
      expect(r.current, isNull);
    });

    test('没人点赞', () {
      final r = PostReaction.likesFromActionsSummary({'actions_summary': []});
      expect(r.reactions, isEmpty);
      expect(r.current, isNull);
    });
  });

  group('应用锁', () {
    final lock = AppLockService.instance;
    tearDown(() => lock.debugSetState());

    test('离开前台先盖隐私遮罩，没超时回来就撤掉', () {
      lock.debugSetState(enabled: true, timeoutSeconds: 60);
      // 桌面端（跑测试的 Windows）只有 hidden 才盖；inactive 只是失去焦点
      lock.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(lock.obscured, isFalse);
      lock.didChangeAppLifecycleState(AppLifecycleState.hidden);
      expect(lock.obscured, isTrue);
      expect(lock.covering, isTrue);
      lock.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(lock.obscured, isFalse);
      expect(lock.locked, isFalse);
    });

    test('选「立即」时回到前台就上锁', () {
      lock.debugSetState(enabled: true, timeoutSeconds: 0);
      lock.didChangeAppLifecycleState(AppLifecycleState.hidden);
      lock.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(lock.locked, isTrue);
    });

    test('没开应用锁时什么都不盖', () {
      lock.debugSetState();
      lock.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(lock.covering, isFalse);
    });

    testWidgets('遮罩屏蔽底下页面的语义（VoiceOver 读不到），并收起键盘', (tester) async {
      final semantics = tester.ensureSemantics();
      // 从语义树根往下收集所有 label：这才是 VoiceOver 实际能读到的内容
      List<String> spokenLabels() {
        final labels = <String>[];
        void visit(SemanticsNode node) {
          if (node.label.isNotEmpty) labels.add(node.label);
          node.visitChildren((child) {
            visit(child);
            return true;
          });
        }

        for (final view in tester.binding.renderViews) {
          final root = view.owner?.semanticsOwner?.rootSemanticsNode;
          if (root != null) visit(root);
        }
        return labels;
      }

      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              // App 里遮罩所在的 Stack 是全屏的
              fit: StackFit.expand,
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: TextField(focusNode: focus),
                ),
                const Center(child: Text('私信内容')),
                const AppLockGate(),
              ],
            ),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      expect(spokenLabels(), contains('私信内容'));

      // 只盖隐私遮罩（不上锁，避免测试里弹系统认证）
      lock.debugSetState(enabled: true, obscured: true);
      await tester.pump();
      final gateBlock = find.descendant(
        of: find.byType(AppLockGate),
        matching: find.byType(BlockSemantics),
      );
      expect(gateBlock, findsOneWidget);
      expect(focus.hasFocus, isFalse);
      expect(spokenLabels(), isNot(contains('私信内容')));
      expect(find.text('解锁'), findsNothing);

      lock.debugSetState();
      await tester.pump();
      expect(gateBlock, findsNothing);
      expect(spokenLabels(), contains('私信内容'));
      semantics.dispose();
    });
  });

  testWidgets('笔记停笔 1 秒自动保存，不用等关闭面板', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showTopicNoteSheet(context, topicId: 42, title: '话题'),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '写了一半');
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    final note = await tester.runAsync(() => TopicNoteStore.get(42));
    expect(note?.text, '写了一半');
  });
}
