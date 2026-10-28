import 'package:flutter/material.dart';

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
    final theme = Theme.of(context);
    final available = _available;
    return Scaffold(
      appBar: AppBar(title: const Text('应用锁')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('启用应用锁'),
            subtitle: const Text('打开 App 时需要 Face ID / Touch ID 或设备密码'),
            value: _service.enabled,
            onChanged: available == true && !_service.authenticating
                ? _toggle
                : null,
          ),
          if (available == false)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '这台设备没有设置生物识别或设备密码，无法使用应用锁。',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          if (_service.enabled) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('离开 App 多久后上锁', style: theme.textTheme.titleSmall),
            ),
            RadioGroup<int>(
              groupValue: _service.timeoutSeconds,
              onChanged: (v) {
                if (v != null) _service.setTimeout(v);
              },
              child: Column(
                children: [
                  for (final e in AppLockService.timeoutChoices.entries)
                    RadioListTile<int>(value: e.key, title: Text(e.value)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
