/// 回答里有外部工具给的内容时的渲染保护：渲染本身不能因为这些内容去发请求。
///
/// 把会自动加载外部资源的 Markdown 写法改成普通链接（用户点了才会打开）：
/// - 图片 `![alt](url)`、`![alt][ref]`、`<img src="url">` → 「[图片：alt](url)」；
/// - 单独占一行的网址（会被渲染成预览卡片）→ 「[链接：域名](url)」。
abstract final class ExternalContent {
  static final _image = RegExp(r'!\[([^\]]*)\]\(\s*([^)\s]+)(?:\s+"[^"]*")?\s*\)');
  static final _imageRef = RegExp(r'!\[([^\]]*)\]\[([^\]]*)\]');
  static final _imgTag = RegExp(r'''<img\b[^>]*?\bsrc\s*=\s*["']([^"']+)["'][^>]*>''', caseSensitive: false);
  static final _altAttr = RegExp(r'''\balt\s*=\s*["']([^"']*)["']''', caseSensitive: false);
  static final _bareUrl = RegExp(r'^\s*<?(https?://[^\s<>]+)>?\s*$');

  static String _label(String alt) => alt.trim().isEmpty ? '图片' : '图片：${alt.trim()}';

  static String defang(String markdown) {
    var s = markdown.replaceAllMapped(_imgTag, (m) {
      final alt = _altAttr.firstMatch(m.group(0)!)?.group(1) ?? '';
      return '[${_label(alt)}](${m.group(1)})';
    });
    s = s.replaceAllMapped(_image, (m) => '[${_label(m.group(1)!)}](${m.group(2)})');
    s = s.replaceAllMapped(_imageRef, (m) => '[${_label(m.group(1)!)}][${m.group(2)}]');
    return s
        .split('\n')
        .map((line) {
          final m = _bareUrl.firstMatch(line);
          if (m == null) return line;
          final url = m.group(1)!;
          final host = Uri.tryParse(url)?.host ?? url;
          return '[链接：$host]($url)';
        })
        .join('\n');
  }
}
