import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter_test/flutter_test.dart';

// 快捷词的导出能导回来：
// 导出的 JSON 里没有 id（自己生成的 id 不该带出去），导入时要新生成 id；
// 旧的解析要求必须有 id，所以自己导出的内容导回去会失败。

const _preset = PromptPreset(
  id: 'user-1234',
  type: PromptType.image,
  name: '示例快捷词',
  iconRaw: 'sparkles',
  promptTemplate: '画一只{动物}',
  aspectRatio: '16:9',
  tags: ['封面', '插画'],
  pinned: true,
  sortOrder: 3,
);

/// 现在导出的格式（没有 id）
const _exported = <String, dynamic>{
  'type': 'image',
  'name': '示例快捷词',
  'iconRaw': 'sparkles',
  'promptTemplate': '画一只{动物}',
  'aspectRatio': '16:9',
  'tags': ['封面', '插画'],
};

void main() {
  test('导出的内容（不带 id）能被导入的解析读回来，字段一致', () {
    // 导入走的就是 PromptPreset.fromJson（再由导入流程换上新 id）
    final back = PromptPreset.fromJson(_exported);
    expect(back.name, '示例快捷词');
    expect(back.type, PromptType.image);
    expect(back.iconRaw, 'sparkles');
    expect(back.promptTemplate, '画一只{动物}');
    expect(back.aspectRatio, '16:9');
    expect(back.tags, ['封面', '插画']);
  });

  test('带 id 的完整 JSON（应用自己存的格式）照旧能读', () {
    final back = PromptPreset.fromJson(_preset.toJson());
    expect(back.id, 'user-1234');
    expect(back.pinned, isTrue);
    expect(back.sortOrder, 3);
  });
}
