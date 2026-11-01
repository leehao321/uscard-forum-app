import '../models/ai_provider.dart';

/// 工具参数 schema 的清洗：外部来源（比如远程 MCP 服务）的 inputSchema 可以带各种
/// 关键字，而各家模型接口只认其中一部分，多余的键会让请求直接 400。
abstract final class ToolSchema {
  /// 所有服务商都不需要、有的会拒收的元数据键
  static const _meta = {r'$schema', r'$id', r'$comment'};

  /// Gemini 的 Schema 只认这些键
  static const _geminiKeys = {
    'type',
    'format',
    'description',
    'nullable',
    'enum',
    'properties',
    'required',
    'items',
    'minItems',
    'maxItems',
    'minimum',
    'maximum',
    'title',
    'anyOf',
    'propertyOrdering',
  };

  /// 按服务商清洗。根一定是 `type: object` + `properties`。
  static Map<String, Object?> clean(Map<String, Object?> schema, AiProviderType type) {
    final gemini = type == AiProviderType.gemini;
    final out = _clean(schema, gemini);
    out['type'] = 'object';
    if (out['properties'] is! Map) out['properties'] = <String, Object?>{};
    return out;
  }

  static Map<String, Object?> _clean(Map schema, bool gemini) {
    final out = <String, Object?>{};
    for (final e in schema.entries) {
      final key = '${e.key}';
      if (_meta.contains(key)) continue;
      if (gemini && !_geminiKeys.contains(key)) continue;
      final v = e.value;
      switch (key) {
        case 'properties':
          // properties 的键是参数名，值才是 schema
          out[key] = v is Map
              ? {
                  for (final p in v.entries)
                    '${p.key}': p.value is Map ? _clean(p.value as Map, gemini) : p.value,
                }
              : v;
        case 'items':
          out[key] = v is Map ? _clean(v, gemini) : v;
        case 'anyOf' || 'oneOf' || 'allOf':
          out[key] = v is List ? [for (final s in v) s is Map ? _clean(s, gemini) : s] : v;
        case 'type':
          if (gemini && v is List) {
            // Gemini 的 type 只能是单个字符串：["string","null"] → string + nullable
            final names = [for (final t in v) '$t'];
            final main = names.firstWhere((t) => t != 'null', orElse: () => 'string');
            out[key] = main;
            if (names.contains('null')) out['nullable'] = true;
          } else {
            out[key] = v;
          }
        default:
          out[key] = v;
      }
    }
    // 数组一定要有 items，不然 Gemini / OpenAI 都会拒
    if (out['type'] == 'array' && out['items'] is! Map) {
      out['items'] = <String, Object?>{'type': 'string'};
    }
    return out;
  }
}
