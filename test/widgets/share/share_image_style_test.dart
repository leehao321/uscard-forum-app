import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/providers/preferences_provider.dart';
import 'package:fluxdo/providers/theme_provider.dart'
    show sharedPreferencesProvider;
import 'package:fluxdo/widgets/share/share_image_preview.dart';
import 'package:fluxdo/widgets/share/share_image_theme.dart';
import 'package:fluxdo/widgets/share/share_image_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ui/support/ui_harness.dart';

// 分享图片半屏的 5 种样式（补充稿 21–25）：
// 经典 / 深色 / 纯黑 / 绿野 / 蓝调的取色全部来自 token，样式不跟随 App 深浅色；
// 点色板后预览（和导出的同一棵树）立刻换成对应 token 色，并存进偏好。

/// 示例数据：不联网，不用真实帖子
TopicDetail _detail() {
  final post = {
    'id': 1,
    'username': 'example',
    'name': '示例用户',
    'avatar_template': '',
    'cooked': '<p>示例数据：分享图片里显示的正文摘录。</p>',
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

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required UiVariant variant,
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final detail = _detail();
  await pumpUi(
    tester,
    Align(
      alignment: Alignment.bottomCenter,
      child: ShareImagePreview(detail: detail, post: detail.postStream.posts.first),
    ),
    variant: variant,
    overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
    prefs: prefs,
  );
  await tester.pump(const Duration(milliseconds: 100));
  return ProviderScope.containerOf(tester.element(find.byType(ShareImagePreview)));
}

/// 分享图根容器的底色：ShareImageWidget 下第一个 ColoredBox
/// （`Container(color:)` 没有 decoration 时展开成 ColoredBox）
Color _imageBg(WidgetTester tester) {
  final box = find
      .descendant(
        of: find.byType(ShareImageWidget),
        matching: find.byType(ColoredBox),
      )
      .evaluate()
      .map((e) => e.widget as ColoredBox)
      .first;
  return box.color;
}

/// 「美卡论坛」标志文字的颜色（取 text 的 0.8 透明度）
Color? _logoTextColor(WidgetTester tester) {
  final text = tester.widget<Text>(find.text('美卡论坛'));
  return text.style?.color;
}

Finder _swatch(ShareImageTheme t) =>
    find.byKey(ValueKey('share_swatch_${t.nameKey}'));

void main() {
  setUpAll(loadUiFonts);

  group('样式取色（token）', () {
    test('共 5 种，顺序 = 色板顺序', () {
      expect(ShareImageTheme.values, [
        ShareImageTheme.classic,
        ShareImageTheme.dark,
        ShareImageTheme.black,
        ShareImageTheme.green,
        ShareImageTheme.blue,
      ]);
    });

    test('share/蓝调 = #E8F4FC', () {
      expect(AppSharePalette.blue, const Color(0xFFE8F4FC));
    });

    test('经典 = 浅色 surface/grouped，文字取浅色 text/primary', () {
      final p = ShareImageTheme.classic.palette;
      expect(p.bg, AppColors.light.surfaceGrouped);
      expect(p.text, AppColors.light.textPrimary);
      expect(p.isDark, isFalse);
    });

    test('深色 = 深色 surface/grouped（固定用 Dark 模式表面）', () {
      final p = ShareImageTheme.dark.palette;
      expect(p.bg, AppColors.dark.surfaceGrouped);
      expect(p.text, AppColors.dark.textPrimary);
      expect(p.isDark, isTrue);
    });

    test('纯黑 = 深色 surface/page（#000）', () {
      final p = ShareImageTheme.black.palette;
      expect(p.bg, AppColors.dark.surfacePage);
      expect(p.bg, const Color(0xFF000000));
    });

    test('绿野 = brand/button 底 + text/on-brand 字', () {
      final p = ShareImageTheme.green.palette;
      expect(p.bg, AppColors.light.brandButton);
      expect(p.text, AppColors.light.onBrandButton);
    });

    test('蓝调 = share/蓝调，文字按浅色模式', () {
      final p = ShareImageTheme.blue.palette;
      expect(p.bg, AppSharePalette.blue);
      expect(p.text, AppColors.light.textPrimary);
      expect(p.isDark, isFalse);
    });

    test('旧版 6 种样式的偏好索引换算到新索引', () {
      // 旧：经典 0 / 纯白 1 / 深色 2 / 纯黑 3 / 蓝调 4 / 绿色调 5
      expect(ShareImageTheme.fromLegacyIndex(0), ShareImageTheme.classic.index);
      expect(ShareImageTheme.fromLegacyIndex(1), ShareImageTheme.classic.index);
      expect(ShareImageTheme.fromLegacyIndex(2), ShareImageTheme.dark.index);
      expect(ShareImageTheme.fromLegacyIndex(3), ShareImageTheme.black.index);
      expect(ShareImageTheme.fromLegacyIndex(4), ShareImageTheme.blue.index);
      expect(ShareImageTheme.fromLegacyIndex(5), ShareImageTheme.green.index);
      expect(ShareImageTheme.fromLegacyIndex(9), ShareImageTheme.classic.index);
    });
  });

  group('偏好里的样式索引', () {
    test('没有新键时从旧键换算（旧纯黑 3 → 现在的纯黑）', () async {
      SharedPreferences.setMockInitialValues({'pref_share_image_theme_index': 3});
      final sp = await SharedPreferences.getInstance();
      final n = PreferencesNotifier(sp);
      expect(n.state.shareImageThemeIndex, ShareImageTheme.black.index);
    });

    test('新键优先，写入只写新键', () async {
      SharedPreferences.setMockInitialValues({
        'pref_share_image_theme_index': 3,
        'pref_share_image_style_index': ShareImageTheme.blue.index,
      });
      final sp = await SharedPreferences.getInstance();
      final n = PreferencesNotifier(sp);
      expect(n.state.shareImageThemeIndex, ShareImageTheme.blue.index);
      await n.setShareImageThemeIndex(ShareImageTheme.green.index);
      expect(sp.getInt('pref_share_image_style_index'), ShareImageTheme.green.index);
      expect(sp.getInt('pref_share_image_theme_index'), 3, reason: '旧键保留不动');
    });
  });

  // App 浅 / 深都要得到同样的分享图：样式不跟随 App 深浅色
  for (final brightness in Brightness.values) {
    final variant = UiVariant(brightness, 1.0, UiDevice.pro);
    group('预览半屏（App ${brightness.name}）', () {
      testUi('默认经典：底色 = 浅色 surface/grouped，色板 5 个', (tester) async {
        await _pump(tester, variant: variant);
        expectNoUiException(tester);
        expect(_imageBg(tester), AppColors.light.surfaceGrouped);
        expect(_logoTextColor(tester)?.withValues(alpha: 1), AppColors.light.textPrimary);
        for (final t in ShareImageTheme.values) {
          expect(_swatch(t), findsOneWidget);
        }
      });

      for (final t in ShareImageTheme.values) {
        testUi('点「${t.nameKey}」：预览换成该样式的 token 色，并存进偏好', (tester) async {
          final container = await _pump(tester, variant: variant);
          await tester.tap(_swatch(t));
          await tester.pumpAndSettle();
          expectNoUiException(tester);

          final p = t.palette;
          expect(_imageBg(tester), p.bg, reason: '预览底色');
          expect(
            _logoTextColor(tester)?.withValues(alpha: 1),
            p.text,
            reason: '预览文字色',
          );
          expect(
            container.read(preferencesProvider).shareImageThemeIndex,
            t.index,
          );
        });
      }

      testUi('按偏好里存的索引恢复上次的样式', (tester) async {
        await _pump(
          tester,
          variant: variant,
          prefs: {'pref_share_image_style_index': ShareImageTheme.green.index},
        );
        expect(_imageBg(tester), AppColors.light.brandButton);
      });
    });
  }
}
