import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';

import '../../../../../l10n/s.dart';
import 'markdown_toolbar.dart';

/// 编辑器工具定义
///
/// 工具栏收起态、展开网格和快捷面板共用同一份注册表（[editorTools]）。
/// 普通工具提供 [action]；需要二级选择的工具（标题、Callout）提供
/// [menuItems] + [onMenuSelected]。
class EditorTool {
  /// 稳定 id，用于偏好存储（外显工具列表）
  final String id;

  /// 图标（FaIcon / Icon，尺寸颜色由使用方通过 IconTheme 控制）
  final Widget icon;

  /// 标签文案
  final String Function(AppLocalizations s) label;

  /// 普通工具动作
  final void Function(MarkdownToolbarState toolbar)? action;

  /// 二级弹出菜单项（与 [onMenuSelected] 成对出现）
  final List<AppMenuItem<String>> Function(AppLocalizations s)? menuItems;

  /// 二级弹出菜单选中回调
  final void Function(MarkdownToolbarState toolbar, String value)?
      onMenuSelected;

  const EditorTool({
    required this.id,
    required this.icon,
    required this.label,
    this.action,
    this.menuItems,
    this.onMenuSelected,
  }) : assert(
          (action != null) != (menuItems != null && onMenuSelected != null),
          '普通工具提供 action，菜单工具提供 menuItems + onMenuSelected',
        );

  bool get hasMenu => menuItems != null;
}

/// 图片上传工具的 id（工具栏对其特殊渲染上传进度）
const String kEditorToolImage = 'image';

/// 全部编辑器工具（顺序即面板网格与工具栏外显顺序）
final List<EditorTool> editorTools = [
  EditorTool(
    id: kEditorToolImage,
    icon: const Icon(AppIcons.image),
    label: (s) => s.toolPanel_image,
    action: (t) => t.pickAndUploadImages(),
  ),
  EditorTool(
    id: 'attachment',
    icon: const Icon(AppIcons.paperclip),
    label: (s) => s.toolPanel_attachment,
    action: (t) => t.pickAndUploadFile(),
  ),
  // 音视频改名上传(.xz 绕站点扩展名白名单,4MB 上限;插 <audio>/<video>
  // 标签,网页端原生播放)
  EditorTool(
    id: 'media',
    icon: const Icon(AppIcons.video),
    label: (s) => '音视频',
    menuItems: (s) => const [
      AppMenuItem<String>(value: 'audio', label: '上传音频'),
      AppMenuItem<String>(value: 'video', label: '上传视频'),
      AppMenuItem<String>(value: 'voice', label: '语音消息'),
    ],
    onMenuSelected: (t, value) => value == 'voice'
        ? t.recordAndInsertVoice()
        : t.pickAndUploadMedia(isAudio: value == 'audio'),
  ),
  EditorTool(
    id: 'heading',
    icon: const Icon(AppIcons.heading),
    label: (s) => s.toolPanel_heading,
    menuItems: (s) => [
      AppMenuItem<String>(value: '1', label: s.toolbar_h1),
      AppMenuItem<String>(value: '2', label: s.toolbar_h2),
      AppMenuItem<String>(value: '3', label: s.toolbar_h3),
      AppMenuItem<String>(value: '4', label: s.toolbar_h4),
      AppMenuItem<String>(value: '5', label: s.toolbar_h5),
    ],
    onMenuSelected: (t, value) =>
        t.applyLinePrefix('${'#' * int.parse(value)} '),
  ),
  EditorTool(
    id: 'bold',
    icon: const Icon(AppIcons.textBold),
    label: (s) => s.toolPanel_bold,
    action: (t) => t.wrapSelection('**', '**',
        placeholder: S.current.toolbar_boldPlaceholder),
  ),
  EditorTool(
    id: 'italic',
    icon: const Icon(AppIcons.textItalic),
    label: (s) => s.toolPanel_italic,
    action: (t) =>
        t.wrapSelection('*', '*', placeholder: S.current.toolbar_italicPlaceholder),
  ),
  EditorTool(
    id: 'strikethrough',
    icon: const Icon(AppIcons.textStrike),
    label: (s) => s.toolPanel_strikethrough,
    action: (t) => t.insertStrikethrough(),
  ),
  EditorTool(
    id: 'bulletList',
    icon: const Icon(AppIcons.listBulleted),
    label: (s) => s.toolPanel_bulletList,
    action: (t) => t.applyLinePrefix('- '),
  ),
  EditorTool(
    id: 'numberedList',
    icon: const Icon(AppIcons.listNumbered),
    label: (s) => s.toolPanel_numberedList,
    action: (t) => t.applyLinePrefix('1. '),
  ),
  EditorTool(
    id: 'link',
    icon: const Icon(AppIcons.link),
    label: (s) => s.toolPanel_link,
    // 使用工具栏自身的 context：面板收起后该 context 仍然有效
    action: (t) => t.insertLink(t.context),
  ),
  EditorTool(
    id: 'quote',
    icon: const Icon(AppIcons.formatQuote),
    label: (s) => s.toolPanel_quote,
    action: (t) => t.insertQuote(),
  ),
  EditorTool(
    id: 'callout',
    icon: const Icon(AppIcons.callout),
    label: (s) => s.toolPanel_callout,
    menuItems: (s) => const [
      AppMenuItem<String>(value: 'note', label: 'Note'),
      AppMenuItem<String>(value: 'tip', label: 'Tip'),
      AppMenuItem<String>(value: 'info', label: 'Info'),
      AppMenuItem<String>(value: 'warning', label: 'Warning'),
      AppMenuItem<String>(value: 'danger', label: 'Danger'),
      AppMenuItem<String>(value: 'bug', label: 'Bug'),
      AppMenuItem<String>(value: 'example', label: 'Example'),
      AppMenuItem<String>(value: 'quote', label: 'Quote'),
      AppMenuItem<String>(value: 'abstract', label: 'Abstract'),
      AppMenuItem<String>(value: 'todo', label: 'Todo'),
      AppMenuItem<String>(value: 'success', label: 'Success'),
      AppMenuItem<String>(value: 'question', label: 'Question'),
      AppMenuItem<String>(value: 'failure', label: 'Failure'),
    ],
    onMenuSelected: (t, value) => t.insertCallout(value),
  ),
  EditorTool(
    id: 'template',
    icon: const Icon(AppIcons.layoutTemplate),
    label: (s) => s.toolPanel_template,
    action: (t) => t.insertTemplate(t.context),
  ),
  EditorTool(
    id: 'inlineCode',
    icon: const Icon(AppIcons.code),
    label: (s) => s.toolPanel_inlineCode,
    action: (t) => t.insertInlineCode(),
  ),
  EditorTool(
    id: 'codeBlock',
    icon: const Icon(AppIcons.squareCode),
    label: (s) => s.toolPanel_codeBlock,
    action: (t) => t.insertCodeBlock(),
  ),
  // 块级模板插入(与富 composer「+」插入菜单同款模板文本)
  EditorTool(
    id: 'insertBlock',
    icon: const Icon(AppIcons.squarePlus),
    label: (s) => '插入块',
    menuItems: (s) => const [
      AppMenuItem<String>(value: 'table', label: '表格'),
      AppMenuItem<String>(value: 'math', label: '公式块'),
      AppMenuItem<String>(value: 'hr', label: '分隔线'),
      AppMenuItem<String>(value: 'details', label: '折叠详情'),
    ],
    onMenuSelected: (t, value) => t.insertBlockSnippet(switch (value) {
      'table' => '| 列 1 | 列 2 |\n|---|---|\n| 内容 | 内容 |',
      'math' => '\$\$\nE=mc^2\n\$\$',
      'hr' => '---',
      _ => '[details="点开看"]\n折叠内容\n[/details]',
    }),
  ),
  EditorTool(
    id: 'spoiler',
    icon: const Icon(AppIcons.visibilityOff),
    label: (s) => s.toolPanel_spoiler,
    action: (t) => t.insertSpoiler(),
  ),
  EditorTool(
    id: 'encrypt',
    icon: const Icon(AppIcons.lock),
    label: (s) => s.crypto_encrypt,
    action: (t) => t.insertEncryptedBlock(),
  ),
  EditorTool(
    id: 'poll',
    icon: const Icon(AppIcons.poll),
    label: (s) => '投票',
    action: (t) => t.insertPoll(t.context),
  ),
  // 目录(DiscoTOC 同款):div 标记包裹内容,阅读侧据此生成目录树。
  // 空行让 markdown-it 结束 html_block、内部标题正常 cook;仅 1 楼生效
  // (对齐 DiscoTOC 默认 enable_TOC_for_replies=false)。注意:富文本
  // composer 往返会丢弃该包裹 div(通用容器拆壳),用 Markdown 模式编辑。
  EditorTool(
    id: 'toc',
    icon: const Icon(AppIcons.tableOfContents),
    label: (s) => s.toolPanel_toc,
    action: (t) => t.wrapSelection(
      '\n<div data-theme-toc="true">\n\n',
      '\n\n</div>\n',
      placeholder: S.current.toolbar_tocPlaceholder,
    ),
  ),
  EditorTool(
    id: 'imageGrid',
    icon: const Icon(AppIcons.layoutGrid),
    label: (s) => s.toolPanel_imageGrid,
    action: (t) => t.wrapImagesInGrid(),
  ),
];

/// 按注册表顺序过滤出外显工具
List<EditorTool> resolveVisibleTools(List<String> ids) {
  final byId = {for (final tool in editorTools) tool.id: tool};
  return [for (final id in ids.toSet()) if (byId[id] != null) byId[id]!];
}
