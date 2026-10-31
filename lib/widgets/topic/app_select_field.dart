import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';

/// [AppSelectField] 的一个选项
class AppSelectOption<T> {
  const AppSelectOption({required this.label, required this.value});

  final String label;
  final T value;
}

/// 带标签的选择框：点开是 v2 菜单（[showAppMenu]），取代 Material 的
/// `DropdownButtonFormField`。当前项在菜单里打勾。
class AppSelectField<T> extends StatelessWidget {
  const AppSelectField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final List<AppSelectOption<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final selected = options.where((o) => o.value == value).firstOrNull;
    return Builder(
      builder: (fieldContext) => Semantics(
        button: true,
        label: label,
        value: selected?.label,
        excludeSemantics: true,
        onTap: () => _open(fieldContext),
        child: AppPressable(
          onTap: () => _open(fieldContext),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              suffixIcon: Icon(
                AppIcons.dropdown,
                size: AppSize.iconM,
                color: tokens.colors.textMeta,
              ),
            ),
            isEmpty: selected == null,
            child: Text(
              selected?.label ?? '',
              style: tokens.text.control.copyWith(
                color: tokens.colors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext fieldContext) async {
    final index = await showAppMenu<int>(
      context: fieldContext,
      anchor: globalRectOf(fieldContext),
      sections: [
        [
          for (var i = 0; i < options.length; i++)
            AppMenuItem<int>(
              label: options[i].label,
              value: i,
              checked: options[i].value == value,
            ),
        ],
      ],
    );
    if (index != null) onChanged(options[index].value);
  }
}
