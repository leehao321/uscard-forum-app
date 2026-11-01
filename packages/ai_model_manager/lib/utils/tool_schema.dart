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

  /// Gemini 认的 format（string 上）
  static const _geminiFormats = {'enum', 'date-time'};

  /// 内联 `$ref` 的最大深度
  static const _refDepth = 3;

  /// 把 schema 里所有层级的 `description` 截到 [limit] 字（外部来源的说明不可信，别让它占满上下文）。
  /// `properties` 的键是参数名，不当成 schema 关键字处理。
  static Map<String, Object?> capDescriptions(Map<String, Object?> schema, int limit) {
    Object? walk(Object? v, {bool isProps = false}) {
      if (v is Map) {
        return {
          for (final e in v.entries)
            '${e.key}': isProps
                ? walk(e.value)
                : (e.key == 'description' && e.value is String && (e.value as String).length > limit)
                    ? '${(e.value as String).substring(0, limit)}…'
                    : walk(e.value, isProps: e.key == 'properties'),
        };
      }
      if (v is List) return [for (final x in v) walk(x)];
      return v;
    }

    return walk(schema) as Map<String, Object?>;
  }

  /// 按服务商清洗。根一定是 `type: object` + `properties`。
  static Map<String, Object?> clean(Map<String, Object?> schema, AiProviderType type) {
    final gemini = type == AiProviderType.gemini;
    final defs = <String, Object?>{
      ..._asMap(schema[r'$defs']),
      ..._asMap(schema['definitions']),
    };
    final out = _clean(schema, gemini, defs, 0);
    out['type'] = 'object';
    if (out['properties'] is! Map) out['properties'] = <String, Object?>{};
    if (!gemini) {
      // OpenAI / Anthropic 的根层不接受组合关键字
      out
        ..remove('anyOf')
        ..remove('oneOf')
        ..remove('allOf')
        ..remove('not');
    }
    return out;
  }

  static Map<String, Object?> _asMap(Object? v) =>
      v is Map ? {for (final e in v.entries) '${e.key}': e.value} : <String, Object?>{};

  /// 把 `{"$ref": "#/$defs/X"}` 换成 X 的定义（有限深度，找不到的去掉 $ref）
  static Map _inline(Map schema, Map<String, Object?> defs, int depth) {
    final ref = schema[r'$ref'];
    if (ref is! String) return schema;
    final name = ref.split('/').last;
    final target = defs[name];
    final rest = {for (final e in schema.entries) if (e.key != r'$ref') e.key: e.value};
    if (target is Map && depth < _refDepth) {
      return {...target, ...rest};
    }
    return rest;
  }

  static Map<String, Object?> _clean(Map input, bool gemini, Map<String, Object?> defs, int depth) {
    final schema = gemini ? _inline(input, defs, depth) : input;
    final out = <String, Object?>{};
    for (final e in schema.entries) {
      var key = '${e.key}';
      if (_meta.contains(key)) continue;
      final v = e.value;
      if (gemini) {
        // oneOf → anyOf；const → 单值 enum
        if (key == 'oneOf') key = 'anyOf';
        if (key == 'const') {
          out['enum'] = ['$v'];
          continue;
        }
        if (!_geminiKeys.contains(key)) continue;
      }
      // 内联后的子结构里可能又有 $ref，递归时深度 + 1
      final d = depth + 1;
      switch (key) {
        case 'properties':
          // properties 的键是参数名，值才是 schema
          out[key] = v is Map
              ? {
                  for (final p in v.entries)
                    '${p.key}': p.value is Map ? _clean(p.value as Map, gemini, defs, d) : p.value,
                }
              : v;
        case 'items':
          out[key] = v is Map ? _clean(v, gemini, defs, d) : v;
        case 'anyOf' || 'oneOf' || 'allOf':
          out[key] = v is List ? [for (final s in v) s is Map ? _clean(s, gemini, defs, d) : s] : v;
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
        case 'format':
          // Gemini 只认 enum 和 date-time
          if (!gemini || (v is String && _geminiFormats.contains(v))) out[key] = v;
        case 'enum':
          if (gemini) {
            // 只接受字符串：数字 / 布尔转成字符串，转不了（null、对象、数组）就整个去掉
            if (v is List && v.every((x) => x is String || x is num || x is bool)) {
              out[key] = [for (final x in v) '$x'];
            }
          } else {
            out[key] = v;
          }
        default:
          out[key] = v;
      }
    }
    if (gemini && depth > 0) _geminiFixups(out); // 根层由 clean() 单独保证是 object
    // 数组一定要有 items，不然 Gemini / OpenAI 都会拒
    if (out['type'] == 'array' && out['items'] is! Map) {
      out['items'] = <String, Object?>{'type': 'string'};
    }
    return out;
  }

  /// Gemini 要求：enum 只能配 string；object 一定有 properties（字典形式的改成字符串并写明是 JSON 对象）；
  /// 每个 schema 都有 type
  static void _geminiFixups(Map<String, Object?> out) {
    if (out['enum'] is List && out['type'] != 'string') out['type'] = 'string';
    if (out['type'] == 'object' && !(out['properties'] is Map && (out['properties'] as Map).isNotEmpty)) {
      out['type'] = 'string';
      out.remove('properties');
      out.remove('required');
      final desc = out['description'];
      out['description'] = desc is String && desc.isNotEmpty ? '$desc（JSON 对象，写成字符串）' : 'JSON 对象，写成字符串';
    }
    if (out['type'] == null && out['anyOf'] is! List) {
      out['type'] = out['properties'] is Map
          ? 'object'
          : out['items'] is Map
              ? 'array'
              : 'string';
    }
  }
}
