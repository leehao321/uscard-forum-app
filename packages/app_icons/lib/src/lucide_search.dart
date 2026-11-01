import 'package:flutter/widgets.dart';

import 'lucide_catalog.dart';

/// 按英文名取 Lucide 图标（kebab-case，如 `heart-handshake`）；没有返回 null。
IconData? lucideIconByName(String name) => kLucideIconCatalog[name];

/// 按英文名搜索 Lucide 图标，返回匹配的图标名（kebab-case）。
///
/// 查询词忽略大小写，空格和下划线当成连字符。排序：完全相同 → 以查询词开头 →
/// 包含查询词，同一档里按名字字母序。查询词为空返回空列表；最多返回 [limit] 个。
List<String> searchLucideIconNames(String query, {int limit = 60}) {
  final q = query.trim().toLowerCase().replaceAll(RegExp(r'[\s_]+'), '-');
  if (q.isEmpty) return const [];
  final exact = <String>[];
  final prefix = <String>[];
  final contains = <String>[];
  // 目录本身按名字排序，三档各自保持字母序
  for (final name in kLucideIconCatalog.keys) {
    if (name == q) {
      exact.add(name);
    } else if (name.startsWith(q)) {
      prefix.add(name);
    } else if (name.contains(q)) {
      contains.add(name);
    }
  }
  return [...exact, ...prefix, ...contains].take(limit).toList();
}
