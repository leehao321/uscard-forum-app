import 'dart:async';
import 'dart:io';

import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/post_revision.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/widgets/post/post_revision/revision_modal.dart';
import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:fluxdo/widgets/user/user_card.dart';
import 'package:fluxdo/providers/theme_provider.dart'
    show sharedPreferencesProvider;
import 'package:fluxdo/providers/user_content_providers.dart';
import 'package:fluxdo/widgets/share/export_sheet.dart';
import 'package:fluxdo/widgets/share/share_image_preview.dart';
import 'package:fluxdo/widgets/share/share_image_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ui_harness.dart';

// 第 11 批 11b-2（补充稿 21–31）截图：分享图片 5 种样式、导出文章、用户卡片、
// 编辑历史三种对比。设置 SHOTS_DIR 才出图（浅 / 深各一张）；不设置时只做
// 不抛异常的检查。数据全是示例，不联网。

const _light = UiVariant(Brightness.light, 1.0, UiDevice.pro);
const _dark = UiVariant(Brightness.dark, 1.0, UiDevice.pro);

/// 半屏的背景：模拟页面被 32% 遮罩盖住，半屏贴底
Widget _sheetHost(Widget sheet) => Stack(
  children: [
    Positioned.fill(
      child: Builder(
        builder: (context) => ColoredBox(
          color: Color.alphaBlend(
            AppFixedColors.black.withValues(alpha: 0.32),
            context.tokens.colors.surfacePage,
          ),
        ),
      ),
    ),
    Align(alignment: Alignment.bottomCenter, child: sheet),
  ],
);

/// 示例数据：不联网，不用真实帖子
TopicDetail _shareDetail() {
  final post = {
    'id': 1,
    'username': 'example',
    'name': '示例用户',
    'avatar_template': '',
    'cooked':
        '<p>示例数据：分享图片里显示的正文摘录，最多五行。</p>',
    'post_number': 1,
    'post_type': 1,
    'created_at': '2026-10-30T08:00:00.000Z',
    'updated_at': '2026-10-30T08:00:00.000Z',
    'like_count': 0,
    'reply_count': 0,
    'reply_to_post_number': 0,
    'user_id': 1,
    'read': true,
  };
  return TopicDetail.fromJson({
    'id': 1001,
    'title': '示例话题标题',
    'slug': 'example',
    'posts_count': 1,
    'category_id': 11,
    'tags': <String>[],
    'views': 1,
    'like_count': 0,
    'created_at': '2026-10-30T08:00:00.000Z',
    'highest_post_number': 1,
    'last_read_post_number': 1,
    'post_stream': {
      'posts': [post],
      'stream': [1],
    },
    'details': {
      'created_by': {'id': 1, 'username': 'example', 'avatar_template': ''},
      'last_poster': {'id': 1, 'username': 'example', 'avatar_template': ''},
    },
  });
}

String _name(UiVariant v) => v.brightness == Brightness.dark ? 'dark' : 'light';

void main() {
  setUpAll(() async {
    await loadUiFonts();
    // 测试环境没有系统等宽字体：把 'SF Mono' 指到 MiSans，截图里才有字形
    // （真机并排 Markdown 用的是系统等宽）
    final bytes = await File('assets/fonts/MiSansVF.ttf').readAsBytes();
    final loader = FontLoader('SF Mono')
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  });

  // 21–25 分享图片 5 种样式
  const styles = {
    ShareImageTheme.classic: '21_分享图片_经典',
    ShareImageTheme.dark: '22_分享图片_深色',
    ShareImageTheme.green: '23_分享图片_绿野',
    ShareImageTheme.black: '24_分享图片_纯黑',
    ShareImageTheme.blue: '25_分享图片_蓝调',
  };
  for (final v in [_light, _dark]) {
    for (final e in styles.entries) {
      testUi('${e.value}（${_name(v)}）', (tester) async {
        SharedPreferences.setMockInitialValues({
          'pref_share_image_style_index': e.key.index,
        });
        final sp = await SharedPreferences.getInstance();
        final detail = _shareDetail();
        await pumpUi(
          tester,
          _sheetHost(
            ShareImagePreview(
              detail: detail,
              post: detail.postStream.posts.first,
            ),
          ),
          variant: v,
          overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
          prefs: {'pref_share_image_style_index': e.key.index},
        );
        await tester.pumpAndSettle();
        expectNoUiException(tester);
        await uiShot(tester, '${e.value}_${_name(v)}');
      });
    }
  }

  // 26 导出文章半屏
  for (final v in [_light, _dark]) {
    testUi('26_导出文章_半屏（${_name(v)}）', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      await pumpUi(
        tester,
        _sheetHost(ExportSheet(detail: _exportDetail())),
        variant: v,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          currentUsernameProvider.overrideWith((ref) async => null),
        ],
      );
      // 默认「仅主帖」；切到「全部楼层」，和稿一致
      await tester.tap(find.text('全部楼层'));
      await tester.pumpAndSettle();
      expectNoUiException(tester);
      await uiShot(tester, '26_导出文章_半屏_${_name(v)}');
    });
  }

  // 27 用户卡片半屏 / 28 加载骨架
  for (final v in [_light, _dark]) {
    testUi('27_用户卡片_半屏（${_name(v)}）', (tester) async {
      final service = _CardService();
      await _openUserCard(tester, service, v);
      service.pending.complete(_cardUser());
      await tester.pumpAndSettle();
      expectNoUiException(tester);
      await uiShot(tester, '27_用户卡片_半屏_${_name(v)}');
    });

    testUi('28_用户卡片_加载骨架（${_name(v)}）', (tester) async {
      final service = _CardService();
      await _openUserCard(tester, service, v);
      // 200ms 后骨架才出现
      await tester.pump(const Duration(milliseconds: 300));
      expectNoUiException(tester);
      await uiShot(tester, '28_用户卡片_加载骨架_${_name(v)}');
    });
  }

  // 29 编辑历史 · 行内差异 / 30 对比方式菜单 / 31 并排 Markdown
  for (final v in [_light, _dark]) {
    testUi('29_编辑历史_行内差异（${_name(v)}）', (tester) async {
      await _openRevision(tester, v);
      expectNoUiException(tester);
      await uiShot(tester, '29_编辑历史_行内差异_${_name(v)}');
    });

    testUi('30_编辑历史_对比方式菜单（${_name(v)}）', (tester) async {
      await _openRevision(tester, v);
      await tester.tap(find.byKey(const ValueKey('revision_mode_menu')));
      await tester.pumpAndSettle();
      expectNoUiException(tester);
      await uiShot(tester, '30_编辑历史_对比方式菜单_${_name(v)}');
    });

    testUi('31_编辑历史_并排_Markdown（${_name(v)}）', (tester) async {
      await _openRevision(tester, v);
      await tester.tap(find.byKey(const ValueKey('revision_mode_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('并排 Markdown'));
      await tester.pumpAndSettle();
      expectNoUiException(tester);
      await uiShot(tester, '31_编辑历史_并排_Markdown_${_name(v)}');
    });
  }
}

/// 导出半屏只用帖子 id 列表
TopicDetail _exportDetail() => TopicDetail.fromJson({
  'id': 1001,
  'title': '示例话题标题',
  'slug': 'example',
  'posts_count': 5,
  'category_id': 11,
  'tags': <String>[],
  'views': 1,
  'like_count': 0,
  'created_at': '2026-10-30T08:00:00.000Z',
  'highest_post_number': 5,
  'last_read_post_number': 1,
  'post_stream': {
    'posts': <Map<String, dynamic>>[],
    'stream': [1, 2, 3, 4, 5],
  },
  'details': {
    'created_by': {'id': 1, 'username': 'example', 'avatar_template': ''},
    'last_poster': {'id': 1, 'username': 'example', 'avatar_template': ''},
  },
});

class _CardMe extends CurrentUserNotifier {
  @override
  FutureOr<User?> build() => User.fromJson({
    'id': 99,
    'username': 'me',
    'avatar_template': '',
    'trust_level': 1,
  });
}

class _CardService extends Fake implements DiscourseService {
  final pending = Completer<User>();

  @override
  Future<User> getUserCard(String username, {int? includePostCountFor}) =>
      pending.future;
}

User _cardUser() => User.fromJson({
  'id': 7,
  'username': 'example',
  'name': '示例用户',
  'avatar_template': '',
  'trust_level': 2,
  'bio_cooked': '<p>示例数据：个人简介一行。</p>',
  'can_send_private_message_to_user': true,
});

Future<void> _openUserCard(
  WidgetTester tester,
  _CardService service,
  UiVariant v,
) async {
  await pumpUi(
    tester,
    Builder(
      builder: (context) => _sheetHostPage(
        TextButton(
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
    variant: v,
    overrides: [
      discourseServiceProvider.overrideWithValue(service),
      currentUserProvider.overrideWith(_CardMe.new),
    ],
  );
  await tester.tap(find.text('打开'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Widget _sheetHostPage(Widget child) => Scaffold(body: Center(child: child));

class _RevisionService extends Fake implements DiscourseService {
  @override
  Future<PostRevision> getLatestPostRevision(int postId) async =>
      PostRevision.fromJson({
        'first_revision': 1,
        'previous_revision': 1,
        'current_revision': 2,
        'next_revision': 3,
        'last_revision': 3,
        'current_version': 2,
        'version_count': 3,
        'username': 'example',
        'acting_user_name': '示例用户',
        'avatar_template': '',
        'created_at': '2026-10-30T08:00:00.000Z',
        'body_changes': {
          'inline':
              '<div class="inline-diff"><p>示例数据：这一句没有改动。</p>'
              '<p><del>示例：被删除的文字</del></p>'
              '<p><ins>示例：新增的文字</ins></p></div>',
          'side_by_side':
              '<div class="revision-content --previous"><p>示例：上一版正文</p></div>'
              '<div class="revision-content --current"><p>示例：当前版正文</p></div>',
          'side_by_side_markdown':
              '<table class="markdown">'
              '<tr><td>## 示例标题</td><td>## 示例标题</td></tr>'
              '<tr><td class="diff-del">- 示例删除行</td>'
              '<td class="diff-ins">+ 示例新增行</td></tr>'
              '<tr><td>示例未改行</td><td>示例未改行</td></tr></table>',
        },
      });
}

class _NoUser extends CurrentUserNotifier {
  @override
  FutureOr<User?> build() => null;
}

/// 打开真实的编辑历史半屏（和楼层「已编辑」入口同一个函数）
Future<void> _openRevision(WidgetTester tester, UiVariant v) async {
  await pumpUi(
    tester,
    Builder(
      builder: (context) => _sheetHostPage(
        TextButton(
          onPressed: () => showPostRevisionSheet(context: context, postId: 1),
          child: const Text('打开'),
        ),
      ),
    ),
    variant: v,
    overrides: [
      discourseServiceProvider.overrideWithValue(_RevisionService()),
      currentUserProvider.overrideWith(_NoUser.new),
    ],
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}
