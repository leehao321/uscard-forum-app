import 'dart:async';

import 'package:ai_model_manager/ai_model_manager.dart'
    show aiSharedPreferencesProvider;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/providers/user_content_providers.dart'
    show currentUsernameProvider;
import 'package:shared_preferences/shared_preferences.dart';

// 第 11 批 · 11c-1 各测试共用的假依赖：假偏好存储、未登录用户。不联网。

class FakeNoUser extends CurrentUserNotifier {
  @override
  FutureOr<User?> build() => null;
}

/// 返回假偏好存储和覆盖项；拿 [SharedPreferences] 断言「操作后真的写进存储」
Future<(SharedPreferences, List<Override>)> fakeStore([
  Map<String, Object> values = const {},
]) async {
  SharedPreferences.setMockInitialValues(values);
  final prefs = await SharedPreferences.getInstance();
  return (
    prefs,
    <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      aiSharedPreferencesProvider.overrideWithValue(prefs),
      currentUserProvider.overrideWith(FakeNoUser.new),
      currentUsernameProvider.overrideWith((ref) async => null),
    ],
  );
}
