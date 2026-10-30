import 'dart:convert';
import 'dart:io';

import '_workspace_cli.dart';

// 0.4.0 界面审计：统计页面代码里绕开 token / 组件的写法。
//
// 用法：
//   dart tool/ui_audit.dart            对照基线，任何一项「白名单外」计数上升就退出码 1
//   dart tool/ui_audit.dart --detail   另外按目录列出明细
//   dart tool/ui_audit.dart --update   把当前计数写成新基线
//
// 规则见 docs/uscard/0.4.0-plan.md §5 M0 与 §6.3：每个里程碑只降不升，
// M10 时「白名单外」一列降到目标值。整行注释不计；渲染器子模块、
// 生成代码和非界面包不扫。

const _baselinePath = 'tool/ui_audit_baseline.json';

/// 扫描范围：lib 加上界面相关的 workspace 包
const _roots = [
  'lib',
  'packages/ai_model_manager/lib',
  'packages/app_icons/lib',
  'packages/common_ui/lib',
  'packages/m3e_ui/lib',
];

const _skipPrefixes = ['lib/l10n/'];

const _tokenDir = 'packages/common_ui/lib/src/tokens/';

class _Rule {
  final String id;
  final String label;
  final RegExp pattern;

  /// 允许出现的路径前缀（M10 目标里的白名单）
  final List<String> allowed;

  const _Rule(this.id, this.label, this.pattern, {this.allowed = const []});

  bool isAllowed(String path) => allowed.any(path.startsWith);
}

final _rules = <_Rule>[
  _Rule(
    'symbols',
    'Symbols.',
    RegExp(r'\bSymbols\.'),
    allowed: ['packages/app_icons/'],
  ),
  _Rule(
    'icons',
    'Icons.',
    RegExp(r'\bIcons\.'),
    allowed: ['packages/app_icons/'],
  ),
  _Rule(
    'cupertino_icons',
    'CupertinoIcons.',
    RegExp(r'\bCupertinoIcons\.'),
    allowed: ['packages/app_icons/'],
  ),
  _Rule(
    'font_awesome',
    'FontAwesomeIcons.',
    RegExp(r'\bFontAwesomeIcons\.'),
    allowed: ['lib/utils/font_awesome_name_mapping.dart'],
  ),
  _Rule(
    'color_literal',
    'Color(0x',
    RegExp(r'\bColor\(\s*0x'),
    allowed: [_tokenDir],
  ),
  _Rule(
    'colors',
    'Colors.（不含 transparent）',
    RegExp(r'\bColors\.(?!transparent\b)\w+'),
    allowed: [_tokenDir],
  ),
  _Rule(
    'font_size',
    'fontSize: 数字',
    RegExp(r'\bfontSize:\s*\d'),
    allowed: [_tokenDir],
  ),
  _Rule(
    'border_radius',
    'BorderRadius.circular(数字',
    RegExp(r'\bBorderRadius\.circular\(\s*\d'),
    allowed: [_tokenDir],
  ),
  _Rule(
    'radius',
    'Radius.circular(数字',
    RegExp(r'\bRadius\.circular\(\s*\d'),
    allowed: [_tokenDir],
  ),
  _Rule(
    'alert_dialog',
    'AlertDialog(',
    RegExp(r'\bAlertDialog(\.adaptive)?\('),
    allowed: ['packages/common_ui/'],
  ),
  _Rule(
    'modal_sheet',
    'showModalBottomSheet',
    RegExp(r'\bshowModalBottomSheet\b'),
    allowed: ['packages/common_ui/'],
  ),
  _Rule(
    'popup_menu',
    'PopupMenuButton',
    RegExp(r'\bPopupMenuButton\b'),
    allowed: ['packages/common_ui/'],
  ),
  _Rule(
    'dropdown',
    'DropdownButton / DropdownMenu',
    RegExp(r'\bDropdown(Button|ButtonFormField|Menu)\b'),
    allowed: ['packages/common_ui/'],
  ),
  _Rule(
    'show_menu',
    'showMenu(',
    RegExp(r'\bshowMenu\s*[<(]'),
    allowed: ['packages/common_ui/'],
  ),
  _Rule(
    'icon_button',
    '裸 IconButton(',
    RegExp(r'\bIconButton(\.\w+)?\('),
    allowed: ['packages/common_ui/'],
  ),
];

/// 明细分组：lib 下取两级目录，包取包名
String _groupOf(String path) {
  final parts = path.split('/');
  if (parts.first == 'packages') return parts.take(2).join('/');
  // lib/a.dart → lib；lib/x/a.dart → lib/x；lib/x/y/…/a.dart → lib/x/y
  final dirs = parts.length - 1;
  return parts.take(dirs.clamp(1, 3)).join('/');
}

bool _isGenerated(String path) =>
    path.endsWith('.g.dart') ||
    path.endsWith('.freezed.dart') ||
    path.endsWith('.gr.dart');

class _Counts {
  final total = <String, int>{};
  final outside = <String, int>{};
  final byGroup = <String, Map<String, int>>{};

  void add(_Rule rule, String path, int n) {
    total[rule.id] = (total[rule.id] ?? 0) + n;
    if (!rule.isAllowed(path)) {
      outside[rule.id] = (outside[rule.id] ?? 0) + n;
    }
    final group = byGroup.putIfAbsent(rule.id, () => {});
    final key = _groupOf(path);
    group[key] = (group[key] ?? 0) + n;
  }
}

_Counts _scan() {
  final counts = _Counts();
  for (final root in _roots) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (_isGenerated(path) || _skipPrefixes.any(path.startsWith)) continue;
      final code = entity
          .readAsLinesSync()
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      for (final rule in _rules) {
        final n = rule.pattern.allMatches(code).length;
        if (n > 0) counts.add(rule, path, n);
      }
    }
  }
  return counts;
}

Map<String, dynamic>? _readBaseline() {
  final file = File(_baselinePath);
  if (!file.existsSync()) return null;
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void _writeBaseline(_Counts counts) {
  final sortedGroups = {
    for (final rule in _rules)
      rule.id: Map.fromEntries(
        (counts.byGroup[rule.id] ?? {}).entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)),
      ),
  };
  final data = {
    'total': {for (final r in _rules) r.id: counts.total[r.id] ?? 0},
    'outside': {for (final r in _rules) r.id: counts.outside[r.id] ?? 0},
    'byGroup': sortedGroups,
  };
  File(_baselinePath).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(data)}\n',
  );
}

String _pad(Object v, int width, {bool left = false}) {
  final s = '$v';
  // 中文按两列宽估算，表格大致对齐即可
  final w = s.runes.fold<int>(0, (n, r) => n + (r > 0x2E80 ? 2 : 1));
  final fill = ' ' * (width - w).clamp(0, width);
  return left ? '$s$fill' : '$fill$s';
}

void main(List<String> args) {
  enterWorkspaceRoot();
  final update = args.contains('--update');
  final detail = args.contains('--detail');

  final counts = _scan();
  final baseline = _readBaseline();
  // 拦截看「白名单外」：token 定义、图标包、共用外壳里本来就该有这些写法，
  // 搬进去时总数可能上升，但页面里的用量必须只降不升（计划 §6.3）
  final baseOutside =
      (baseline?['outside'] as Map?)?.cast<String, int>() ?? {};

  stdout.writeln(
    '${_pad('写法', 30, left: true)}${_pad('总数', 8)}${_pad('白名单外', 10)}'
    '${_pad('基线', 8)}${_pad('变化', 8)}',
  );
  var regressed = false;
  for (final rule in _rules) {
    final now = counts.outside[rule.id] ?? 0;
    final base = baseOutside[rule.id];
    final delta = base == null ? '' : now - base;
    if (base != null && now > base) regressed = true;
    stdout.writeln(
      '${_pad(rule.label, 30, left: true)}${_pad(counts.total[rule.id] ?? 0, 8)}'
      '${_pad(now, 10)}${_pad(base ?? '-', 8)}'
      '${_pad(delta is int && delta > 0 ? '+$delta' : delta, 8)}',
    );
  }

  if (detail) {
    for (final rule in _rules) {
      final groups = counts.byGroup[rule.id];
      if (groups == null || groups.isEmpty) continue;
      stdout.writeln('\n${rule.label}');
      final entries = groups.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in entries) {
        stdout.writeln('  ${_pad(e.value, 6)}  ${e.key}');
      }
    }
  }

  if (update) {
    _writeBaseline(counts);
    stdout.writeln('\n已写入基线 $_baselinePath');
    return;
  }
  if (baseline == null) {
    stdout.writeln('\n没有基线，先运行 --update');
    return;
  }
  if (regressed) {
    stderr.writeln('\n有写法比基线多了：新代码请改用 token 和 common_ui 组件');
    exitCode = 1;
  } else {
    stdout.writeln('\n没有比基线多的写法');
  }
}
