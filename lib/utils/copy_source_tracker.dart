import 'package:flutter/services.dart';

/// 记住「最近一次从哪一楼复制了哪段文字」，笔记的「粘贴为摘录」据此记录来源楼层。
///
/// 只存最近一次；剪贴板里的文字和记录对不上（用户在别处复制过）就不认。
class CopySourceTracker {
  CopySourceTracker._();

  static String? _text;
  static int? _postNumber;

  /// 在复制完成的回调里调用：读剪贴板内容并和楼层绑定。
  static Future<void> note(int postNumber) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    _text = data?.text?.trim();
    _postNumber = postNumber;
  }

  /// 同步登记（已知文字时用，不用再读剪贴板）。
  static void noteText(String text, int postNumber) {
    _text = text.trim();
    _postNumber = postNumber;
  }

  /// [text] 是最近一次从某一楼复制的文字时返回那一楼，否则 null。
  static int? sourceFor(String text) {
    final recorded = _text;
    if (recorded == null || recorded.isEmpty) return null;
    return recorded == text.trim() ? _postNumber : null;
  }

  static void reset() {
    _text = null;
    _postNumber = null;
  }
}
