import 'package:flutter/painting.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// 编辑历史 diff 的纯函数：给后端返回的 HTML 着色、把「并排 Markdown」的
/// 表格拆成行。不依赖 Flutter 组件，方便单测。

String _hex(Color c) {
  final rgb = c.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0')}';
}

/// 给「行内差异 / 渲染后对比」的 HTML 着色（补充稿 29）：
/// 新增（`<ins>`）用 [insColor]（brand/primary），去掉默认的下划线；
/// 删除（`<del>`）用 [delColor]（text/destructive），保留删除线。
///
/// 渲染器认 `<span style="color:…">`，所以把颜色写进内层 span。
String colorizeDiffHtml(
  String html, {
  required Color insColor,
  required Color delColor,
}) {
  final ins = _hex(insColor);
  final del = _hex(delColor);
  var out = html.replaceAllMapped(
    RegExp(r'<ins\b[^>]*>', caseSensitive: false),
    (_) => '<span style="color:$ins">',
  );
  out = out.replaceAll(RegExp(r'</ins\s*>', caseSensitive: false), '</span>');
  out = out.replaceAllMapped(
    RegExp(r'<del\b[^>]*>', caseSensitive: false),
    (_) => '<del><span style="color:$del">',
  );
  out = out.replaceAll(
    RegExp(r'</del\s*>', caseSensitive: false),
    '</span></del>',
  );
  return out;
}

/// 并排 Markdown 里一行文字的状态
enum DiffLineKind {
  /// 没改
  common,

  /// 这一行被删（上一版里有，当前版里没有）
  deleted,

  /// 这一行是新增（当前版里才有）
  added,
}

/// 一行里的一段文字：[changed] 表示它在行内被改（`<ins>` / `<del>` 包着的）
class DiffSegment {
  const DiffSegment(this.text, {this.changed = false});

  final String text;
  final bool changed;

  @override
  bool operator ==(Object other) =>
      other is DiffSegment && other.text == text && other.changed == changed;

  @override
  int get hashCode => Object.hash(text, changed);

  @override
  String toString() => 'DiffSegment($text${changed ? ', changed' : ''})';
}

/// 并排 Markdown 的一格（某一版里的一行）
class DiffCell {
  const DiffCell({required this.kind, required this.segments});

  final DiffLineKind kind;
  final List<DiffSegment> segments;

  bool get isEmpty => segments.every((s) => s.text.isEmpty);

  String get plainText => segments.map((s) => s.text).join();
}

/// 并排 Markdown 的一行：左 = 上一版，右 = 当前版
class DiffRow {
  const DiffRow({required this.previous, required this.current});

  final DiffCell previous;
  final DiffCell current;
}

/// 拆后端的并排 Markdown 表格：
/// `<table class="markdown"><tr><td class="diff-del">…</td><td class="diff-ins">…</td></tr>…`，
/// 每行两个 td；td 的 class 里带 `diff-del` 表示这格被删，带 `diff-ins` 表示新增。
/// 没有任何一行时返回 null，调用方走原样渲染。
List<DiffRow>? parseMarkdownDiffRows(String raw) {
  final rowPattern = RegExp(
    r'<tr>\s*<td(?:\s+class="([^"]*?)")?>([\s\S]*?)</td>\s*<td(?:\s+class="([^"]*?)")?>([\s\S]*?)</td>\s*</tr>',
    caseSensitive: false,
  );
  final matches = rowPattern.allMatches(raw).toList();
  if (matches.isEmpty) return null;
  return [
    for (final m in matches)
      DiffRow(
        previous: _cell(m.group(1), m.group(2) ?? ''),
        current: _cell(m.group(3), m.group(4) ?? ''),
      ),
  ];
}

DiffCell _cell(String? classes, String html) {
  final c = classes ?? '';
  final kind = c.contains('diff-del')
      ? DiffLineKind.deleted
      : c.contains('diff-ins')
      ? DiffLineKind.added
      : DiffLineKind.common;
  return DiffCell(kind: kind, segments: _segments(html));
}

/// 把一格的 HTML（只有转义文字和 `<ins>` / `<del>`）展平成文字段
List<DiffSegment> _segments(String html) {
  final fragment = html_parser.parseFragment(html);
  final out = <DiffSegment>[];
  void walk(dom.Node node, bool changed) {
    if (node is dom.Text) {
      if (node.text.isNotEmpty) out.add(DiffSegment(node.text, changed: changed));
      return;
    }
    if (node is dom.Element) {
      final tag = node.localName;
      if (tag == 'br') {
        out.add(DiffSegment('\n', changed: changed));
        return;
      }
      final inner = changed || tag == 'ins' || tag == 'del';
      for (final child in node.nodes) {
        walk(child, inner);
      }
    }
  }

  for (final node in fragment.nodes) {
    walk(node, false);
  }
  return out;
}
