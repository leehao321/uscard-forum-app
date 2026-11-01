import 'package:m3e_ui/m3e_ui.dart';
import 'package:flutter/material.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/ai_l10n.dart';
import '../providers/ai_provider_providers.dart';

/// AI 高级设置（补充稿 42）：单行导航 + 一组两条开关（默认关闭）+ 页脚说明。
class AiAdvancedSettingsPage extends ConsumerWidget {
  const AiAdvancedSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useAppNetwork = ref.watch(aiUseAppNetworkProvider);
    final hasAdapterFactory = ref.watch(aiDioAdapterFactoryProvider) != null;
    final partialEnabled = ref.watch(aiPartialImagesProvider);
    final tokens = context.tokens;
    final l10n = AiL10n.current;

    return Scaffold(
      backgroundColor: tokens.colors.surfacePage,
      appBar: AppNavBar(title: l10n.advancedSettings),
      body: ReadableBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.pageMargin,
            AppSpace.s,
            AppSpace.pageMargin,
            AppSpace.x32,
          ),
          children: [
            SegmentedCardGroup(
              children: [
                SwitchListTile.adaptive(
                  title: Text(l10n.useAppNetwork),
                  subtitle: Text(l10n.useAppNetworkSubtitle),
                  value: useAppNetwork && hasAdapterFactory,
                  onChanged: hasAdapterFactory
                      ? (value) async {
                          final prefs = ref.read(aiSharedPreferencesProvider);
                          await prefs.setBool('ai_use_app_network', value);
                          ref.read(aiUseAppNetworkProvider.notifier).state =
                              value;
                        }
                      : null,
                ),
                SwitchListTile.adaptive(
                  title: Text(l10n.partialImagesTitle),
                  subtitle: Text(l10n.partialImagesSubtitle),
                  value: partialEnabled,
                  onChanged: (value) async {
                    final prefs = ref.read(aiSharedPreferencesProvider);
                    await prefs.setBool('ai_partial_images', value);
                    ref.read(aiPartialImagesProvider.notifier).state = value;
                  },
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.m,
                AppSpace.s,
                AppSpace.m,
                0,
              ),
              child: Text(
                l10n.partialImagesFootnote,
                style: Theme.of(context).textTheme.bodySmall!
                    .merge(tokens.text.meta)
                    .copyWith(color: tokens.colors.textMeta),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
