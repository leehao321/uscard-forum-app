// 全局图标中心层 —— 图标统一收口
//
// 规则（务必遵守）：
//   1. 0.4.0（v2 设计）起只用 Lucide 线框图标，300 字重（描边约 1.55，
//      最接近 Figma 稿里的 1.75；描边随图标尺寸等比缩放）；缺失时走自绘
//      （AppCustomIcon）。尺寸只用 24 / 20 / 16（AppSize.iconL/M/S）。
//   2. 业务/页面代码禁止直接引用 `Icons.*` / `Symbols.*` / `LucideIcons*`，
//      所有图标必须经过本文件暴露的 AppIcons 常量。页面里残留的
//      `Symbols.*` 随各里程碑迁到这里（tool/ui_audit.dart 统计）。
//   3. 图标恒为线框。Lucide 没有填充轴，`Icon(fill:)` 对它无效；需要
//      「选中 / 未选中」两态时用颜色区分（brand/primary vs text/meta），
//      自绘图标仍可用 fill。
//   4. 自绘图标：用 [AppCustomIcon] 包装 [IconPainterBuilder]，并在调用处用
//      [AppIcon] 渲染。AppCustomIcon 同样支持 fill/size/color，遵循 IconTheme。
//   5. 例外：社区数据驱动的 badge/tag/category 图标继续走 font_awesome。
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons_300.dart';

import 'icon_painters.dart';

/// 一个"图标值"——可能是字体图标（[IconData]）或自绘图标（[AppCustomIcon]）。
///
/// 中心层暴露的所有图标常量都是 [AppIconSpec]；调用方用 [AppIcon] 渲染时
/// 不需要关心背后是字体还是自绘。
sealed class AppIconSpec {
  const AppIconSpec();
}

/// 字体图标（Lucide 等）。
class AppFontIcon extends AppIconSpec {
  final IconData data;
  const AppFontIcon(this.data);
}

/// 自绘图标。提供一个 painter builder：`(color, fill) → CustomPainter`。
///
/// `fill` 取自全局 IconTheme 或调用方 [AppIcon] 传入；painter 应在 0~1 之间平滑
/// 过渡轮廓与填充。如果自绘图标只支持单形态，painter 可忽略 fill。
class AppCustomIcon extends AppIconSpec {
  final IconPainterBuilder painterBuilder;

  /// 设计稿尺寸（painter 用归一化坐标时应基于此 box）。渲染时按 size 缩放。
  final Size designSize;
  const AppCustomIcon(
    this.painterBuilder, {
    this.designSize = const Size(24, 24),
  });
}

/// painter 构造函数签名。color/fill 由 [AppIcon] 渲染时注入。
typedef IconPainterBuilder =
    CustomPainter Function({
      required Color color,
      required double fill,
      required double strokeWidth,
    });

/// 内部隐式转换：直接把 [IconData] 当 [AppIconSpec] 用。
extension IconDataToSpec on IconData {
  AppFontIcon get asSpec => AppFontIcon(this);
}

/// 全 App 图标统一出口。仅暴露常量，不要在这里写组件。
abstract final class AppIcons {
  // ─── 导航 / 通用操作 ────────────────────────────────────────────────
  static const close = LucideIcons300.x;
  static const back = LucideIcons300.chevronLeft;
  static const forward = LucideIcons300.arrowRight;
  static const up = LucideIcons300.arrowUp;
  static const down = LucideIcons300.arrowDown;
  static const chevronLeft = LucideIcons300.chevronLeft;
  static const chevronRight = LucideIcons300.chevronRight;
  static const qrCode = LucideIcons300.qrCode;
  static const chevronDown = LucideIcons300.chevronDown;
  static const chevronUp = LucideIcons300.chevronUp;
  static const expandMore = LucideIcons300.chevronDown;
  static const expandLess = LucideIcons300.chevronUp;
  static const dropdown = LucideIcons300.chevronDown;
  static const dropup = LucideIcons300.chevronUp;
  static const menu = LucideIcons300.menu;
  static const moreHoriz = LucideIcons300.ellipsis;
  static const moreVert = LucideIcons300.ellipsisVertical;
  static const check = LucideIcons300.check;
  static const checkAll = LucideIcons300.checkCheck;
  static const add = LucideIcons300.plus;
  static const remove = LucideIcons300.minus;
  static const search = LucideIcons300.search;
  static const filter = LucideIcons300.listFilter;
  static const filterOff = LucideIcons300.funnelX;
  static const sort = LucideIcons300.arrowDownWideNarrow;
  static const tune = LucideIcons300.slidersHorizontal;
  static const refresh = LucideIcons300.refreshCw;
  static const sync = LucideIcons300.refreshCcw;
  static const undo = LucideIcons300.undo2;
  static const redo = LucideIcons300.redo2;

  // ─── v2 语义名（设计说明 §2.6、§5） ─────────────────────────────────
  /// 发帖入口
  static const compose = LucideIcons300.squarePen;

  /// 楼层按钮 / 楼层胶囊
  static const floor = LucideIcons300.arrowUpDown;

  /// 全部标为已读
  static const markAllRead = LucideIcons300.checkCheck;

  /// 通知类型：提及
  static const mention = LucideIcons300.atSign;

  /// 通知类型：关注
  static const follow = LucideIcons300.userPlus;

  // ─── 编辑 / 内容 ───────────────────────────────────────────────────
  static const copy = LucideIcons300.copy;
  static const cut = LucideIcons300.scissors;
  static const paste = LucideIcons300.clipboardPaste;
  static const delete = LucideIcons300.trash2;
  static const edit = LucideIcons300.pen;
  static const save = LucideIcons300.save;
  static const saveAlt = LucideIcons300.download;
  static const download = LucideIcons300.download;
  static const upload = LucideIcons300.upload;
  static const share = LucideIcons300.share;
  static const reply = LucideIcons300.reply;
  static const replyAll = LucideIcons300.replyAll;
  static const forwardMsg = LucideIcons300.forward;
  static const send = LucideIcons300.send;
  static const openInNew = LucideIcons300.externalLink;
  static const link = LucideIcons300.link;
  static const linkOff = LucideIcons300.unlink;
  static const code = LucideIcons300.code;
  static const formatQuote = LucideIcons300.quote;

  // ─── 媒体 ─────────────────────────────────────────────────────────
  static const image = LucideIcons300.image;
  static const imageBroken = LucideIcons300.imageOff;
  static const videoLibrary = LucideIcons300.video;
  static const play = LucideIcons300.play;
  static const pause = LucideIcons300.pause;
  static const camera = LucideIcons300.camera;
  static const brush = LucideIcons300.brush;
  static const gallery = LucideIcons300.images;

  // ─── 状态类（两态用颜色区分，见规则 3） ─────────────────────────────
  static const bookmark = LucideIcons300.bookmark;
  static const notification = LucideIcons300.bell;
  // 通知级别：静音 / 关注（每条都通知）/ 跟踪 / 常规用 notification
  static const notificationOff = LucideIcons300.bellOff;
  static const notificationActive = LucideIcons300.bellRing;
  static const notificationAdd = LucideIcons300.bellPlus;
  static const favorite = LucideIcons300.heart;
  static const star = LucideIcons300.star;
  static const heart = LucideIcons300.heart;
  static const visibility = LucideIcons300.eye;
  static const visibilityOff = LucideIcons300.eyeOff;
  static const pushPin = LucideIcons300.pin;
  static const chatBubble = LucideIcons300.messageCircle;
  static const thumbUp = LucideIcons300.thumbsUp;
  static const thumbDown = LucideIcons300.thumbsDown;
  static const checkBox = LucideIcons300.squareCheck;
  static const radioButton = LucideIcons300.circleDot;
  static const radioButtonOff = LucideIcons300.circle;
  static const playCircle = LucideIcons300.circlePlay;

  // ─── 用户 / 账户 ───────────────────────────────────────────────────
  static const person = LucideIcons300.user;
  static const people = LucideIcons300.users;
  static const account = LucideIcons300.circleUser;
  static const login = LucideIcons300.logIn;
  static const logout = LucideIcons300.logOut;
  static const lock = LucideIcons300.lock;
  static const lockOpen = LucideIcons300.lockOpen;
  static const key = LucideIcons300.key;
  static const shield = LucideIcons300.shield;
  static const security = LucideIcons300.shieldCheck;
  static const verifiedUser = LucideIcons300.badgeCheck;
  static const medal = LucideIcons300.award;

  // ─── 通讯 ─────────────────────────────────────────────────────────
  static const mail = LucideIcons300.mail;
  static const forum = LucideIcons300.messagesSquare;
  static const message = LucideIcons300.messageSquare;
  static const announcement = LucideIcons300.megaphone;

  // ─── 状态提示 ──────────────────────────────────────────────────────
  static const info = LucideIcons300.info;
  static const help = LucideIcons300.circleHelp;
  static const warning = LucideIcons300.triangleAlert;
  static const error = LucideIcons300.circleAlert;
  static const checkCircle = LucideIcons300.circleCheck;
  static const cancelCircle = LucideIcons300.circleX;
  static const removeCircle = LucideIcons300.circleMinus;
  static const doNotDisturb = LucideIcons300.circleMinus;
  static const block = LucideIcons300.ban;
  static const wifiOff = LucideIcons300.wifiOff;
  static const readLater = LucideIcons300.layers;
  static const note = LucideIcons300.stickyNote;
  static const hot = LucideIcons300.flame;
  static const assign = LucideIcons300.userCheck;
  static const archive = LucideIcons300.archive;
  static const unarchive = LucideIcons300.archiveRestore;
  static const serverOff = LucideIcons300.serverOff;
  static const shieldAlert = LucideIcons300.shieldAlert;
  static const timerOff = LucideIcons300.timerOff;
  static const notFound = LucideIcons300.fileQuestion;
  static const dataError = LucideIcons300.braces;
  static const inbox = LucideIcons300.inbox;
  static const searchOff = LucideIcons300.searchX;
  static const northWest = LucideIcons300.arrowUpLeft;
  static const flag = LucideIcons300.flag;
  static const loading = LucideIcons300.hourglass;

  // ─── 分类 / 设置 / 杂项 ────────────────────────────────────────────
  static const settings = LucideIcons300.settings;
  static const home = LucideIcons300.house;
  static const article = LucideIcons300.fileText;
  static const book = LucideIcons300.bookOpen;
  static const autoStories = LucideIcons300.bookOpenText;
  static const folder = LucideIcons300.folder;
  static const accountTree = LucideIcons300.listTree;
  static const category = LucideIcons300.layoutGrid;
  static const tag = LucideIcons300.tag;
  static const history = LucideIcons300.history;
  static const lockClock = LucideIcons300.lockKeyhole;
  static const cloud = LucideIcons300.cloud;
  static const cloudOff = LucideIcons300.cloudOff;
  static const hub = LucideIcons300.network;
  static const language = LucideIcons300.languages;
  static const palette = LucideIcons300.palette;
  static const colorLens = LucideIcons300.palette;
  static const speed = LucideIcons300.gauge;
  static const rocket = LucideIcons300.rocket;
  static const touchApp = LucideIcons300.pointer;
  static const wallet = LucideIcons300.wallet;
  static const token = LucideIcons300.coins;
  static const description = LucideIcons300.fileText;
  static const military = LucideIcons300.medal;
  static const addComment = LucideIcons300.messageSquarePlus;
  static const emoji = LucideIcons300.smile;
  static const autoAwesome = LucideIcons300.sparkles;
  static const autoFixHigh = LucideIcons300.wandSparkles;
  static const callSplit = LucideIcons300.split;

  // ─── 编辑器（0.4.0 M5）──────────────────────────────────────────────
  static const addCircle = LucideIcons300.circlePlus;
  static const appWindow = LucideIcons300.appWindow;
  static const audio = LucideIcons300.music;
  static const backspace = LucideIcons300.delete;
  static const bookOpen = LucideIcons300.bookOpen;
  static const braces = LucideIcons300.braces;
  static const calendar = LucideIcons300.calendar;
  static const carousel = LucideIcons300.galleryHorizontal;
  static const chevronsUpDown = LucideIcons300.chevronsUpDown;
  static const circleChevronDown = LucideIcons300.circleChevronDown;
  static const clipboardCheck = LucideIcons300.clipboardCheck;
  static const clipboardList = LucideIcons300.clipboardList;
  static const clock = LucideIcons300.clock;
  static const cloudDone = LucideIcons300.cloudCheck;
  static const cloudUpload = LucideIcons300.cloudUpload;
  static const columns = LucideIcons300.columns3;
  static const cornerReturn = LucideIcons300.cornerDownLeft;
  static const eraser = LucideIcons300.eraser;
  static const file = LucideIcons300.file;
  static const flask = LucideIcons300.flaskConical;
  static const gridOff = LucideIcons300.grid2x2X;
  static const gridView = LucideIcons300.layoutGrid;
  static const grip = LucideIcons300.gripVertical;
  static const hash = LucideIcons300.hash;
  static const heading = LucideIcons300.heading;
  static const keyboard = LucideIcons300.keyboard;
  static const layoutTemplate = LucideIcons300.layoutTemplate;
  static const listBulleted = LucideIcons300.list;
  static const listNumbered = LucideIcons300.listOrdered;
  static const lockKeyhole = LucideIcons300.lockKeyhole;
  static const maximize = LucideIcons300.maximize2;
  static const mic = LucideIcons300.mic;
  static const minimize = LucideIcons300.minimize2;
  static const paperclip = LucideIcons300.paperclip;
  static const pencilLine = LucideIcons300.pencilLine;
  static const poll = LucideIcons300.chartNoAxesColumn;
  static const rows = LucideIcons300.rows3;
  static const scaling = LucideIcons300.scaling;
  static const selectAll = LucideIcons300.boxSelect;
  static const sigma = LucideIcons300.sigma;
  static const smile = LucideIcons300.smile;
  static const space = LucideIcons300.space;
  static const sparkles = LucideIcons300.sparkles;
  static const stop = LucideIcons300.square;
  static const superscript = LucideIcons300.superscript;
  static const swapHoriz = LucideIcons300.arrowLeftRight;
  static const table = LucideIcons300.table;
  static const textSelect = LucideIcons300.textSelect;
  static const textType = LucideIcons300.type;
  static const toTop = LucideIcons300.arrowUpToLine;
  static const wand = LucideIcons300.wandSparkles;
  static const workflow = LucideIcons300.workflow;
  // M7（个人列表、用户主页、徽章等）
  static const micOff = LucideIcons300.micOff;
  static const fileOpen = LucideIcons300.fileInput;
  static const alarm = LucideIcons300.alarmClock;
  static const alarmOff = LucideIcons300.alarmClockOff;
  static const globe = LucideIcons300.globe;
  static const mapPin = LucideIcons300.mapPin;
  static const folderOpen = LucideIcons300.folderOpen;
  static const zap = LucideIcons300.zap;
  static const folderUp = LucideIcons300.folderUp;
  static const volumeOn = LucideIcons300.volume2;
  static const volumeOff = LucideIcons300.volumeOff;
  static const repeat = LucideIcons300.repeat;
  static const userOff = LucideIcons300.userX;
  static const arrowUpRight = LucideIcons300.arrowUpRight;
  static const trophy = LucideIcons300.trophy;
  static const infinite = LucideIcons300.infinity;

  // ─── 自绘图标（Lucide 没有合适字形时） ─────────────────────────────
  static final AppCustomIcon openBook = AppCustomIcon(
    ({required color, required fill, required strokeWidth}) =>
        OpenBookPainter(color: color, strokeWidth: strokeWidth),
  );

  static final AppCustomIcon paperPlane = AppCustomIcon(
    ({required color, required fill, required strokeWidth}) =>
        PaperPlanePainter(color: color, strokeWidth: strokeWidth),
  );

  static final AppCustomIcon contentActions = AppCustomIcon(
    ({required color, required fill, required strokeWidth}) =>
        ContentActionsPainter(color: color, strokeWidth: strokeWidth),
  );

  // ---- M9 自有功能 ----
  static const compass = LucideIcons300.compass;
  static const layers = LucideIcons300.layers;
  static const restartAlt = LucideIcons300.rotateCcw;
  static const brain = LucideIcons300.brain;
  static const typeIcon = LucideIcons300.type;
  static const stopSquare = LucideIcons300.square;
  static const bot = LucideIcons300.bot;
  static const server = LucideIcons300.server;
  static const volumeUp = LucideIcons300.volume2;
  static const volumeDown = LucideIcons300.volume1;
  static const fastForward = LucideIcons300.fastForward;
  static const rewind = LucideIcons300.rewind;
  static const cube = LucideIcons300.box;
  static const database = LucideIcons300.database;
  static const mapIcon = LucideIcons300.map;
  static const lightbulb = LucideIcons300.lightbulb;
  static const hourglass = LucideIcons300.hourglass;
  static const wrench = LucideIcons300.wrench;
  static const grid = LucideIcons300.grid3x3;
  static const listChecks = LucideIcons300.listChecks;
  static const squareIcon = LucideIcons300.square;
  static const listIcon = LucideIcons300.list;
  static const sun = LucideIcons300.sun;
  static const layoutGrid = LucideIcons300.layoutGrid;
  static const cameraOff = LucideIcons300.cameraOff;

  // ---- M10 Y ----
  static const circleIcon = LucideIcons300.circle;
  static const gitMerge = LucideIcons300.gitMerge;
  static const octagonX = LucideIcons300.octagonX;
  static const scan = LucideIcons300.scan;
  static const circleEllipsis = LucideIcons300.circleEllipsis;
  static const chartBar = LucideIcons300.chartBar;
  static const chartLine = LucideIcons300.chartLine;
  static const repeatIcon = LucideIcons300.repeat;
  static const clockIcon = LucideIcons300.clock;
  static const videoOff = LucideIcons300.videoOff;
  static const video = LucideIcons300.video;
  static const chevronsDownUp = LucideIcons300.chevronsDownUp;
  // ---- /M10 Y ----

  // ---- M10 X ----
  static const arrowUp = LucideIcons300.arrowUp;
  static const arrowDown = LucideIcons300.arrowDown;
  static const cornerDownRight = LucideIcons300.cornerDownRight;
  static const userMinus = LucideIcons300.userMinus;
  static const userPlus = LucideIcons300.userPlus;
  static const userSearch = LucideIcons300.userSearch;
  static const chevronFirst = LucideIcons300.chevronFirst;
  static const chevronLast = LucideIcons300.chevronLast;
  static const hand = LucideIcons300.hand;
  static const moveRight = LucideIcons300.moveRight;
  static const skipForward = LucideIcons300.skipForward;
  // ---- /M10 X ----
  // ---- M10 Z ----
  static const textBold = LucideIcons300.bold;
  static const textItalic = LucideIcons300.italic;
  static const textStrike = LucideIcons300.strikethrough;
  static const clipboard = LucideIcons300.clipboard;
  static const fileCode = LucideIcons300.fileCode;
  static const squarePlus = LucideIcons300.squarePlus;
  static const alignLeft = LucideIcons300.textAlignStart;
  static const textCursor = LucideIcons300.textCursor;
  static const handHeart = LucideIcons300.handHeart;
  // ---- /M10 Z ----
  // ---- M10 收尾 ----
  static const callout = LucideIcons300.messageSquareWarning;
  static const squareCode = LucideIcons300.squareCode;
  static const tableOfContents = LucideIcons300.tableOfContents;
  static const heading1 = LucideIcons300.heading1;
  static const heading2 = LucideIcons300.heading2;
  static const heading3 = LucideIcons300.heading3;
  // ---- /M10 收尾 ----


  // 表情 Tab 用的笑脸（更柔和，配合 fill 切实/空）
  static final AppCustomIcon smileyOutline = AppCustomIcon(
    ({required color, required fill, required strokeWidth}) =>
        SmileyPainter(color: color, fill: fill, strokeWidth: strokeWidth),
  );
  // 贴纸 Tab 用的贴纸图标
  static final AppCustomIcon stickerOutline = AppCustomIcon(
    ({required color, required fill, required strokeWidth}) =>
        StickerPainter(color: color, fill: fill, strokeWidth: strokeWidth),
  );
}
