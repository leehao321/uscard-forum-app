import 'dart:async';

import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:dio/dio.dart';

import 'ai_translation_service.dart';
import 'quick_translation_service.dart';

/// 翻译来源。
enum TranslationSource {
  /// Google 网页翻译：免 Key，默认。
  google,

  /// 用户在「AI 模型服务」里配置的模型。
  ai,

  /// B 站 Index：只占位。没有找到可以验证的公开接口，设置里显示为不可选。
  bilibiliIndex;

  bool get available => this != TranslationSource.bilibiliIndex;
}

/// 把一个楼层翻译成目标语言。
// ignore: one_member_abstracts
abstract interface class TranslationEngine {
  Future<QuickTranslation> translatePost({
    required String cookedHtml,
    required String targetLanguage,
    CancelToken? cancelToken,
  });
}

/// 选了 AI 但没有可用模型。
class TranslationUnavailableException implements Exception {
  const TranslationUnavailableException();
}

class UnavailableTranslationEngine implements TranslationEngine {
  const UnavailableTranslationEngine();

  @override
  Future<QuickTranslation> translatePost({
    required String cookedHtml,
    required String targetLanguage,
    CancelToken? cancelToken,
  }) => Future.error(const TranslationUnavailableException());
}

/// 用 AI 模型翻译。费用记在用户自己的 API Key 上。
class AiTranslationEngine implements TranslationEngine {
  AiTranslationEngine({
    required AiTranslationService service,
    required AiProvider provider,
    required AiModel model,
    Future<String?> Function(String providerId)? readApiKey,
  }) : _service = service,
       _provider = provider,
       _model = model,
       _readApiKey = readApiKey ?? AiProviderListNotifier.getApiKey;

  final AiTranslationService _service;
  final AiProvider _provider;
  final AiModel _model;
  final Future<String?> Function(String providerId) _readApiKey;

  @override
  Future<QuickTranslation> translatePost({
    required String cookedHtml,
    required String targetLanguage,
    CancelToken? cancelToken,
  }) async {
    final clamped = AiTranslationService.clampForTranslation(
      QuickTranslationService.translatableText(cookedHtml),
    );
    if (clamped.text.isEmpty) {
      return const QuickTranslation(
        text: '',
        sourceLanguage: null,
        truncated: false,
      );
    }
    final apiKey = await _readApiKey(_provider.id);
    if (apiKey == null || apiKey.isEmpty) {
      throw const TranslationUnavailableException();
    }

    final buffer = StringBuffer();
    final done = Completer<void>();
    final subscription = _service
        .translateStream(
          provider: _provider,
          model: _model,
          apiKey: apiKey,
          text: clamped.text,
          targetLanguage: targetLanguage,
        )
        .listen(
          buffer.write,
          onError: (Object e, StackTrace s) {
            if (!done.isCompleted) done.completeError(e, s);
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
        );
    unawaited(
      cancelToken?.whenCancel.then((_) {
        unawaited(subscription.cancel());
        if (!done.isCompleted) {
          done.completeError(StateError('translation cancelled'));
        }
      }),
    );
    await done.future;
    return QuickTranslation(
      text: buffer.toString().trim(),
      sourceLanguage: null,
      truncated: clamped.truncated,
    );
  }
}

/// 原文大概率已经是目标语言：全帖翻译时跳过，不把中文帖一条条发出去再原样收回。
///
/// 只判断简体中文这一种。繁简靠字符比例分不出来，其他语言也没有可靠的简单办法，
/// 判断不了的照常翻译。单楼手动翻译不走这里。
bool likelyAlreadyInTarget(String text, String targetLanguage) {
  if (targetLanguage != 'zh-CN') return false;
  var cjk = 0;
  var letters = 0;
  for (final rune in text.runes) {
    if (rune >= 0x4E00 && rune <= 0x9FFF) {
      cjk++;
      letters++;
    } else if ((rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A)) {
      letters++;
    } else if ((rune >= 0x3040 && rune <= 0x30FF) || (rune >= 0xAC00 && rune <= 0xD7AF)) {
      // 日文假名、韩文：是外语
      return false;
    }
  }
  if (letters == 0) return true;
  // 英文字母一个词好几个，中文帖夹几个词也常见，门槛放低一点
  return cjk / letters >= 0.4;
}
