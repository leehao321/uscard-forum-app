import 'package:flutter/material.dart';

import '../services/app_lock_service.dart';
import 'common/compass_logo.dart';

/// 应用锁遮罩：上锁时盖住整个界面，并自动弹一次系统认证。
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> {
  final _service = AppLockService.instance;
  bool _wasLocked = false;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onChanged);
    _onChanged();
  }

  @override
  void dispose() {
    _service.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final locked = _service.locked;
    if (locked && !_wasLocked) {
      // 刚上锁：等这一帧画完再弹系统认证
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _service.locked) _service.unlock();
      });
    }
    _wasLocked = locked;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_service.locked) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Positioned.fill(
      child: Material(
        color: theme.colorScheme.surface,
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CompassLogo(size: 96, spinning: false),
                const SizedBox(height: 20),
                Text('USCard Forum 已锁定', style: theme.textTheme.titleMedium),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _service.authenticating ? null : _service.unlock,
                  icon: const Icon(Icons.lock_open),
                  label: const Text('解锁'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
