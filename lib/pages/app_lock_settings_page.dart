import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:m3e_ui/m3e_ui.dart' show SegmentedCardGroup;

import '../services/app_lock_service.dart';
import '../services/toast_service.dart';

/// 应用锁设置
class AppLockSettingsPage extends StatefulWidget {
  const AppLockSettingsPage({super.key});

  @override
  State<AppLockSettingsPage> createState() => _AppLockSettingsPageState();
}

class _AppLockSettingsPageState extends State<AppLockSettingsPage> {
  final _service = AppLockService.instance;
  bool? _available;

  @override
  void initState() {
    super.initState();
    _service.addListener(_refresh);
    _service.isAvailable().then((v) {
      if (mounted) setState(() => _available = v);
    });
  }

  @override
  void dispose() {
    _service.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _toggle(bool value) async {
    final ok = await _service.setEnabled(value);
    if (!ok) ToastService.showError('没有通过验证，设置未改变');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final meta = base.merge(tokens.text.meta).copyWith(color: colors.textMeta);
    final available = _available;

    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.m,
        AppSpace.s,
        AppSpace.m,
        AppSpace.s,
      ),
      child: Semantics(header: true, child: Text(text, style: meta)),
    );

    Widget footer(String text, {Color? color}) => Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.m, AppSpace.s, AppSpace.m, 0),
      child: Text(text, style: meta.copyWith(color: color)),
    );

    return Scaffold(
      backgroundColor: colors.surfacePage,
      appBar: ReadableAppBar(child: const AppNavBar(title: '应用锁')),
      body: ReadableBody(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kReadableMaxWidth),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                AppSpace.pageMargin,
                AppSpace.s,
                AppSpace.pageMargin,
                MediaQuery.paddingOf(context).bottom + AppSpace.x32,
              ),
              children: [
                SegmentedCardGroup(
                  children: [
                    SwitchListTile.adaptive(
                      secondary: Icon(
                        AppIcons.lock,
                        color: colors.brandPrimary,
                      ),
                      title: const Text('启用应用锁'),
                      value: _service.enabled,
                      onChanged: available == true && !_service.authenticating
                          ? _toggle
                          : null,
                    ),
                  ],
                ),
                footer(
                  available == false
                      ? '这台设备没有设置生物识别或设备密码，无法使用应用锁。'
                      : '打开 App 时需要 Face ID / Touch ID 或设备密码',
                  color: available == false ? colors.textDestructive : null,
                ),
                if (_service.enabled) ...[
                  const SizedBox(height: AppSpace.xl),
                  header('离开 App 多久后上锁'),
                  SegmentedCardGroup(
                    children: [
                      for (final e in AppLockService.timeoutChoices.entries)
                        Semantics(
                          inMutuallyExclusiveGroup: true,
                          checked: _service.timeoutSeconds == e.key,
                          child: ListTile(
                            title: Text(e.value),
                            trailing: _service.timeoutSeconds == e.key
                                ? Icon(
                                    AppIcons.check,
                                    size: AppSize.iconM,
                                    color: colors.brandPrimary,
                                  )
                                : null,
                            onTap: () => _service.setTimeout(e.key),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
