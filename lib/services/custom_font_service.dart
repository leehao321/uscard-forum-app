import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 导入的字体。
@immutable
class CustomFont {
  const CustomFont({required this.family, required this.displayName});

  /// 注册给引擎的字体族名，写进 `ThemeData.fontFamily`
  final String family;

  /// 给人看的名字（文件名）
  final String displayName;
}

enum CustomFontError { notAFont, tooLarge, readFailed }

class CustomFontException implements Exception {
  const CustomFontException(this.error);

  final CustomFontError error;

  @override
  String toString() => 'CustomFontException($error)';
}

/// 导入本地字体（.ttf / .otf）：复制到 `documents/fonts/`，运行时注册。
///
/// 这是全局设置，不分论坛。iOS 升级后沙盒路径会变，所以只存文件名。
class CustomFontService {
  CustomFontService({
    required SharedPreferences prefs,
    Future<Directory> Function()? documents,
    Future<void> Function(String family, Uint8List bytes)? register,
  }) : _prefs = prefs,
       _documents = documents ?? getApplicationDocumentsDirectory,
       _register = register ?? _registerWithEngine;

  static const fileKey = 'custom_font_file';
  static const nameKey = 'custom_font_name';

  /// 中文字体十几 MB 很常见；再大基本不是正常字体，读进内存也吃不消。
  static const maxBytes = 64 * 1024 * 1024;

  /// 本次运行已注册的字体。主题启动时同步读它，所以要在第一帧之前 [loadSaved]。
  static CustomFont? current;

  final SharedPreferences _prefs;
  final Future<Directory> Function() _documents;
  final Future<void> Function(String family, Uint8List bytes) _register;

  static Future<void> _registerWithEngine(String family, Uint8List bytes) {
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    return loader.load();
  }

  /// 文件头：TrueType（00 01 00 00 或 true）、OpenType（OTTO）。
  /// 引擎收到坏数据不报错，只是静默不生效，所以这里要拦。
  static bool looksLikeFont(Uint8List bytes) {
    if (bytes.length < 12) return false;
    final h = bytes.sublist(0, 4);
    final trueType =
        (h[0] == 0 && h[1] == 1 && h[2] == 0 && h[3] == 0) ||
        String.fromCharCodes(h) == 'true';
    final openType = String.fromCharCodes(h) == 'OTTO';
    if (!trueType && !openType) return false;
    // 紧跟着是表的数量，真字体不会是 0
    final tables = (bytes[4] << 8) | bytes[5];
    return tables > 0;
  }

  /// 同样内容同一个族名：引擎不能卸载字体，换内容必须换名字才生效。
  static String familyFor(Uint8List bytes) =>
      'PulseCustomFont_${sha256.convert(bytes).toString().substring(0, 12)}';

  Future<Directory> _fontsDir() async {
    final docs = await _documents();
    return Directory(p.join(docs.path, 'fonts'));
  }

  /// 导入 [sourcePath]，成功后立即可用，旧的字体文件删掉。
  Future<CustomFont> importFile(String sourcePath, {String? displayName}) async {
    final source = File(sourcePath);
    final Uint8List bytes;
    try {
      if (await source.length() > maxBytes) {
        throw const CustomFontException(CustomFontError.tooLarge);
      }
      bytes = await source.readAsBytes();
    } on FileSystemException {
      throw const CustomFontException(CustomFontError.readFailed);
    }
    if (!looksLikeFont(bytes)) {
      throw const CustomFontException(CustomFontError.notAFont);
    }

    final family = familyFor(bytes);
    final ext = p.extension(sourcePath).toLowerCase() == '.otf' ? '.otf' : '.ttf';
    final fileName = '$family$ext';
    final dir = await _fontsDir();
    await dir.create(recursive: true);
    await File(p.join(dir.path, fileName)).writeAsBytes(bytes, flush: true);
    await _register(family, bytes);

    final previous = _prefs.getString(fileKey);
    final name = displayName ?? p.basenameWithoutExtension(sourcePath);
    await _prefs.setString(fileKey, fileName);
    await _prefs.setString(nameKey, name);
    if (previous != null && previous != fileName) {
      try {
        await File(p.join(dir.path, previous)).delete();
      } on FileSystemException catch (e) {
        debugPrint('[CustomFont] 删除旧字体失败: ${e.osError?.errorCode}');
      }
    }
    return current = CustomFont(family: family, displayName: name);
  }

  /// 启动时重新注册。文件没了（比如备份恢复到新设备）或坏了就当没有，不影响启动。
  Future<CustomFont?> loadSaved() async {
    current = null;
    final fileName = _prefs.getString(fileKey);
    if (fileName == null) return null;
    try {
      final dir = await _fontsDir();
      final bytes = await File(p.join(dir.path, fileName)).readAsBytes();
      if (!looksLikeFont(bytes)) return null;
      final family = familyFor(bytes);
      await _register(family, bytes);
      return current = CustomFont(
        family: family,
        displayName: _prefs.getString(nameKey) ?? fileName,
      );
    } catch (e) {
      debugPrint('[CustomFont] 加载失败: ${e.runtimeType}');
      return null;
    }
  }
}
