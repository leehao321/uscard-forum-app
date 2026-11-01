import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/mcp_server_config.dart';
import '../providers/mcp_server_providers.dart';
import 'mcp_page_parts.dart';
import 'mcp_server_edit_page.dart';

/// MCP 服务列表：添加、编辑、开关。
/// 页面文案目前只有中文（其他语言也显示中文）。
class McpServersPage extends ConsumerStatefulWidget {
  const McpServersPage({super.key});

  @override
  ConsumerState<McpServersPage> createState() => _McpServersPageState();
}

class _McpServersPageState extends ConsumerState<McpServersPage> {
  final _scroll = ScrollController();
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final scrolled = _scroll.hasClients && _scroll.offset > 1;
      if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final servers = ref.watch(mcpServerListProvider);
    final tokens = context.tokens;
    final colors = tokens.colors;
    final meta = Theme.of(context).textTheme.bodySmall!.merge(tokens.text.meta).copyWith(color: colors.textMeta);

    void open([McpServerConfig? s]) => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => McpServerEditPage(serverId: s?.id)),
    );

    return Scaffold(
      backgroundColor: colors.surfacePage,
      appBar: AppNavBar(
        title: 'MCP 服务',
        slotWidth: 70,
        // 内容滚动之后加细分隔线
        showDivider: _scrolled,
        trailing: [
          IconButton(
            key: const ValueKey('mcp-add'),
            tooltip: '添加',
            icon: const Icon(AppIcons.add),
            onPressed: () => open(),
          ),
        ],
      ),
      body: ReadableBody(
        child: ListView(
          controller: _scroll,
          padding: EdgeInsets.zero,
          children: [
            ReadableColumn(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.pageMargin, AppSpace.s, AppSpace.pageMargin, 0),
                child: servers.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpace.xxl),
                        child: Center(child: Text('还没有 MCP 服务。点右上角添加一个。', style: meta)),
                      )
                    : McpGroupCard(
                        children: [for (final s in servers) _ServerRow(server: s, onTap: () => open(s))],
                      ),
              ),
            ),
            ReadableColumn(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.pageMargin + AppSpace.m,
                  AppSpace.s,
                  AppSpace.pageMargin + AppSpace.m,
                  AppSpace.xl,
                ),
                child: Text(
                  '连接外部的 MCP 服务（Streamable HTTP），让 AI 功能可以调用它的工具。'
                  '默认只启用标了「只读」的工具；工具返回的内容会发给你配置的 AI 服务商。',
                  style: meta,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerRow extends ConsumerWidget {
  const _ServerRow({required this.server, required this.onTap});

  final McpServerConfig server;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final base = Theme.of(context).textTheme.bodyLarge!.merge(tokens.text.body).copyWith(color: colors.textPrimary);
    final meta = Theme.of(context).textTheme.bodySmall!.merge(tokens.text.meta).copyWith(color: colors.textMeta);
    final host = Uri.tryParse(server.url)?.host ?? server.url;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.m, vertical: AppSpace.s),
          child: Row(
            children: [
              Icon(AppIcons.server, size: AppSize.iconM, color: colors.textMeta),
              const SizedBox(width: AppSpace.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(server.name.isEmpty ? host : server.name, style: base, maxLines: 2, overflow: TextOverflow.ellipsis),
                    // 地址用普通次要色，允许两行
                    Text(host, style: meta, maxLines: 2, overflow: TextOverflow.ellipsis),
                    // 明文 http 单独做成警示标签，不会被地址挤掉
                    if (server.isPlainHttp)
                      const Padding(
                        padding: EdgeInsets.only(top: AppSpace.xs),
                        child: McpWarning('明文 http', compact: true),
                      ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: server.enabled,
                activeTrackColor: colors.brandButton,
                onChanged: (v) => ref.read(mcpServerListProvider.notifier).update(server.id, enabled: v),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
