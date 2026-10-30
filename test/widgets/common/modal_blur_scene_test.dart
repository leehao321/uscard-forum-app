import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/utils/blur_config.dart' show ModalBlurScene;
import 'package:fluxdo/utils/dialog_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final scene in ModalBlurScene.values) {
    for (final brightness in Brightness.values) {
      for (final enabled in [false, true]) {
        testWidgets('$scene $brightness 旧偏好 blur=$enabled: 遮罩不模糊', (
          tester,
        ) async {
          SharedPreferences.setMockInitialValues({'pref_dialog_blur': enabled});
          final prefs = await SharedPreferences.getInstance();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
              child: MaterialApp(
                theme: ThemeData(brightness: brightness),
                home: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () {
                        if (scene == ModalBlurScene.sheet) {
                          showAppBottomSheet<void>(
                            context: context,
                            suspendDynamicContent: false,
                            builder: (_) => const SizedBox(
                              height: 140,
                              child: Text('panel content'),
                            ),
                          );
                        } else {
                          showAppDialog<void>(
                            context: context,
                            suspendDynamicContent: false,
                            builder: (_) => const AlertDialog(
                              content: Text('dialog content'),
                            ),
                          );
                        }
                      },
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          // 0.4.0（计划 P11）：v2 的遮罩是 32% 纯色、不模糊，「弹窗模糊」
          // 去掉了；旧版存的 pref_dialog_blur=true 也不再生效
          expect(find.byType(BackdropFilter), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
}
