/// 应用内通用 UI 组件库。
///
/// 目前提供:
/// - 支持滑动关闭、缩放/链式关闭等交互的弹出菜单封装,替代原生
///   [PopupMenuButton] / showMenu,统一全局菜单交互;
/// - [GlassSurface]:柔光玻璃材质(局部背景折射、边缘光与色散),
///   按 [GlassRecipe] 按阅读密度分级的场景配方使用。
/// - [DesktopScrollInteractionBehavior] 与 [DesktopScrollInteractionBinding]:
///   统一桌面滚动期间的控件点击，接入应用入口即可覆盖后代滚动容器。
/// - v2 设计 token（0.4.0）：[AppTokens]（`context.tokens`）汇总颜色、
///   字号、圆角、材质与外观档位；固定间距与尺寸在 [AppSpace]、[AppSize]。
/// - v2 共享组件（0.4.0）：导航栏、图标按钮、菜单、对话框、半屏外壳、
///   筛选、头像、加载与空错状态、浮动胶囊、左滑操作、阅读列等，见
///   `src/ui/ui.dart`。
library;

export 'src/tokens/tokens.dart';
export 'src/ui/ui.dart';

export 'src/app_sheet_scaffold.dart';
export 'src/dismissible_popup_menu.dart';
export 'src/desktop_scroll_interaction.dart';
export 'src/glass_settings.dart';
export 'src/glass_surface.dart';
export 'src/glass_surface_frame.dart';
export 'src/predictive_back_cupertino_transitions.dart';
