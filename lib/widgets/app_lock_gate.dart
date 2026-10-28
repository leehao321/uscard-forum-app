import 'package:flutter/material.dart';

import '../services/app_lock_service.dart';
import 'common/compass_logo.dart';

/// 应用锁遮罩：上锁时盖住整个界面，并自动弹一次系统认证；离开前台时只盖
/// 隐私遮罩（不弹认证），多任务缩略图里看不到内容。
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> {
  final _service = AppLockService.instance;
  bool _wasLocked = false;
  bool _wasCovering = false;

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
    final covering = _service.covering;
    if (covering && !_wasCovering) {
      // 盖上的那一刻收起键盘：否则键盘浮在锁屏上，打的字会进到被盖住的输入框
      FocusManager.instance.primaryFocus?.unfocus();
    }
    if (locked && !_wasLocked) {
      // 刚上锁：等这一帧画完再弹系统认证
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _service.locked) _service.unlock();
      });
    }
    _wasLocked = locked;
    _wasCovering = covering;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_service.covering) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final locked = _service.locked;
    return Positioned.fill(
      // BlockSemantics：底下页面的语义树整个屏蔽，VoiceOver 读不到、也点不到被盖住的内容
      child: BlockSemantics(
        child: Material(
          color: theme.colorScheme.surface,
          child: SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CompassLogo(size: 96, spinning: false),
                  if (locked) ...[
                    const SizedBox(height: 20),
                    Text('USCard Forum 已锁定', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _service.authenticating ? null : _service.unlock,
                      icon: const Icon(Icons.lock_open),
                      label: const Text('解锁'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
