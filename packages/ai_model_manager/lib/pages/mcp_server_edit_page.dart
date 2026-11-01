import 'dart:async';

import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/mcp_server_config.dart';
import '../providers/mcp_server_providers.dart';
import '../services/mcp_client_service.dart';
import '../services/mcp_secret_read_exception.dart';
import '../services/mcp_tool_bridge.dart';
import 'mcp_page_parts.dart';

/// 添加 / 编辑一个 MCP 服务：名称、地址、Token、请求头；「测试连接」拉取工具列表，
/// 每个工具一个开关（默认只开标了只读的）。
/// 页面文案目前只有中文（其他语言也显示中文）。
class McpServerEditPage extends ConsumerStatefulWidget {
  const McpServerEditPage({super.key, this.serverId});

  /// 为空是新增
  final String? serverId;

  @override
  ConsumerState<McpServerEditPage> createState() => _McpServerEditPageState();
}

class _McpServerEditPageState extends ConsumerState<McpServerEditPage> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _token = TextEditingController();
  final _headers = TextEditingController();
  bool _enabled = true;
  bool _obscure = true;
  bool _testing = false;
  bool _loaded = false;
  bool _saving = false;
  final _scroll = ScrollController();
  bool _scrolled = false;

  /// 读不到已保存的 Token / 请求头：用户没改这两个字段就不写入，更不删除
  bool _secretsFailed = false;
  bool _secretsTouched = false;

  /// 请求头默认遮住（和 Token 一样），点眼睛才显示
  bool _headersShown = false;
  String? _testError;
  String? _saveError;

  /// 测试连接拉到的工具；为空 = 还没测过
  List<McpToolInfo>? _tools;

  /// 用户在这一页改过的工具开关
  final Map<String, bool> _states = {};

  McpServerConfig? get _existing {
    final id = widget.serverId;
    if (id == null) return null;
    for (final s in ref.read(mcpServerListProvider)) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final e = _existing;
    if (e == null) {
      _loaded = true;
    } else {
      _name.text = e.name;
      _url.text = e.url;
      _enabled = e.enabled;
      _states.addAll(e.toolStates);
      unawaited(_loadSecrets(e.id));
    }
    _url.addListener(() => setState(() {}));
    _scroll.addListener(() {
      final scrolled = _scroll.hasClients && _scroll.offset > 1;
      if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
    });
  }

  Future<void> _loadSecrets(String id) async {
    McpSecrets? loaded;
    try {
      loaded = await ref.read(mcpServerListProvider.notifier).secretsOf(id);
    } on McpSecretReadException {
      loaded = null;
    }
    if (!mounted) return;
    setState(() {
      if (loaded == null) {
        _secretsFailed = true;
      } else {
        _token.text = loaded.bearerToken;
        _headers.text = [for (final e in loaded.headers.entries) '${e.key}: ${e.value}'].join('\n');
      }
      _loaded = true;
    });
    // 之后用户改了这两个字段才算「动过」
    _token.addListener(() => _secretsTouched = true);
    _headers.addListener(() => _secretsTouched = true);
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _token.dispose();
    _headers.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 每行 `名称: 值`
  McpSecrets _secrets() {
    final map = <String, String>{};
    for (final line in _headers.text.split('\n')) {
      final i = line.indexOf(':');
      if (i <= 0) continue;
      final k = line.substring(0, i).trim();
      final v = line.substring(i + 1).trim();
      if (k.isNotEmpty) map[k] = v;
    }
    return McpSecrets(bearerToken: _token.text.trim(), headers: map);
  }

  bool get _urlOk {
    final u = Uri.tryParse(_url.text.trim());
    return u != null && (u.scheme == 'https' || u.scheme == 'http') && u.host.isNotEmpty;
  }

  bool get _plainHttp => _url.text.trim().toLowerCase().startsWith('http://');

  Future<void> _test() async {
    if (!_urlOk) {
      setState(() => _testError = '请先填写完整的服务地址（http:// 或 https:// 开头）');
      return;
    }
    setState(() {
      _testing = true;
      _testError = null;
    });
    final service = ref.read(mcpClientServiceProvider);
    // 一次性的探测 id：测完就忘掉，不污染这个服务真实的会话
    final probe = McpServerConfig(id: '_probe_${DateTime.now().microsecondsSinceEpoch}', name: _name.text, url: _url.text.trim());
    try {
      final tools = await service.listTools(probe, _secrets());
      if (!mounted) return;
      setState(() => _tools = tools);
    } on McpException catch (e) {
      if (!mounted) return;
      setState(() {
        _tools = null;
        _testError = e.message;
      });
    } finally {
      service.forget(probe.id);
      if (mounted) setState(() => _testing = false);
    }
  }

  bool _isOn(McpToolInfo t) => _states[t.name] ?? t.defaultEnabled;

  Future<void> _save() async {
    if (_saving) return;
    if (!_urlOk) {
      setState(() => _saveError = '服务地址不是有效的 http(s) 地址');
      return;
    }
    // await 之前把要用的都取到局部变量
    final notifier = ref.read(mcpServerListProvider.notifier);
    final service = ref.read(mcpClientServiceProvider);
    final navigator = Navigator.of(context);
    final name = _name.text.trim().isEmpty ? (Uri.tryParse(_url.text.trim())?.host ?? 'MCP') : _name.text.trim();
    // 测过的话，把每个工具当前的开关都存下来（只有存了记录的工具才会启用）；没测过就保留原来的
    final states = _tools == null ? Map<String, bool>.from(_states) : {for (final t in _tools!) t.name: _isOn(t)};
    // 读不到已保存的凭据、而且用户没改这两个字段：不写入，也不删除
    final secrets = (_secretsFailed && !_secretsTouched) ? null : _secrets();
    final url = _url.text;
    final enabled = _enabled;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final id = widget.serverId;
      if (id == null) {
        final newId = await notifier.add(name: name, url: url, secrets: secrets ?? const McpSecrets(), enabled: enabled);
        if (states.isNotEmpty) await notifier.update(newId, toolStates: states);
      } else {
        await notifier.update(id, name: name, url: url, enabled: enabled, toolStates: states, secrets: secrets);
        service.forget(id);
      }
    } on McpSecretStoreException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = '$e，没有保存';
      });
      return;
    }
    if (!mounted) return;
    navigator.pop();
  }

  Future<void> _delete() async {
    final id = widget.serverId;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: const Text('删除这个 MCP 服务？'),
        content: const Text('保存的 Token 和请求头也会一起删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(mcpServerListProvider.notifier).remove(id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final theme = Theme.of(context).textTheme;
    final meta = theme.bodySmall!.merge(tokens.text.meta).copyWith(color: colors.textMeta);
    final label = theme.bodyLarge!.merge(tokens.text.body).copyWith(color: colors.textPrimary);

    Widget field(String title, TextEditingController c, {String? hint, bool obscure = false, int maxLines = 1, Widget? suffix, Key? key}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(bottom: AppSpace.xs), child: Text(title, style: meta)),
            TextField(
              key: key,
              controller: c,
              obscureText: obscure,
              minLines: 1,
              maxLines: obscure ? 1 : maxLines,
              autocorrect: false,
              enableSuggestions: false,
              style: label,
              decoration: InputDecoration(
                hintText: hint,
                isDense: true,
                filled: true,
                fillColor: colors.surfaceElevated,
                suffixIcon: suffix,
                contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.m, vertical: AppSpace.m),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(tokens.radius.field),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: colors.surfacePage,
      appBar: AppNavBar(
        title: widget.serverId == null ? '添加 MCP 服务' : '编辑 MCP 服务',
        slotWidth: 70,
        // 内容滚动之后加细分隔线
        showDivider: _scrolled,
        trailing: [TextButton(key: const ValueKey('mcp-save'), onPressed: (_loaded && !_saving) ? _save : null, child: const Text('保存'))],
      ),
      body: ReadableBody(
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(AppSpace.pageMargin, AppSpace.m, AppSpace.pageMargin, AppSpace.xxl),
          children: [
            field('名称', _name, hint: '例如：文档搜索'),
            field('服务地址（Streamable HTTP）', _url, hint: 'https://example.com/mcp', key: const ValueKey('mcp-url'), maxLines: 3),
            if (_plainHttp)
              const Padding(
                key: ValueKey('mcp-plain-warning'),
                padding: EdgeInsets.only(bottom: AppSpace.m),
                child: McpWarning('这个地址不是 https，Token 和请求内容会以明文传输。只在你信任的网络里使用。'),
              ),
            field(
              'Bearer Token（可选）',
              _token,
              obscure: _obscure,
              suffix: IconButton(
                tooltip: _obscure ? '显示' : '隐藏',
                icon: Icon(_obscure ? AppIcons.visibility : AppIcons.visibilityOff, size: AppSize.iconM),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            if (_secretsFailed)
              Padding(
                key: const ValueKey('mcp-secret-warning'),
                padding: const EdgeInsets.only(bottom: AppSpace.m),
                child: Text(
                  '读不到已保存的 Token 和请求头。不改这两项的话，保存时会保持原样，不会清掉。',
                  style: meta.copyWith(color: colors.textDestructive),
                ),
              ),
            _headersShown
                ? field(
                    '自定义请求头（可选，每行「名称: 值」）',
                    _headers,
                    maxLines: 4,
                    key: const ValueKey('mcp-headers'),
                    suffix: IconButton(
                      tooltip: '隐藏',
                      icon: const Icon(AppIcons.visibilityOff, size: AppSize.iconM),
                      onPressed: () => setState(() => _headersShown = false),
                    ),
                  )
                : Padding(
                    key: const ValueKey('mcp-headers-hidden'),
                    padding: const EdgeInsets.only(bottom: AppSpace.m),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpace.xs),
                          child: Text('自定义请求头（可选，每行「名称: 值」）', style: meta),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpace.m),
                          constraints: const BoxConstraints(minHeight: AppSize.hit),
                          decoration: BoxDecoration(
                            color: colors.surfaceElevated,
                            borderRadius: BorderRadius.circular(tokens.radius.field),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _headers.text.trim().isEmpty ? '未设置' : '已设置 ${_secrets().headers.length} 个请求头（内容已遮住）',
                                  style: label.copyWith(color: colors.textMeta),
                                ),
                              ),
                              IconButton(
                                key: const ValueKey('mcp-headers-show'),
                                tooltip: '显示',
                                icon: const Icon(AppIcons.visibility, size: AppSize.iconM),
                                onPressed: () => setState(() => _headersShown = true),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
            Text('Token 和请求头只保存在系统的安全存储里，不会进入数据备份。', style: meta),
            const SizedBox(height: AppSpace.l),
            Row(
              children: [
                Expanded(child: Text('启用这个服务', style: label)),
                Switch.adaptive(
                  value: _enabled,
                  activeTrackColor: colors.brandButton,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.m),
            FilledButton(
              key: const ValueKey('mcp-test'),
              style: FilledButton.styleFrom(
                backgroundColor: colors.brandButton,
                foregroundColor: colors.onBrandButton,
                // 大字号下按钮也要有足够的高度和上下内边距
                minimumSize: const Size.fromHeight(AppSize.hit),
                padding: const EdgeInsets.symmetric(vertical: AppSpace.m, horizontal: AppSpace.l),
              ),
              onPressed: _testing ? null : _test,
              child: Text(_testing ? '正在连接…' : '测试连接'),
            ),
            if (_testError != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.m),
                child: Text(_testError!, key: const ValueKey('mcp-test-error'), style: meta.copyWith(color: colors.textDestructive)),
              ),
            if (_tools != null) ...[
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.l, bottom: AppSpace.s),
                child: Text(
                  '连接正常：${_tools!.length} 个工具',
                  key: const ValueKey('mcp-test-ok'),
                  style: label.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text('默认只开启标了「只读」的工具；其余默认关闭。', style: meta),
              if (_tools!.where(_isOn).length > McpToolBridge.maxTools)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.xs),
                  child: Text(
                    '启用的工具超过 ${McpToolBridge.maxTools} 个，只会给 AI 用前 ${McpToolBridge.maxTools} 个。',
                    key: const ValueKey('mcp-too-many'),
                    style: meta.copyWith(color: colors.textDestructive),
                  ),
                ),
              const SizedBox(height: AppSpace.s),
              McpGroupCard(children: [for (final t in _tools!) _toolRow(context, t)]),
            ],
            if (_saveError != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.m),
                child: Text(_saveError!, style: meta.copyWith(color: colors.textDestructive)),
              ),
            if (widget.serverId != null) ...[
              const SizedBox(height: AppSpace.xl),
              TextButton(
                key: const ValueKey('mcp-delete'),
                onPressed: _delete,
                child: Text('删除这个服务', style: TextStyle(color: colors.textDestructive)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _toolRow(BuildContext context, McpToolInfo t) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final theme = Theme.of(context).textTheme;
    final meta = theme.bodySmall!.merge(tokens.text.meta).copyWith(color: colors.textMeta);
    final base = theme.bodyLarge!.merge(tokens.text.body).copyWith(color: colors.textPrimary);
    final on = _isOn(t);
    return Padding(
      key: ValueKey('mcp-tool-${t.name}'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.m, vertical: AppSpace.s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 名字和「只读」小徽标
                Wrap(
                  spacing: AppSpace.s,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(t.title ?? t.name, style: base),
                    if (t.readOnlyHint == true) const McpBadge('只读'),
                  ],
                ),
                Text(
                  t.description.isEmpty ? '（无说明）' : t.description,
                  style: meta,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                // 不是明确只读的工具（含没有标注的）一律提示风险，不管开关开没开
                if (t.mayModify)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.xs),
                    child: McpWarning('这个工具可能会修改数据', key: ValueKey('mcp-modify-${t.name}')),
                  ),
              ],
            ),
          ),
          Switch.adaptive(
            value: on,
            activeTrackColor: colors.brandButton,
            onChanged: (v) => setState(() => _states[t.name] = v),
          ),
        ],
      ),
    );
  }
}
