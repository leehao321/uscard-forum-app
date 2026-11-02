import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/mcp_server_config.dart';
import '../providers/mcp_server_providers.dart';
import 'mcp_page_parts.dart';
import 'mcp_server_edit_page.dart';

/// MCP 服务列表：添加、编辑、开关。
/// 页面文案目前只有中文（其他语言也显示中文）。
class McpServersPage extends ConsumerWidget {
  const McpServersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(mcpServerListProvider);
    final theme = Theme.of(context);
    final meta = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    void open([McpServerConfig? s]) => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => McpServerEditPage(serverId: s?.id)),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('MCP 服务'),
        actions: [
          IconButton(
            key: const ValueKey('mcp-add'),
            tooltip: '添加',
            icon: const Icon(Symbols.add_rounded),
            onPressed: () => open(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (servers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('还没有 MCP 服务。点右上角添加一个。', style: meta)),
            )
          else
            McpGroupCard(
              children: [
                for (final s in servers)
                  _ServerRow(server: s, onTap: () => open(s)),
              ],
            ),
          const SizedBox(height: 12),
          Text(
            '连接外部的 MCP 服务（Streamable HTTP），让 AI 功能可以调用它的工具。'
            '默认只启用标了「只读」的工具；工具返回的内容会发给你配置的 AI 模型。',
            style: meta,
          ),
        ],
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
    final host = Uri.tryParse(server.url)?.host ?? server.url;
    return ListTile(
      leading: const Icon(Symbols.dns_rounded),
      title: Text(
        server.name.isEmpty ? host : server.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(host, maxLines: 2, overflow: TextOverflow.ellipsis),
          // 明文 http 单独做成警示标签，不会被地址挤掉
          if (server.isPlainHttp)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: McpWarning('明文 http', compact: true),
            ),
        ],
      ),
      trailing: Switch(
        value: server.enabled,
        onChanged: (v) => ref
            .read(mcpServerListProvider.notifier)
            .update(server.id, enabled: v),
      ),
      onTap: onTap,
    );
  }
}
