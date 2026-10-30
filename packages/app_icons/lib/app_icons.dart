/// app_icons —— 全局图标库（0.4.0 起是 Lucide + 自绘）。
///
/// 业务方只 `import 'package:app_icons/app_icons.dart';`，用 [AppIcons] 里的
/// 语义常量；自绘场景用 [AppCustomIcon]/[AppIcon]；规则细节见
/// src/app_icons.dart 头注释。
///
/// 迁移期仍导出 Material Symbols 的 [Symbols]：页面里还没迁完的旧图标
/// 继续可用，tool/ui_audit.dart 统计其数量，全部迁完（M10）后去掉。
library;

export 'package:material_symbols_icons/symbols.dart' show Symbols;

export 'src/app_icon.dart';
export 'src/app_icons.dart';
export 'src/icon_painters.dart';
