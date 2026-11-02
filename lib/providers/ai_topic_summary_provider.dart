import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_post_review_provider.dart';

/// 话题 AI 总结使用的模型：默认文本模型，没有则取第一个可用文本模型；无可用模型为 null。
final aiTopicSummaryModelProvider =
    Provider<({AiProvider provider, AiModel model})?>((ref) {
      return resolveSelectedTextAiModel(ref, null);
    });
