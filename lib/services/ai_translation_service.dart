import 'package:html/parser.dart' as html_parser;

/// 帖子正文转成可翻译文本的工具。
class AiTranslationService {
  AiTranslationService._();

  /// 单次送翻的字符上限。超长帖(转录、日志贴)超限截到段落边界,
  /// UI 侧注明只翻译了开头部分。
  static const int maxTranslateChars = 16000;

  /// 超过 [maxTranslateChars] 时截断,尽量截在换行处避免劈开句子。
  static ({String text, bool truncated}) clampForTranslation(String text) {
    if (text.length <= maxTranslateChars) {
      return (text: text, truncated: false);
    }
    var cut = text.lastIndexOf('\n', maxTranslateChars);
    if (cut < maxTranslateChars ~/ 2) cut = maxTranslateChars;
    return (text: text.substring(0, cut).trimRight(), truncated: true);
  }

  /// cooked HTML 转为供翻译的纯文本。
  static String extractPlainText(String cookedHtml) {
    final document = html_parser.parse(cookedHtml);
    for (final img in document.querySelectorAll('img')) {
      final alt = img.attributes['alt'];
      img.replaceWith(
        html_parser.parseFragment(alt != null && alt.isNotEmpty ? alt : ''),
      );
    }
    final text = document.body?.text ?? cookedHtml;
    return text
        .replaceAll(RegExp(r'\r\n?'), '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
