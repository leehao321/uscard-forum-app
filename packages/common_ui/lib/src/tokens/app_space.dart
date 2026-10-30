/// v2 间距：4/8 网格，2 只用于名字与 @handle 之间（设计说明 §2.4）
abstract final class AppSpace {
  static const double xxs = 2;
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double x32 = 32;
  static const double x40 = 40;

  /// 页面左右边距；发丝线左缩进
  static const double pageMargin = 20;

  /// 0.5 发丝线（不随设备像素比变化）
  static const double hairline = 0.5;

  /// 键盘上方间距
  static const double keyboardGap = 8;
}

/// v2 固定尺寸（0.4.0 计划 §3.4）。都是最小值或视觉尺寸，文字变大时
/// 行高可以撑高；「框架」类控件在组件里封顶字号。
abstract final class AppSize {
  /// 最小点击区
  static const double hit = 44;

  /// 导航栏、分类条、收起的工具栏
  static const double navBar = 44;
  static const double categoryBar = 44;
  static const double toolbarCollapsed = 44;

  /// 分组列表行、半屏选项行（最小高）
  static const double row48 = 48;

  /// 底部工具栏（不含安全区）
  static const double toolbar = 64;

  /// 列表行：单行标题 72，两行 96（最小高）
  static const double topicRow = 72;
  static const double topicRowTwoLine = 96;

  /// 楼层按钮 128×48、回复按钮高 48
  static const double floorButtonWidth = 128;
  static const double floorButtonHeight = 48;
  static const double replyButton = 48;

  /// 收起态楼层胶囊高 32，左右内边距 12
  static const double floorPill = 32;

  /// 浮动 Tab 胶囊 58、Tab 项 62×37、搜索胶囊 58
  static const double tabCapsule = 58;
  static const double tabItemWidth = 62;
  static const double tabItemHeight = 37;
  static const double searchCapsule = 58;

  /// 字母头像：34 / 40（字母 17）、64（字母 22）
  static const double avatarS = 34;
  static const double avatarM = 40;
  static const double avatarL = 64;

  /// 图标 24 / 20 / 16
  static const double iconL = 24;
  static const double iconM = 20;
  static const double iconS = 16;

  /// 未读点
  static const double unreadDot = 8;

  /// 对话框宽 320（左右 60）；带输入时左右 40
  static const double dialogWidth = 320;
  static const double dialogInsetInput = 40;

  /// 标题菜单 240、上下文菜单 260
  static const double menuWidth = 240;
  static const double contextMenuWidth = 260;

  /// 左滑按钮宽
  static const double swipeAction = 72;

  /// 阅读列最大宽（含列内左右 20，正文行宽 600）
  static const double readableMaxWidth = 640;

  /// 拖拽条 36×5
  static const double sheetHandleWidth = 36;
  static const double sheetHandleHeight = 5;

  /// Toast 高 44，在工具栏或 Tab 胶囊上方 16
  static const double toast = 44;
  static const double toastGap = 16;

  /// 行内表情 18；表情面板高 336、8 列、表情 28
  static const double emojiInline = 18;
  static const double emojiPanel = 336;
  static const double emojiPanelItem = 28;
  static const int emojiPanelColumns = 8;
}
