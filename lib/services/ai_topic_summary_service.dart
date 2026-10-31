import 'package:ai_model_manager/ai_model_manager.dart';

import '../models/topic.dart';
import 'ai_translation_service.dart';

/// 局部总结里的一个要点：正文 + 依据的楼层号
class SegmentPoint {
  const SegmentPoint({required this.text, this.floors = const []});

  final String text;
  final List<int> floors;
}

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
  ///
  /// [segment] 为 true 时用「按楼层段总结」的提示词（要点 + 楼层号），
  /// 配合 [parseSegmentSummary] 解析。
  Stream<String> summarizeStream({
    required AiProvider provider,
    required AiModel model,
    required String apiKey,
    required String input,
    bool segment = false,
  }) async* {
    final stream = _chatService.sendChatStream(
      provider: provider,
      model: model.id,
      apiKey: apiKey,
      systemPrompt: segment ? segmentSystemPrompt : systemPrompt,
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

  /// 取已加载楼层里楼层号在 [from]–[to]（含）的部分，拼成输入。
  /// [from]、[to] 为空表示不限。
  static ({String text, bool truncated, int postCount}) buildSegmentInput({
    required String title,
    required List<Post> posts,
    int? from,
    int? to,
  }) => buildInput(
    title: title,
    posts: [
      for (final p in posts)
        if ((from == null || p.postNumber >= from) &&
            (to == null || p.postNumber <= to))
          p,
    ],
  );

  /// 解析「按楼层段总结」的输出：每行一个要点，行尾（或行内）的
  /// 「#12」「#12、#15」是这个要点对应的楼层。
  /// 没有按要点格式输出时整段当作一个要点，不丢内容。
  static List<SegmentPoint> parseSegmentSummary(String raw) {
    final points = <SegmentPoint>[];
    final bullet = RegExp(r'^\s*(?:[-*•·]|\d+[.、)])\s*');
    final floorRe = RegExp(r'#(\d{1,6})');
    for (final line in raw.split('\n')) {
      if (line.trim().isEmpty) continue;
      if (!bullet.hasMatch(line)) {
        // 续行：并进上一个要点
        if (points.isNotEmpty) {
          final last = points.removeLast();
          points.add(_point('${last.text} ${line.trim()}', floorRe));
        } else {
          points.add(_point(line.trim(), floorRe));
        }
        continue;
      }
      points.add(_point(line.replaceFirst(bullet, '').trim(), floorRe));
    }
    return points;
  }

  static SegmentPoint _point(String text, RegExp floorRe) {
    final floors = <int>[];
    for (final m in floorRe.allMatches(text)) {
      final n = int.parse(m.group(1)!);
      if (!floors.contains(n)) floors.add(n);
    }
    // 行尾括号里只放楼层号的部分从正文里去掉，楼层号单独显示成可点的标签
    final cleaned = text
        .replaceAll(RegExp(r'[（(]\s*(?:#\d+[\s,，、和]*)+[）)]\s*$'), '')
        .replaceAll(RegExp(r'\s*(?:#\d+[\s,，、和]*)+$'), '')
        .trim();
    return SegmentPoint(text: cleaned.isEmpty ? text : cleaned, floors: floors);
  }

  static const String segmentSystemPrompt = '''
你是论坛话题总结助手。用户会发来一个论坛话题的标题和其中一段楼层的内容（格式为「#楼层号 @用户名：正文」）。
请用简体中文只总结这一段楼层，输出 3 到 6 条要点：

- 每条要点单独一行，以「- 」开头；
- 每条要点末尾用「#楼层号」标出依据的楼层，多个楼层用顿号隔开，例如「- 楼主说明了安装步骤 #1、#3」；
- 数字、条件、步骤、链接保持原样；有明显分歧时各写一条。

要求：只依据给出的内容，不要编造；不要前言、标题或结语；每条不超过 60 字。
''';

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
