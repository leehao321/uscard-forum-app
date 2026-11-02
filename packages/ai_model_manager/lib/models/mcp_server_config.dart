import '../utils/tool_schema.dart';

/// 远程 MCP 服务的敏感部分：Bearer Token 和自定义请求头。
/// 只存在系统安全存储里，不进 SharedPreferences，也不进数据备份。
class McpSecrets {
  const McpSecrets({this.bearerToken = '', this.headers = const {}});

  final String bearerToken;
  final Map<String, String> headers;

  bool get isEmpty => bearerToken.isEmpty && headers.isEmpty;

  Map<String, Object?> toJson() => {'token': bearerToken, 'headers': headers};

  factory McpSecrets.fromJson(Map<String, dynamic> j) => McpSecrets(
    bearerToken: j['token'] as String? ?? '',
    headers: {
      for (final e in (j['headers'] as Map? ?? const {}).entries)
        '${e.key}': '${e.value}',
    },
  );
}

/// 一个远程 MCP 服务的配置。
///
/// 公开部分（名称、地址、开关、每个工具的启用状态）存在 SharedPreferences；
/// 敏感部分见 [McpSecrets]，单独存安全存储。
class McpServerConfig {
  const McpServerConfig({
    required this.id,
    required this.name,
    required this.url,
    this.enabled = true,
    this.toolStates = const {},
  });

  final String id;
  final String name;

  /// Streamable HTTP 的 Endpoint URL
  final String url;
  final bool enabled;

  /// 工具名 → 是否启用。没出现的工具按默认规则决定（见 [McpToolInfo.defaultEnabled]）
  final Map<String, bool> toolStates;

  /// 地址不是 https（明文传输）
  bool get isPlainHttp => Uri.tryParse(url.trim())?.scheme.toLowerCase() == 'http';

  McpServerConfig copyWith({
    String? name,
    String? url,
    bool? enabled,
    Map<String, bool>? toolStates,
  }) => McpServerConfig(
    id: id,
    name: name ?? this.name,
    url: url ?? this.url,
    enabled: enabled ?? this.enabled,
    toolStates: toolStates ?? this.toolStates,
  );

  /// 只含公开部分：这里**没有** Token 和请求头
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'enabled': enabled,
    'tools': toolStates,
  };

  factory McpServerConfig.fromJson(Map<String, dynamic> j) => McpServerConfig(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    url: j['url'] as String? ?? '',
    enabled: j['enabled'] as bool? ?? true,
    toolStates: {
      for (final e in (j['tools'] as Map? ?? const {}).entries)
        '${e.key}': e.value == true,
    },
  );
}

/// 服务端 `tools/list` 返回的一个工具
class McpToolInfo {
  const McpToolInfo({
    required this.name,
    this.title,
    this.description = '',
    this.inputSchema = const {'type': 'object', 'properties': {}},
    this.readOnlyHint,
    this.destructiveHint,
  });

  final String name;
  final String? title;
  final String description;
  final Map<String, Object?> inputSchema;

  /// `annotations.readOnlyHint`
  final bool? readOnlyHint;

  /// `annotations.destructiveHint`
  final bool? destructiveHint;

  /// 默认只开明确标了只读的工具；没有标注、或标了会破坏数据的默认关
  bool get defaultEnabled => readOnlyHint == true && destructiveHint != true;

  /// 这个工具可能会修改数据（不是明确只读）：手动打开时要提示
  bool get mayModify => !defaultEnabled;

  /// 工具名、说明都来自外部服务，不是可信内容：说明截到这么多字
  static const maxDescriptionChars = 1000;

  static String? _str(Object? v) => v is String ? v : null;
  static bool? _bool(Object? v) => v is bool ? v : null;

  /// 外部服务给的字段类型不对时不抛错：当成没有
  factory McpToolInfo.fromJson(Map<String, dynamic> j) {
    final ann = j['annotations'];
    final description = _str(j['description']) ?? '';
    final title = _str(j['title']) ?? (ann is Map ? _str(ann['title']) : null);
    return McpToolInfo(
      name: _str(j['name']) ?? '',
      title: title == null ? null : _cut(title, 100),
      description: _cut(description, maxDescriptionChars),
      inputSchema: j['inputSchema'] is Map
          ? ToolSchema.capDescriptions(Map<String, Object?>.from(j['inputSchema'] as Map), maxDescriptionChars)
          : const {'type': 'object', 'properties': {}},
      readOnlyHint: ann is Map ? _bool(ann['readOnlyHint']) : null,
      destructiveHint: ann is Map ? _bool(ann['destructiveHint']) : null,
    );
  }

  static String _cut(String s, int n) => s.length <= n ? s : '${s.substring(0, n)}…';
}
