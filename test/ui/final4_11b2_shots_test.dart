import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/providers/theme_provider.dart'
    show sharedPreferencesProvider;
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
  setUpAll(loadUiFonts);

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
}
