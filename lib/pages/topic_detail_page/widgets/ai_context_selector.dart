import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';

/// 上下文范围选择器
class AiContextSelector extends StatelessWidget {
  final ContextScope currentScope;
  final ValueChanged<ContextScope> onChanged;

  const AiContextSelector({
    super.key,
    required this.currentScope,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (pillContext) => FilterPill(
        label: currentScope.label,
        icon: AppIcons.article,
        onTap: () async {
          final picked = await showAppMenu<ContextScope>(
            context: pillContext,
            anchor: globalRectOf(pillContext),
            sections: [
              [
                for (final scope in ContextScope.values)
                  AppMenuItem<ContextScope>(
                    label: scope.label,
                    value: scope,
                    checked: scope == currentScope,
                  ),
              ],
            ],
          );
          if (picked != null) onChanged(picked);
        },
      ),
    );
  }
}
