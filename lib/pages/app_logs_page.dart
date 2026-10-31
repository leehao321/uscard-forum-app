import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter/services.dart';
import 'package:cross_file/cross_file.dart';
import 'package:path/path.dart' as p;

import '../services/app_error_handler.dart';
import '../utils/share_utils.dart';
import '../services/discourse/discourse_service.dart';
import '../services/log/logger_utils.dart';
import '../services/network/adapters/platform_adapter.dart';
import '../services/toast_service.dart';

import 'package:common_ui/common_ui.dart';
import 'package:m3e_ui/m3e_ui.dart';

import '../widgets/post/reply_sheet.dart';
import '../l10n/s.dart';
import '../utils/dialog_utils.dart';

/// 日志类型筛选（公开供调试工具等入口预设初始筛选）
enum LogTypeFilter {
  all,
  general,
  request,
  lifecycle,
  cookie,
  network,
  cfChallenge,
  auth;

  /// 条目 type 字段是否匹配该筛选
  bool matches(String type) {
    return switch (this) {
      LogTypeFilter.all => true,
      LogTypeFilter.general => type == 'general',
      LogTypeFilter.request => type == 'request',
      LogTypeFilter.lifecycle => type == 'lifecycle',
      LogTypeFilter.cookie => type == 'cookie_trace' || type == 'cookie_engine',
      LogTypeFilter.network => type == 'network',
      LogTypeFilter.cfChallenge => type == 'cf_challenge',
      LogTypeFilter.auth => type == 'auth',
    };
  }
}

/// 日志级别筛选
enum _LogLevelFilter {
  all,
  error,
  warning,
  info,
  debug;

  bool matches(String level) {
    if (this == _LogLevelFilter.all) return true;
    return level == name;
  }
}

/// 详情对话框中已专门渲染过的字段，剩余字段进「附加字段」区域
const Set<String> _knownEntryKeys = {
  'timestamp',
  'level',
  'type',
  'message',
  'tag',
  'error',
  'errorType',
  'stackTrace',
  'appVersion',
  'customParameters',
  'method',
  'url',
  'statusCode',
  'duration',
  'networkAdapter',
  'event',
  'username',
  'reason',
};

/// 应用日志查看页面
class AppLogsPage extends StatefulWidget {
  const AppLogsPage({super.key, this.initialType = LogTypeFilter.all});

  /// 初始类型筛选（调试工具入口跳转时预设）
  final LogTypeFilter initialType;

  @override
  State<AppLogsPage> createState() => _AppLogsPageState();
}

class _AppLogsPageState extends State<AppLogsPage> {
  List<Map<String, dynamic>> _entries = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;

  late LogTypeFilter _typeFilter = widget.initialType;
  _LogLevelFilter _levelFilter = _LogLevelFilter.all;

  bool _searching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    setState(() => _loading = true);
    final entries = await LoggerUtils.readLogEntries();
    if (mounted) {
      setState(() {
        _entries = entries;
        _loading = false;
        _applyFilters();
      });
    }
  }

  /// 重算筛选结果（在 setState 内调用）
  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();
    _filtered = _entries.where((e) {
      final level = e['level']?.toString() ?? 'error';
      final type = e['type']?.toString() ?? 'general';
      if (!_levelFilter.matches(level)) return false;
      if (!_typeFilter.matches(type)) return false;
      if (query.isNotEmpty && !_matchesQuery(e, query)) return false;
      return true;
    }).toList();
  }

  static bool _matchesQuery(Map<String, dynamic> entry, String query) {
    for (final key in const [
      'message',
      'tag',
      'url',
      'error',
      'errorType',
      'event',
      'name',
    ]) {
      final value = entry[key];
      if (value != null && value.toString().toLowerCase().contains(query)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _copyDeviceInfo() async {
    final text = await LoggerUtils.getDeviceInfoText();
    await Clipboard.setData(ClipboardData(text: text));
    ToastService.showSuccess(S.current.common_copiedToClipboard);
  }

  Future<void> _copyAll() async {
    final content = await LoggerUtils.readLogContent();
    if (content.trim().isEmpty) {
      ToastService.showInfo(S.current.appLogs_noLogs);
      return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: content));
      ToastService.showSuccess(S.current.common_copiedToClipboard);
    } on PlatformException {
      // 日志超过 Binder 事务上限(~1MB)无法复制,回退到保存文件
      // (保存五端都可用,分享在 Linux 上不支持文件)
      await _saveLog();
    }
  }

  Future<void> _shareLog() async {
    final path = await LoggerUtils.getShareFilePath();
    await ShareUtils.shareFile(
      XFile(path),
      subject: S.current.appLogs_shareSubject,
    );
  }

  Future<void> _saveLog() async {
    final String path;
    try {
      path = await LoggerUtils.getShareFilePath();
    } catch (_) {
      // 生成阶段的异常由 LoggerUtils 记录，保存面板尚未打开。
      ToastService.showError(S.current.share_saveFailed);
      return;
    }
    final outcome = await ShareUtils.saveFile(XFile(path));
    if (outcome.shared) {
      final name = outcome.displayName ?? p.basename(path);
      ToastService.showSuccess(S.current.export_savedAs(name));
    }
  }

  Future<void> _clearLogs() async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AppAlertDialog(
        title: Text(context.l10n.appLogs_clearTitle),
        content: Text(context.l10n.appLogs_clearContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.common_delete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await LoggerUtils.clearLogs();
      await _loadLogs();
      ToastService.showSuccess(S.current.appLogs_logsCleared);
    }
  }

  /// 打开私信界面，预填设备信息、日志摘要和完整日志附件
  Future<void> _sendFeedback() async {
    try {
      // 并行：获取设备信息、读取日志内容、上传完整日志文件
      final deviceInfoFuture = LoggerUtils.getDeviceInfoText();
      final logContentFuture = LoggerUtils.readLogContent();
      final uploadFuture = _uploadLogFile();
      final deviceInfo = await deviceInfoFuture;
      final logContent = await logContentFuture;
      final attachmentMarkdown = await uploadFuture;

      if (!mounted) return;

      final buf = StringBuffer()
        ..writeln('## 设备信息')
        ..writeln('```')
        ..writeln(deviceInfo)
        ..writeln('```')
        ..writeln();

      // 完整日志附件
      if (attachmentMarkdown != null) {
        buf
          ..writeln('## 完整日志')
          ..writeln(attachmentMarkdown)
          ..writeln();
      }

      // 行内日志摘要（截断避免超长）
      buf.writeln('## 日志摘要');
      buf.writeln('```');
      const maxLogLength = 30000;
      if (logContent.length > maxLogLength) {
        buf.writeln('... (已截断，仅保留最近日志)');
        buf.writeln(logContent.substring(logContent.length - maxLogLength));
      } else {
        buf.writeln(logContent.isEmpty ? '(无日志)' : logContent);
      }
      buf.writeln('```');

      showReplySheet(
        context: context,
        targetUsername: 'pyteng',
        initialTitle: S.current.appLogs_feedbackTitle,
        initialContent: buf.toString(),
      );
    } on DioException catch (_) {
      // 网络错误已由 ErrorInterceptor 处理
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
    }
  }

  /// 上传完整日志文件（.txt），返回附件 markdown；失败返回 null
  Future<String?> _uploadLogFile() async {
    try {
      final jsonlPath = await LoggerUtils.getShareFilePath();
      // 复制为 .txt，避免 .jsonl 不在服务器 authorized_extensions 中
      final txtPath = jsonlPath.replaceAll('.jsonl', '.txt');
      await File(jsonlPath).copy(txtPath);
      final result = await DiscourseService().uploadFile(txtPath);
      return result.toAutoMarkdown();
    } catch (e) {
      debugPrint('[AppLogsPage] 上传日志文件失败: $e');
      return null;
    }
  }

  /// 级别色条：只强调 error/warning，普通行透明占位——错误才跳得出来
  Color _levelBarColor(BuildContext context, Map<String, dynamic> entry) {
    final scheme = Theme.of(context).colorScheme;
    final level = entry['level']?.toString() ?? 'error';
    final statusCode = entry['statusCode'];
    if (level == 'error' || (statusCode is int && statusCode >= 400)) {
      return scheme.error;
    }
    if (level == 'warning') return context.tokens.colors.textDestructive;
    return Colors.transparent;
  }

  /// 获取卡片标题
  String _getTitle(Map<String, dynamic> entry) {
    final type = entry['type']?.toString() ?? 'general';
    if (type == 'request') {
      final method = entry['method']?.toString() ?? '';
      final url = entry['url']?.toString() ?? '';
      // 只显示路径部分
      final uri = Uri.tryParse(url);
      final path = uri?.path ?? url;
      return '$method $path';
    }

    if (type == 'lifecycle') {
      return entry['message']?.toString() ?? S.current.appLogs_lifecycleEvent;
    }

    final tag = entry['tag']?.toString();
    final errorType = entry['errorType']?.toString();
    final message = entry['message']?.toString() ?? S.current.error_unknown;

    if (tag != null && errorType != null) {
      return '[$tag] $errorType';
    }
    if (errorType != null && entry['level'] == 'error') {
      return errorType;
    }
    if (tag != null) {
      return '[$tag] $message';
    }
    return message;
  }

  /// 获取卡片副标题
  String _getSubtitle(Map<String, dynamic> entry) {
    final type = entry['type']?.toString() ?? 'general';
    if (type == 'request') {
      final statusCode = entry['statusCode'];
      final duration = entry['duration'];
      final adapter = _getRequestAdapterLabel(entry);
      final parts = <String>[];
      if (statusCode != null) parts.add('$statusCode');
      if (duration != null) parts.add('${duration}ms');
      if (adapter != null) parts.add(adapter);
      return parts.join('\n');
    }

    if (type == 'lifecycle') {
      final parts = <String>[];
      final username = entry['username']?.toString();
      final reason = entry['reason']?.toString();
      if (username != null) parts.add('${S.current.appLogs_user}: $username');
      if (reason != null) parts.add(reason);
      return parts.join(' · ');
    }

    final level = entry['level']?.toString() ?? 'error';
    if (level == 'error') {
      return entry['error']?.toString() ?? S.current.error_unknown;
    }
    return entry['message']?.toString() ?? '';
  }

  void _showDetail(Map<String, dynamic> entry) {
    final type = entry['type']?.toString() ?? 'general';
    if (type == 'request') {
      _showRequestDetail(entry);
    } else if (type == 'lifecycle') {
      _showLifecycleDetail(entry);
    } else {
      _showGeneralDetail(entry);
    }
  }

  /// 提取详情对话框中未专门渲染的附加字段
  static Map<String, String> _extraFields(Map<String, dynamic> entry) {
    final extras = <String, String>{};
    for (final e in entry.entries) {
      if (_knownEntryKeys.contains(e.key)) continue;
      final value = e.value;
      if (value == null) continue;
      extras[e.key] = value.toString();
    }
    return extras;
  }

  void _showLifecycleDetail(Map<String, dynamic> entry) {
    final timestamp = entry['timestamp']?.toString() ?? '';
    final event = entry['event']?.toString() ?? '';
    final message = entry['message']?.toString() ?? '';
    final username = entry['username']?.toString();
    final reason = entry['reason']?.toString();
    final appVersion = entry['appVersion']?.toString();

    final eventLabel = switch (event) {
      'app_start' => S.current.appLogs_appStart,
      'login' => S.current.appLogs_userLogin,
      'logout_active' => S.current.appLogs_logoutActive,
      'logout_passive' => S.current.appLogs_logoutPassive,
      _ => event,
    };

    final detail = StringBuffer()
      ..writeln('${S.current.appLogs_time}: $timestamp')
      ..writeln('${S.current.appLogs_event}: $eventLabel');
    if (appVersion != null) {
      detail.writeln('${S.current.appLogs_version}: $appVersion');
    }
    detail.writeln('${S.current.appLogs_message}: $message');
    if (username != null) {
      detail.writeln('${S.current.appLogs_user}: $username');
    }
    if (reason != null) {
      detail.writeln('${S.current.appLogs_reason}: $reason');
    }

    _showDetailSheet(
      title: eventLabel,
      copyText: detail.toString(),
      rows: [
        (context.l10n.appLogs_time, timestamp, false),
        if (appVersion != null)
          (context.l10n.appLogs_version, appVersion, false),
        (context.l10n.appLogs_event, eventLabel, false),
        (context.l10n.appLogs_message, message, false),
        if (username != null) (context.l10n.appLogs_user, username, false),
        if (reason != null) (context.l10n.appLogs_reason, reason, false),
      ],
    );
  }

  void _showGeneralDetail(Map<String, dynamic> entry) {
    final level = entry['level']?.toString() ?? 'error';
    final message = entry['message']?.toString() ?? '';
    final error = entry['error']?.toString();
    final errorType = entry['errorType']?.toString();
    final rawTrace = entry['stackTrace']?.toString();
    final stackTrace = rawTrace != null && rawTrace.trim().isNotEmpty
        ? rawTrace
        : null;
    final timestamp = entry['timestamp']?.toString() ?? '';
    final tag = entry['tag']?.toString();
    final appVersion = entry['appVersion']?.toString();
    final extras = _extraFields(entry);

    final detail = StringBuffer()
      ..writeln('${S.current.appLogs_time}: $timestamp')
      ..writeln('${S.current.appLogs_level}: $level');
    if (appVersion != null) {
      detail.writeln('${S.current.appLogs_version}: $appVersion');
    }
    if (tag != null) detail.writeln('${S.current.appLogs_tag}: $tag');
    detail.writeln('${S.current.appLogs_message}: $message');
    if (error != null && error != message) {
      detail.writeln('${S.current.appLogs_error}: $error');
    }
    if (errorType != null) {
      detail.writeln('${S.current.appLogs_type}: $errorType');
    }
    for (final e in extras.entries) {
      detail.writeln('${e.key}: ${e.value}');
    }
    if (stackTrace != null) {
      detail
        ..writeln()
        ..writeln('${S.current.appLogs_stack}:')
        ..writeln(stackTrace);
    }

    _showDetailSheet(
      title: tag != null ? '[$tag]' : level.toUpperCase(),
      copyText: detail.toString(),
      rows: [
        (context.l10n.appLogs_time, timestamp, false),
        if (appVersion != null)
          (context.l10n.appLogs_version, appVersion, false),
        (context.l10n.appLogs_message, message, false),
        if (error != null && error != message)
          (context.l10n.appLogs_error, error, false),
        if (errorType != null)
          (context.l10n.appLogs_errorType, errorType, false),
      ],
      extras: extras,
      stackTrace: stackTrace,
    );
  }

  /// 生命周期 / 通用日志的详情半屏（和请求详情同一个版式）：
  /// 标题 + 复制 + x；键 13 meta 56 宽、值 13；附加字段和堆栈放代码块。
  void _showDetailSheet({
    required String title,
    required String copyText,
    required List<(String, String, bool)> rows,
    Map<String, String> extras = const {},
    String? stackTrace,
  }) {
    showAppBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final tokens = sheetContext.tokens;
        final base = Theme.of(sheetContext).textTheme.bodySmall!;
        final meta = base
            .merge(tokens.text.meta)
            .copyWith(color: tokens.colors.textMeta);
        final value = base
            .merge(tokens.text.meta)
            .copyWith(color: tokens.colors.textPrimary);
        const mono = TextStyle(fontFamily: 'monospace');
        Widget codeBlock(String label, String text) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpace.m),
            Text(label, style: meta),
            const SizedBox(height: AppSpace.xs),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpace.m),
              decoration: BoxDecoration(
                color: tokens.colors.surfaceElevated,
                borderRadius: BorderRadius.circular(tokens.radius.table),
              ),
              child: SelectableText(
                text,
                style: value
                    .merge(mono)
                    .copyWith(fontSize: AppFontSize.caption),
              ),
            ),
          ],
        );
        return AppSheetScaffold(
          title: title,
          maxHeightFactor: 0.85,
          actions: [
            AppIconButton(
              icon: AppIcons.copy,
              semanticLabel: sheetContext.l10n.appLogs_copyAll,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: copyText));
                ToastService.showSuccess(S.current.common_copiedToClipboard);
              },
            ),
          ],
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (key, text, monospace) in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.s),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 56, child: Text(key, style: meta)),
                        Expanded(
                          child: SelectableText(
                            text,
                            style: monospace ? value.merge(mono) : value,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (extras.isNotEmpty)
                  codeBlock(
                    sheetContext.l10n.appLogs_otherFields,
                    [for (final e in extras.entries) '${e.key}: ${e.value}']
                        .join('\n'),
                  ),
                if (stackTrace != null)
                  codeBlock(sheetContext.l10n.appLogs_stackTrace, stackTrace),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 请求详情半屏：标题「GET 请求」+ 复制 + x；键值分组（键 13 meta 56 宽，
  /// URL 等宽可换行）；其余字段放「附加字段」代码块。
  void _showRequestDetail(Map<String, dynamic> entry) {
    final timestamp = entry['timestamp']?.toString() ?? '';
    final method = entry['method']?.toString() ?? '';
    final url = entry['url']?.toString() ?? '';
    final statusCode = entry['statusCode']?.toString() ?? '';
    final duration = entry['duration'];
    final level = entry['level']?.toString() ?? 'info';
    final adapter = _getRequestAdapterLabel(entry);
    final extras = _extraFields(entry);

    String copyText() {
      final detail = StringBuffer()
        ..writeln('${S.current.appLogs_time}: $timestamp')
        ..writeln('${S.current.appLogs_method}: $method')
        ..writeln('URL: $url')
        ..writeln('${S.current.appLogs_statusCode}: $statusCode');
      if (duration != null) {
        detail.writeln('${S.current.appLogs_duration}: ${duration}ms');
      }
      if (adapter != null) {
        detail.writeln('${S.current.networkAdapter_adapterType}: $adapter');
      }
      detail.writeln('${S.current.appLogs_level}: $level');
      for (final e in extras.entries) {
        detail.writeln('${e.key}: ${e.value}');
      }
      return detail.toString();
    }

    showAppBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final tokens = sheetContext.tokens;
        final base = Theme.of(sheetContext).textTheme.bodySmall!;
        final meta = base
            .merge(tokens.text.meta)
            .copyWith(color: tokens.colors.textMeta);
        final value = base
            .merge(tokens.text.meta)
            .copyWith(color: tokens.colors.textPrimary);
        const mono = TextStyle(fontFamily: 'monospace');
        Widget kv(String key, String text, {bool monospace = false}) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.s),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 56, child: Text(key, style: meta)),
              Expanded(
                child: SelectableText(
                  text,
                  style: monospace ? value.merge(mono) : value,
                ),
              ),
            ],
          ),
        );
        return AppSheetScaffold(
          title: '$method ${sheetContext.l10n.appLogs_request}',
          maxHeightFactor: 0.85,
          actions: [
            AppIconButton(
              icon: AppIcons.copy,
              semanticLabel: sheetContext.l10n.appLogs_copyAll,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: copyText()));
                ToastService.showSuccess(S.current.common_copiedToClipboard);
              },
            ),
          ],
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                kv(sheetContext.l10n.appLogs_time, timestamp),
                kv('URL', url, monospace: true),
                kv(sheetContext.l10n.appLogs_statusCode, statusCode),
                if (duration != null)
                  kv(sheetContext.l10n.appLogs_duration, '${duration}ms'),
                if (adapter != null)
                  kv(sheetContext.l10n.networkAdapter_adapterType, adapter),
                kv(
                  sheetContext.l10n.appLogs_level,
                  level == 'warning'
                      ? sheetContext.l10n.common_loadFailed
                      : sheetContext.l10n.common_done,
                ),
                if (extras.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.m),
                  Text(sheetContext.l10n.appLogs_otherFields, style: meta),
                  const SizedBox(height: AppSpace.xs),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpace.m),
                    decoration: BoxDecoration(
                      color: tokens.colors.surfaceElevated,
                      borderRadius: BorderRadius.circular(tokens.radius.table),
                    ),
                    child: SelectableText(
                      [for (final e in extras.entries) '${e.key}: ${e.value}']
                          .join('\n'),
                      style: value
                          .merge(mono)
                          .copyWith(fontSize: AppFontSize.caption),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String? _getRequestAdapterLabel(Map<String, dynamic> entry) {
    final adapterName = entry['networkAdapter']?.toString();
    final adapterType = tryParseAdapterType(adapterName);
    if (adapterType == null) {
      return adapterName?.isEmpty == true ? null : adapterName;
    }
    return getAdapterDisplayName(adapterType);
  }

  /// 行内时间戳：HH:mm:ss（等宽对齐）
  String _formatTime(String? timestamp) {
    if (timestamp == null) return '';
    final time = DateTime.tryParse(timestamp);
    if (time == null) return '';
    final local = time.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }

  /// 跨天分隔行的日期：M-d
  String _formatDate(DateTime local) => '${local.month}-${local.day}';

  static DateTime? _entryLocalTime(Map<String, dynamic> entry) {
    final raw = entry['timestamp']?.toString();
    if (raw == null) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  static bool _sameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return true;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _typeFilterLabel(LogTypeFilter filter) {
    return switch (filter) {
      LogTypeFilter.all => S.current.common_all,
      LogTypeFilter.general => S.current.appLogs_general,
      LogTypeFilter.request => S.current.appLogs_request,
      LogTypeFilter.lifecycle => S.current.appLogs_lifecycle,
      LogTypeFilter.cookie => S.current.appLogs_cookie,
      LogTypeFilter.network => S.current.appLogs_network,
      LogTypeFilter.cfChallenge => S.current.appLogs_cfChallenge,
      LogTypeFilter.auth => S.current.appLogs_auth,
    };
  }

  String _levelFilterLabel(_LogLevelFilter filter) {
    return switch (filter) {
      _LogLevelFilter.all => S.current.common_all,
      _LogLevelFilter.error => S.current.appLogs_error,
      _LogLevelFilter.warning => S.current.appLogs_warning,
      _LogLevelFilter.info => S.current.appLogs_info,
      _LogLevelFilter.debug => S.current.appLogs_debug,
    };
  }

  void _startSearch() {
    setState(() => _searching = true);
  }

  void _stopSearch() {
    setState(() {
      _searching = false;
      _searchController.clear();
      _applyFilters();
    });
  }

  PreferredSizeWidget _buildAppBar() {
    final tokens = context.tokens;
    if (_searching) {
      return AppNavBar(
        showDivider: true,
        automaticallyImplyLeading: false,
        leading: AppIconButton(
          icon: AppIcons.back,
          semanticLabel: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: _stopSearch,
        ),
        titleWidget: TextField(
          controller: _searchController,
          autofocus: true,
          cursorColor: tokens.colors.brandPrimary,
          style: Theme.of(context).textTheme.bodyMedium
              ?.merge(tokens.text.control)
              .copyWith(color: tokens.colors.textPrimary),
          decoration: InputDecoration(
            hintText: context.l10n.appLogs_search,
            border: InputBorder.none,
          ),
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(_applyFilters),
        ),
        trailing: [
          if (_searchController.text.isNotEmpty)
            AppIconButton(
              icon: AppIcons.close,
              semanticLabel: MaterialLocalizations.of(context)
                  .clearButtonTooltip,
              onPressed: () {
                _searchController.clear();
                setState(_applyFilters);
              },
            ),
        ],
      );
    }

    final l10n = context.l10n;
    return AppNavBar(
      title: l10n.appLogs_title,
      showDivider: true,
      slotWidth: 100,
      trailing: [
        AppIconButton(
          icon: AppIcons.search,
          semanticLabel: l10n.appLogs_search,
          onPressed: _startSearch,
        ),
        AppMenuButton<String>(
          icon: AppIcons.moreHoriz,
          semanticLabel: l10n.topicDetail_moreOptions,
          onSelected: (value) {
            switch (value) {
              case 'deviceInfo':
                _copyDeviceInfo();
              case 'copy':
                _copyAll();
              case 'save':
                _saveLog();
              case 'share':
                _shareLog();
              case 'feedback':
                _sendFeedback();
              case 'clear':
                _clearLogs();
            }
          },
          sectionsBuilder: (context) => [
            [
              AppMenuItem(
                label: l10n.appLogs_copyDeviceInfo,
                value: 'deviceInfo',
                icon: AppIcons.copy,
              ),
              AppMenuItem(
                label: l10n.appLogs_copyAll,
                value: 'copy',
                icon: AppIcons.copy,
              ),
              AppMenuItem(
                label: l10n.appLogs_saveLogs,
                value: 'save',
                icon: AppIcons.saveAlt,
              ),
              // Linux 上 share_plus 不支持分享文件,隐藏该项
              if (ShareUtils.canShareFiles)
                AppMenuItem(
                  label: l10n.appLogs_shareLogs,
                  value: 'share',
                  icon: AppIcons.share,
                ),
              AppMenuItem(
                label: l10n.appLogs_sendFeedback,
                value: 'feedback',
                icon: AppIcons.mail,
              ),
            ],
            [
              AppMenuItem(
                label: l10n.appLogs_clearLogs,
                value: 'clear',
                icon: AppIcons.delete,
                destructive: true,
              ),
            ],
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.tokens.colors.surfacePage,
      appBar: ReadableAppBar(child: _buildAppBar()),
      body: ReadableBody(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: LoadingSpinner());
    }

    if (_entries.isEmpty) {
      return AppStateView(
        icon: AppIcons.article,
        title: context.l10n.appLogs_noLogs,
      );
    }

    return Column(
      children: [
        _buildFilterBar(),
        const AppHairline(),
        // 日志列表
        Expanded(
          child: _filtered.isEmpty
              ? AppStateView(
                  icon: AppIcons.searchOff,
                  title: context.l10n.appLogs_noMatchingLogs,
                )
              : M3eRefreshIndicator(
                  onRefresh: _loadLogs,
                  child: ListView.builder(
                    itemCount: _filtered.length,
                    padding: const EdgeInsets.only(bottom: 8),
                    itemBuilder: (context, index) {
                      final entry = _filtered[index];
                      // 跨天时插入日期分隔行
                      final time = _entryLocalTime(entry);
                      Widget? dateHeader;
                      if (index > 0 &&
                          !_sameDay(
                            _entryLocalTime(_filtered[index - 1]),
                            time,
                          ) &&
                          time != null) {
                        dateHeader = _buildDateHeader(time);
                      }
                      final row = _buildLogRow(entry);
                      if (dateHeader == null) return row;
                      return Column(children: [dateHeader, row]);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildDateHeader(DateTime local) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
      color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.6),
      child: Text(
        _formatDate(local),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.outline,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// 网络请求行（设计说明 §5.4）：「GET /latest.json」13 等宽 + 右侧状态码 13
  /// （错误用 text/destructive），下面「时间 · 耗时 · 适配器」11 meta。
  Widget _buildRequestRow(Map<String, dynamic> entry) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final method = entry['method']?.toString() ?? '';
    final uri = Uri.tryParse(entry['url']?.toString() ?? '');
    final path = uri == null
        ? ''
        : (uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path);
    final status = entry['statusCode'];
    final isError = status is int && status >= 400;
    final duration = entry['duration'];
    final adapter = _getRequestAdapterLabel(entry);
    final time = _formatTime(entry['timestamp']?.toString());
    final detail = [
      if (time.isNotEmpty) time,
      if (duration != null) '${duration}ms',
      ?adapter,
    ].join(' · ');
    const mono = TextStyle(fontFamily: 'monospace', fontSize: AppFontSize.meta);
    return InkWell(
      onTap: () => _showDetail(entry),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.pageMargin,
          vertical: AppSpace.s,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: tokens.colors.separator,
              width: AppSpace.hairline,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$method $path',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono.copyWith(color: tokens.colors.textPrimary),
                  ),
                ),
                const SizedBox(width: AppSpace.s),
                if (status != null)
                  Text(
                    '$status',
                    style: mono.copyWith(
                      color: isError
                          ? tokens.colors.textDestructive
                          : tokens.colors.textMeta,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.xxs),
            Text(
              detail,
              style: theme.textTheme.labelSmall?.copyWith(
                color: tokens.colors.textMeta,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 紧凑控制台风日志行：时间戳列 + 标题/副行（错误行标题用 destructive 文字色）
  Widget _buildLogRow(Map<String, dynamic> entry) {
    if (entry['type']?.toString() == 'request') {
      return _buildRequestRow(entry);
    }
    final theme = Theme.of(context);
    final barColor = _levelBarColor(context, entry);
    final title = _getTitle(entry);
    final subtitle = _getSubtitle(entry);
    final time = _formatTime(entry['timestamp']?.toString());

    final timeStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.outline,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    // v2：不再用彩色左边条，错误行只把标题改成 destructive 文字色
    final isErrorRow = barColor == theme.colorScheme.error;
    final titleStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: AppFontSize.meta,
      color: isErrorRow ? context.tokens.colors.textDestructive : null,
    );
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return InkWell(
      onTap: () => _showDetail(entry),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: context.tokens.colors.separator,
              width: AppSpace.hairline,
            ),
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.pageMargin,
                    8,
                    AppSpace.pageMargin,
                    8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          SizedBox(
                            width: 56,
                            child: Text(time, style: timeStyle),
                          ),
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: titleStyle,
                            ),
                          ),
                        ],
                      ),
                      if (subtitle.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 56, top: 2),
                          child: _buildSubtitle(entry, subtitle, subtitleStyle),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 副行：请求类条目的状态码单独着色，其余纯文本
  Widget _buildSubtitle(
    Map<String, dynamic> entry,
    String subtitle,
    TextStyle? style,
  ) {
    final type = entry['type']?.toString();
    final statusCode = entry['statusCode'];
    if (type == 'request' && statusCode is int) {
      final statusColor = statusCode >= 400
          ? context.tokens.colors.textDestructive
          : context.tokens.colors.textMeta;
      final rest = subtitle.startsWith('$statusCode')
          ? subtitle.substring('$statusCode'.length)
          : ' $subtitle';
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$statusCode',
              style: style?.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(text: rest),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    return Text(
      subtitle,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }

  /// 筛选区：级别 chips 平铺（高频、一击直达）+ 类型下拉（低频、收纳）+ 条数
  Widget _buildFilterBar() {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    // 筛选胶囊行：级别（再点一次取消）+ 类型（点开菜单）；条数固定在右端
    return SizedBox(
      height: AppSize.categoryBar,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: AppSpace.pageMargin),
              child: Row(
                children: [
                  for (final filter in _LogLevelFilter.values)
                    if (filter != _LogLevelFilter.all) ...[
                      FilterPill(
                        label: _levelFilterLabel(filter),
                        selected: _levelFilter == filter,
                        showChevron: false,
                        onTap: () {
                          setState(() {
                            // 再点一次已选级别 = 取消级别筛选
                            _levelFilter = _levelFilter == filter
                                ? _LogLevelFilter.all
                                : filter;
                            _applyFilters();
                          });
                        },
                      ),
                      const SizedBox(width: AppSpace.s),
                    ],
                  _buildTypePill(),
                ],
              ),
            ),
          ),
          // 条数固定锚定右端：宽度变化不参与左侧布局
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.pageMargin,
            ),
            child: Text(
              S.current.appLogs_entryCount(_filtered.length),
              style: theme.textTheme.labelSmall?.copyWith(
                color: tokens.colors.textMeta,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 类型筛选胶囊：点开 v2 菜单，非「全部」时高亮
  Widget _buildTypePill() {
    return Builder(
      builder: (pillContext) => FilterPill(
        label: _typeFilterLabel(_typeFilter),
        selected: _typeFilter != LogTypeFilter.all,
        onTap: () async {
          final picked = await showAppMenu<LogTypeFilter>(
            context: pillContext,
            anchor: globalRectOf(pillContext),
            sections: [
              [
                for (final filter in LogTypeFilter.values)
                  AppMenuItem<LogTypeFilter>(
                    label: _typeFilterLabel(filter),
                    value: filter,
                    checked: filter == _typeFilter,
                  ),
              ],
            ],
          );
          if (picked == null || !mounted) return;
          setState(() {
            _typeFilter = picked;
            _applyFilters();
          });
        },
      ),
    );
  }
}
