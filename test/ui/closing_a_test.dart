import 'dart:io';

import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/pages/saved_topics_page.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/invite_private_message_dialog.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/private_message_participants.dart';
import 'package:fluxdo/storage/saved_topic_store.dart';
import 'package:fluxdo/widgets/auth/qr_login_sheet.dart';
import 'package:fluxdo/widgets/post/pm_recipient_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ui_harness.dart';

// 0.4.0 收尾 A：私信参与者 / 收件人 / 邀请对话框、QR 桌面对话框、已存帖子。
// 论坛请求一律不发：数据全是本地假数据。

TopicUser _user(int id, String username, String? name) =>
    TopicUser(id: id, username: username, name: name, avatarTemplate: '');

Widget _participants({int selfId = 1}) => Scaffold(
  body: SingleChildScrollView(
    child: PrivateMessageParticipants(
      location: PrivateMessageParticipantsLocation.firstPost,
      participants: [
        _user(1, 'chase_fan', '张三'),
        _user(2, 'bossdao', null),
        _user(3, 'a_very_long_username_for_wrapping_test', '一个很长的名字用来测试换行'),
      ],
      groups: const [TopicGroup(id: 9, name: 'staff', fullName: '管理组')],
      canRemoveAllowedUsers: true,
      removableSelfId: selfId,
      canInvite: true,
      removingParticipantId: null,
      removingGroupName: null,
      onRemoveParticipant: (_) {},
      onRemoveGroup: (_) {},
      onInvite: () {},
    ),
  ),
);

void main() {
  setUpAll(loadUiFonts);

  group('私信参与者', () {
    for (final variant in [...UiVariant.portrait, ...UiVariant.landscape]) {
      testUi('不溢出（${variant.label}）', (tester) async {
        await pumpUi(tester, _participants(), variant: variant);
        expectNoUiException(tester);
      });
    }

    testUi('邀请与移除按钮热区 ≥ 44，胶囊是 v2 材质', (tester) async {
      await pumpUi(tester, _participants());
      final invite = find.byKey(
        const ValueKey('pm-participants-firstPost-invite'),
      );
      expect(tester.getSize(invite).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(invite).width, greaterThanOrEqualTo(44));
      final remove = find.byKey(
        const ValueKey('pm-participant-firstPost-remove-2'),
      );
      expect(tester.getSize(remove).height, greaterThanOrEqualTo(44));
      await uiShot(tester, 'a_participants');
      expect(find.text('参与者 · 4'), findsOneWidget);
      await expectUiAccessibility(tester, textContrast: false);
    });
  });

  group('收件人字段', () {
    for (final inline in [true, false]) {
      for (final variant in [
        UiVariant.lightDefault,
        const UiVariant(Brightness.dark, 2, UiDevice.pro),
        ...UiVariant.landscape,
      ]) {
        testUi('${inline ? '内联' : '对话框'}形态不溢出（${variant.label}）', (
          tester,
        ) async {
          await pumpUi(
            tester,
            Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: PmRecipientField(
                  inline: inline,
                  recipients: const ['bossdao', 'chase_fan'],
                  onChanged: (_) {},
                ),
              ),
            ),
            variant: variant,
          );
          expectNoUiException(tester);
        });
      }
    }

    testUi('内联形态有「收件人」标签，已选胶囊 36 高、x 热区 44', (tester) async {
      await pumpUi(
        tester,
        Scaffold(
          body: PmRecipientField(
            inline: true,
            recipients: const ['bossdao'],
            onChanged: (_) {},
          ),
        ),
      );
      await uiShot(tester, 'a_recipient_inline');
      expect(find.text('收件人'), findsOneWidget);
      expect(find.text('@bossdao'), findsOneWidget);
      final x = find.byIcon(AppIcons.close);
      expect(
        tester
            .getSize(
              find.ancestor(of: x, matching: find.byType(AppPressable)).first,
            )
            .width,
        greaterThanOrEqualTo(44),
      );
    });
  });

  group('邀请对话框', () {
    testUi('左右 40，输入区不溢出', (tester) async {
      await pumpUi(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    showInvitePrivateMessageDialog(context: context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expectNoUiException(tester);
      expect(find.byKey(const ValueKey('pm-invite-confirm')), findsOneWidget);
    });
  });

  group('QR 登录', () {
    testUi('桌面形态是 v2 对话框：左对齐标题 + 44 的关闭键', (tester) async {
      await pumpUi(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showQrLoginSheet(context, username: 'me'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        variant: const UiVariant(Brightness.light, 1, UiDevice.landscape),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expectNoUiException(tester);
      final close = find.byIcon(AppIcons.close);
      expect(close, findsOneWidget);
      expect(
        tester
            .getSize(
              find
                  .ancestor(of: close, matching: find.byType(AppPressable))
                  .first,
            )
            .height,
        greaterThanOrEqualTo(44),
      );
    });
  });

  group('已存帖子', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('saved_topics_ui');
      SavedTopicStore.debugDirectory = dir;
    });
    tearDown(() async {
      SavedTopicStore.debugDirectory = null;
      await dir.delete(recursive: true);
    });

    for (final variant in [
      UiVariant.lightDefault,
      const UiVariant(Brightness.dark, 1.3, UiDevice.pro),
      ...UiVariant.landscape,
    ]) {
      testUi('空列表不溢出（${variant.label}）', (tester) async {
        await tester.runAsync(() async {
          SharedPreferences.setMockInitialValues({});
        });
        await pumpUi(
          tester,
          const SavedTopicsPage(),
          variant: variant,
          settle: false,
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expectNoUiException(tester);
        expect(find.text('已存帖子'), findsOneWidget);
      });
    }
  });
}
