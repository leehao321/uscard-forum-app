import 'dart:async';

import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/post_revision.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/widgets/post/post_revision/revision_diff_utils.dart';
import 'package:fluxdo/widgets/post/post_revision/revision_view.dart';
import 'package:fluxdo_render/fluxdo_render.dart' show FluxdoRender;

import '../../ui/support/ui_harness.dart';

// 编辑历史三种对比方式（补充稿 29–31）：行内差异（删除 text/destructive + 删除线、
// 新增 brand/primary）、并排 Markdown（左上一版右当前版，系统等宽）、渲染后对比。
// 点右上角的对比方式切换；数据是示例，请求用假服务，不联网。

const _inline =
    '<div class="inline-diff"><p>示例数据：这一句没有改动。</p>'
    '<p><del>示例：被删除的文字</del></p><p><ins>示例：新增的文字</ins></p></div>';

const _sideBySide =
    '<div class="revision-content --previous"><p>示例：上一版正文</p></div>'
    '<div class="revision-content --current"><p>示例：当前版正文</p></div>';

const _markdown =
    '<table class="markdown">'
    '<tr><td>## 示例标题</td><td>## 示例标题</td></tr>'
    '<tr><td class="diff-del">- 示例删除行</td><td class="diff-ins">+ 示例新增行</td></tr>'
    '<tr><td>示例未改行</td><td>示例未改行</td></tr>'
    '</table>';

Map<String, dynamic> _json({
  int current = 2,
  int? previous = 1,
  int? next = 3,
  bool body = true,
}) => {
  'first_revision': 1,
  'previous_revision': previous ?? current,
  'current_revision': current,
  'next_revision': next,
  'last_revision': 3,
  'current_version': current,
  'version_count': 3,
  'username': 'example',
  'acting_user_name': '示例用户',
  'avatar_template': '',
  'created_at': '2026-10-30T08:00:00.000Z',
  'edit_reason': '示例原因',
  if (body)
    'body_changes': {
      'inline': _inline,
      'side_by_side': _sideBySide,
      'side_by_side_markdown': _markdown,
    },
};

class _FakeService extends Fake implements DiscourseService {
  _FakeService({this.single = false});

  /// 只有一个版本：没有上一版也没有下一版
  final bool single;

  /// 请求过的版本号
  final requested = <int>[];

  @override
  Future<PostRevision> getLatestPostRevision(int postId) async =>
      PostRevision.fromJson(
        single ? _json(previous: null, next: null) : _json(),
      );

  @override
  Future<PostRevision> getPostRevision(int postId, int revision) async {
    requested.add(revision);
    return PostRevision.fromJson(_json(current: revision, previous: revision - 1));
  }
}

class _NoUser extends CurrentUserNotifier {
  @override
  FutureOr<User?> build() => null;
}

Future<void> _pump(
  WidgetTester tester,
  _FakeService service, {
  UiVariant variant = UiVariant.lightDefault,
}) async {
  await pumpUi(
    tester,
    const Scaffold(body: PostRevisionView(postId: 1)),
    variant: variant,
    overrides: [
      discourseServiceProvider.overrideWithValue(service),
      currentUserProvider.overrideWith(_NoUser.new),
    ],
  );
  await tester.pump(const Duration(milliseconds: 100));
}

/// 当前页面里所有正文渲染器拿到的 HTML
List<String> _renderedHtml(WidgetTester tester) => tester
    .widgetList<FluxdoRender>(find.byType(FluxdoRender))
    .map((w) => w.cookedHtml)
    .toList();

Future<void> _chooseMode(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('revision_mode_menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

void main() {
  setUpAll(loadUiFonts);

  group('colorizeDiffHtml', () {
    const ins = Color(0xFF173E31);
    const del = Color(0xFFD70015);

    test('新增换成 brand/primary 的 span，去掉默认下划线', () {
      final out = colorizeDiffHtml(
        '<p>甲<ins class="x">乙</ins></p>',
        insColor: ins,
        delColor: del,
      );
      expect(out, '<p>甲<span style="color:#173e31">乙</span></p>');
    });

    test('删除保留 del 标签（删除线），里面套 text/destructive 的 span', () {
      final out = colorizeDiffHtml(
        '<p><del>丙</del></p>',
        insColor: ins,
        delColor: del,
      );
      expect(out, '<p><del><span style="color:#d70015">丙</span></del></p>');
    });

    test('没有 ins / del 的 HTML 原样返回', () {
      const html = '<p>没有改动</p>';
      expect(colorizeDiffHtml(html, insColor: ins, delColor: del), html);
    });
  });

  group('parseMarkdownDiffRows', () {
    test('按行拆成左（上一版）右（当前版），读出删除 / 新增', () {
      final rows = parseMarkdownDiffRows(_markdown)!;
      expect(rows, hasLength(3));
      expect(rows[0].previous.kind, DiffLineKind.common);
      expect(rows[0].previous.plainText, '## 示例标题');
      expect(rows[1].previous.kind, DiffLineKind.deleted);
      expect(rows[1].previous.plainText, '- 示例删除行');
      expect(rows[1].current.kind, DiffLineKind.added);
      expect(rows[1].current.plainText, '+ 示例新增行');
      expect(rows[2].current.plainText, '示例未改行');
    });

    test('行内的 ins / del 标成「被改的片段」，实体还原成文字', () {
      final rows = parseMarkdownDiffRows(
        '<table><tr><td class="diff-del">a &amp; <del>b</del></td><td></td></tr></table>',
      )!;
      expect(rows.single.previous.segments, const [
        DiffSegment('a & '),
        DiffSegment('b', changed: true),
      ]);
      expect(rows.single.current.isEmpty, isTrue);
    });

    test('没有表格行时返回 null', () {
      expect(parseMarkdownDiffRows('<p>x</p>'), isNull);
    });
  });

  for (final brightness in Brightness.values) {
    final variant = UiVariant(brightness, 1.0, UiDevice.pro);
    group('编辑历史（${brightness.name}）', () {
      testUi('工具栏：上一版 → 当前版、当前对比方式「行内差异」', (tester) async {
        await _pump(tester, _FakeService(), variant: variant);
        expectNoUiException(tester);
        expect(find.text('上一版 → 当前版'), findsOneWidget);
        expect(find.byKey(const ValueKey('revision_mode_label')), findsOneWidget);
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('revision_mode_label'))).data,
          '行内差异',
        );
        expect(find.byKey(const ValueKey('revision_previous')), findsOneWidget);
        expect(find.byKey(const ValueKey('revision_next')), findsOneWidget);
      });

      testUi('行内差异：新增 brand/primary、删除 text/destructive（删除线）', (tester) async {
        await _pump(tester, _FakeService(), variant: variant);
        final colors = AppColors.resolve(brightness, AccentPreset.meika);
        final html = _renderedHtml(tester).single;
        expect(html, contains('<span style="color:${_hex(colors.brandPrimary)}">示例：新增的文字</span>'));
        expect(
          html,
          contains('<del><span style="color:${_hex(colors.textDestructive)}">示例：被删除的文字</span></del>'),
        );
        expect(html, isNot(contains('<ins')), reason: '新增不再带下划线标签');
        expect(find.byKey(const ValueKey('revision_diff_card')), findsOneWidget);
      });

      testUi('点对比方式：菜单三项，顺序 行内差异 / 并排 Markdown / 渲染后对比，当前项带勾', (tester) async {
        await _pump(tester, _FakeService(), variant: variant);
        await tester.tap(find.byKey(const ValueKey('revision_mode_menu')));
        await tester.pumpAndSettle();
        final inline = tester.getTopLeft(find.byKey(const ValueKey('revision_mode_inline'))).dy;
        final md = tester.getTopLeft(find.byKey(const ValueKey('revision_mode_sideBySideMarkdown'))).dy;
        final rendered = tester.getTopLeft(find.byKey(const ValueKey('revision_mode_sideBySide'))).dy;
        expect(inline, lessThan(md));
        expect(md, lessThan(rendered));
        expect(find.text('行内差异'), findsWidgets);
        expect(find.text('并排 Markdown'), findsOneWidget);
        expect(find.text('渲染后对比'), findsOneWidget);
        // 当前项（行内差异）有勾
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('revision_mode_inline')),
            matching: find.byIcon(AppIcons.check),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('revision_mode_sideBySide')),
            matching: find.byIcon(AppIcons.check),
          ),
          findsNothing,
        );
      });

      testUi('切到「并排 Markdown」：左上一版右当前版，删除行 destructive、新增行 brand，系统等宽', (tester) async {
        await _pump(tester, _FakeService(), variant: variant);
        await _chooseMode(tester, '并排 Markdown');
        expectNoUiException(tester);
        final colors = AppColors.resolve(brightness, AccentPreset.meika);

        // 标签换了；两列小标题
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('revision_mode_label'))).data,
          '并排 Markdown',
        );
        expect(find.text('上一版'), findsOneWidget);
        expect(find.text('当前版'), findsOneWidget);
        // 不再有行内的卡片和渲染器
        expect(find.byKey(const ValueKey('revision_diff_card')), findsNothing);

        final deleted = find.byKey(const ValueKey('revision_md_deleted'));
        final added = find.byKey(const ValueKey('revision_md_added'));
        expect(deleted, findsOneWidget);
        expect(added, findsOneWidget);
        // 删除在左、新增在右
        expect(tester.getCenter(deleted).dx, lessThan(tester.getCenter(added).dx));

        TextSpan spanOf(Finder cell) => tester
            .widget<Text>(find.descendant(of: cell, matching: find.byType(Text)))
            .textSpan! as TextSpan;
        final delSpan = spanOf(deleted);
        final addSpan = spanOf(added);
        expect(delSpan.toPlainText(), '- 示例删除行');
        expect(addSpan.toPlainText(), '+ 示例新增行');
        expect(delSpan.style!.color, colors.textDestructive);
        expect(addSpan.style!.color, colors.brandPrimary);
        // 源码用系统等宽（D37）
        expect(delSpan.style!.fontFamily, 'SF Mono');
        expect(delSpan.style!.fontFamilyFallback, contains('monospace'));
      });

      testUi('切到「渲染后对比」：左右两列渲染器，带上一版 / 当前版小标题；再切回行内差异', (tester) async {
        await _pump(tester, _FakeService(), variant: variant);
        await _chooseMode(tester, '渲染后对比');
        expectNoUiException(tester);
        expect(find.text('上一版'), findsOneWidget);
        expect(find.text('当前版'), findsOneWidget);
        final html = _renderedHtml(tester);
        expect(html, hasLength(2));
        expect(html[0], contains('示例：上一版正文'));
        expect(html[1], contains('示例：当前版正文'));

        await _chooseMode(tester, '行内差异');
        expect(find.byKey(const ValueKey('revision_diff_card')), findsOneWidget);
        expect(_renderedHtml(tester), hasLength(1));
      });
    });
  }

  testUi('点右箭头 / 左箭头：请求下一版 / 上一版', (tester) async {
    final service = _FakeService();
    await _pump(tester, service);
    await tester.tap(find.byKey(const ValueKey('revision_next')));
    await tester.pumpAndSettle();
    expect(service.requested, [3]);
    await tester.tap(find.byKey(const ValueKey('revision_previous')));
    await tester.pumpAndSettle();
    expect(service.requested, [3, 2]);
  });

  testUi('只有一个版本：不画切换箭头，对比方式仍在', (tester) async {
    await _pump(tester, _FakeService(single: true));
    expect(find.byKey(const ValueKey('revision_previous')), findsNothing);
    expect(find.byKey(const ValueKey('revision_next')), findsNothing);
    expect(find.text('上一版 → 当前版'), findsOneWidget);
    expect(find.byKey(const ValueKey('revision_mode_menu')), findsOneWidget);
  });
}
