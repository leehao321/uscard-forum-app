import 'package:ai_model_manager/ai_model_manager.dart';

import '../models/topic.dart';
import 'ai_translation_service.dart';

/// 话题 AI 总结服务。
///
/// 只总结 App 里已经加载出来的楼层，不额外请求论坛；
/// 模型调用走用户自己在设置里配置的 API Key。
class AiTopicSummaryService {
  AiTopicSummaryService({required AiChatService chatService})
    : _chatService = chatService;

  final AiChatService _chatService;

  /// 送给模型的正文字符上限，超出会截断（用户自己的 API Key，避免烧 token）。
  static const int maxInputChars = 24000;

  /// 单个楼层最多取的字符数，防止某一层的长日志占满上下文。
  static const int maxCharsPerPost = 2500;

  /// 把已加载的楼层拼成给模型看的纯文本，返回文本、是否被截断和实际使用的楼层数。
  static ({String text, bool truncated, int postCount}) buildInput({
    required String title,
    required List<Post> posts,
  }) {
    final buffer = StringBuffer('话题标题：$title\n\n');
    var truncated = false;
    var count = 0;
    for (final post in posts) {
      var body = AiTranslationService.extractPlainText(post.cooked);
      if (body.isEmpty) continue;
      if (body.length > maxCharsPerPost) {
        body = '${body.substring(0, maxCharsPerPost)}…';
        truncated = true;
      }
      final entry = '#${post.postNumber} @${post.username}：\n$body\n\n';
      if (buffer.length + entry.length > maxInputChars) {
        truncated = true;
        break;
      }
      buffer.write(entry);
      count++;
    }
    return (
      text: buffer.toString().trimRight(),
      truncated: truncated,
      postCount: count,
    );
  }

  /// 流式生成总结，每个事件是一段增量文本。
  Stream<String> summarizeStream({
    required AiProvider provider,
    required AiModel model,
    required String apiKey,
    required String input,
  }) async* {
    final stream = _chatService.sendChatStream(
      provider: provider,
      model: model.id,
      apiKey: apiKey,
      systemPrompt: systemPrompt,
      messages: [
        AiChatMessage(
          id: 'summary-request',
          role: ChatRole.user,
          content: input,
          createdAt: DateTime.now(),
        ),
      ],
      thinkingConfig: const ThinkingConfig(),
    );
    await for (final chunk in stream) {
      if (chunk is TextDelta) yield chunk.text;
    }
  }

  static const String systemPrompt = '''
你是论坛话题总结助手。用户会发来一个论坛话题的标题和各楼层内容（格式为「#楼层号 @用户名：正文」）。
请用简体中文总结：

1. 先用一两句话概括话题在讨论什么。
2. 再用要点列出主要观点、结论和有价值的信息（数字、条件、步骤、链接保持原样）。
3. 如果有明显的分歧或争议，单独列出各方看法；如果有被多人认可的结论，标出来。
4. 引用具体楼层时写成「#楼层号」。

要求：只依据给出的内容，不要编造；不要输出前言或「以下是总结」之类的话；整体控制在 400 字以内。
''';
}
