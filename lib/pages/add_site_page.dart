import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';

import '../l10n/s.dart';
import '../models/site_profile.dart';
import '../services/site_probe_service.dart';

/// 加站页：预置站卡片 + 自由输入域名。首次启动时也用它选站。
class AddSitePage extends StatefulWidget {
  /// 用户确认了要添加的站点。完成后本页保持加载状态，由调用方决定去向；
  /// 抛异常时恢复可操作。
  final Future<void> Function(SiteProfile site) onConfirmed;

  final SiteProbeService? probeService;

  const AddSitePage({super.key, required this.onConfirmed, this.probeService});

  @override
  State<AddSitePage> createState() => _AddSitePageState();
}

class _AddSitePageState extends State<AddSitePage> {
  final _addressController = TextEditingController();
  late final SiteProbeService _probeService =
      widget.probeService ?? SiteProbeService();

  /// 选中的预置站；为 null 表示使用自由输入的地址。
  SiteProfile? _selectedPreset = SitePresets.all.first;
  bool _busy = false;
  String? _error;

  /// 被 Cloudflare 挡住时可以跳过校验直接添加的地址。
  String? _unverifiedBaseUrl;

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  void _selectPreset(SiteProfile preset) {
    FocusScope.of(context).unfocus();
    setState(() {
      _selectedPreset = preset;
      _addressController.clear();
      _error = null;
      _unverifiedBaseUrl = null;
    });
  }

  void _onAddressChanged(String value) {
    setState(() {
      _selectedPreset = value.trim().isEmpty ? SitePresets.all.first : null;
      _error = null;
      _unverifiedBaseUrl = null;
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    final preset = _selectedPreset;
    if (preset != null) {
      await _confirm(preset);
      return;
    }

    final baseUrl = normalizeSiteBaseUrl(_addressController.text);
    if (baseUrl == null) {
      setState(() => _error = context.l10n.site_errorInvalidAddress);
      return;
    }

    final matchedPreset = SitePresets.match(baseUrl);
    if (matchedPreset != null) {
      await _confirm(matchedPreset);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _unverifiedBaseUrl = null;
    });
    final result = await _probeService.probe(baseUrl);
    if (!mounted) return;
    setState(() => _busy = false);

    switch (result) {
      case SiteProbeSuccess():
        final accepted = await _showConfirmDialog(result);
        if (accepted == true && mounted) {
          await _confirm(result.toProfile());
        }
      case SiteProbeFailure(:final reason):
        setState(() {
          _error = _failureMessage(reason);
          if (reason == SiteProbeFailureReason.cloudflareChallenge) {
            _unverifiedBaseUrl = baseUrl;
          }
        });
    }
  }

  Future<void> _addUnverified() async {
    final baseUrl = _unverifiedBaseUrl;
    if (baseUrl == null || _busy) return;
    await _confirm(
      SiteProfile(baseUrl: baseUrl, title: Uri.parse(baseUrl).host),
    );
  }

  Future<void> _confirm(SiteProfile site) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onConfirmed(site);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  String _failureMessage(SiteProbeFailureReason reason) {
    final l10n = context.l10n;
    return switch (reason) {
      SiteProbeFailureReason.notDiscourse => l10n.site_errorNotDiscourse,
      SiteProbeFailureReason.unreachable => l10n.site_errorUnreachable,
      SiteProbeFailureReason.badCertificate => l10n.site_errorBadCertificate,
      SiteProbeFailureReason.cloudflareChallenge => l10n.site_errorCloudflare,
    };
  }

  Future<bool?> _showConfirmDialog(SiteProbeSuccess info) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        final l10n = context.l10n;
        final version = info.version;
        final description = info.description;
        return AlertDialog(
          title: Text(l10n.site_confirmTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(info.title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                info.baseUrl,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (description != null) ...[
                const SizedBox(height: 12),
                Text(
                  description,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              if (version != null) ...[
                const SizedBox(height: 12),
                Text(
                  l10n.site_confirmVersion(version),
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (info.loginRequired) ...[
                const SizedBox(height: 12),
                Text(
                  l10n.site_confirmLoginRequired,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.tertiary,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.common_cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.site_confirmAdd),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final error = _error;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                Text(l10n.site_chooseTitle, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  l10n.site_chooseSubtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                for (final preset in SitePresets.all)
                  _PresetCard(
                    preset: preset,
                    selected: identical(preset, _selectedPreset),
                    onTap: _busy ? null : () => _selectPreset(preset),
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: _addressController,
                  enabled: !_busy,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  textInputAction: TextInputAction.go,
                  onChanged: _onAddressChanged,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: l10n.site_customAddressLabel,
                    hintText: l10n.site_customAddressHint,
                    errorText: error,
                    errorMaxLines: 4,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.site_continue),
                ),
                if (_unverifiedBaseUrl != null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _busy ? null : _addUnverified,
                    child: Text(l10n.site_addAnyway),
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

class _PresetCard extends StatelessWidget {
  final SiteProfile preset;
  final bool selected;
  final VoidCallback? onTap;

  const _PresetCard({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: selected ? colorScheme.secondaryContainer : null,
      child: ListTile(
        title: Text(preset.title),
        subtitle: Text(preset.host),
        trailing: Icon(
          selected
              ? Symbols.check_circle_rounded
              : Symbols.radio_button_unchecked_rounded,
          color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
        ),
        selected: selected,
        onTap: onTap,
      ),
    );
  }
}
