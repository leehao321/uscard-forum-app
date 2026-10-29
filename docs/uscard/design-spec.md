# 界面设计规范（iOS 适配层）

适用范围：iOS。Android 和桌面保持现有 Material 3 Expressive 外观，不受影响。
代码入口：`lib/theme/design_tokens.dart`（`AppDesignTokens.of(context)`）。页面里只用 token，不写裸数字。
本规范不含任何论坛专属的值（域名、品牌色），品牌色仍从现有的调色板 / 种子色进来，以后做通用 Discourse 客户端时直接复用。

## 1. 原则

- 克制：一屏只有一个视觉重点；装饰靠留白和层级，不靠颜色和阴影。
- 一致：字号、字重、颜色、圆角、间距、动效都从同一套 token 取；同一种元素在每个页面长得一样。
- 对齐：左缘统一对齐页边距；分隔线缩进到文字起点；数字用等宽数字（tabular figures）。
- 自然：动效短而轻，跟随手势；不弹跳、不闪烁、不做大面积渐变。
- 可调但不走样：用户的外观设置（第 2 期）只切换 token 档位，不改单个控件。

## 2. 字体与字号（Apple 文字样式）

字体：用户没选字体时用系统字体（SF + 苹方回退）；用户导入或选择的字体通过同一套样式生效。缺字回退系统字体。
所有字号随系统动态字体（Dynamic Type，`TextScaler`）缩放；布局在 1.3 倍下不能溢出或截断关键内容。

| 样式 | 字号 / 字重 | 行高 | 用途 |
| --- | --- | --- | --- |
| largeTitle | 34 / Bold | 1.2 | 一级页大标题（滚动后收成导航栏标题） |
| title1 | 28 / Bold | 1.2 | 少用：空状态主标题 |
| title2 | 22 / Bold | 1.25 | 卡片大数字、分组大标题 |
| title3 | 20 / Semibold | 1.25 | 弹框内小节标题 |
| headline | 17 / Semibold | 1.3 | 导航栏标题、列表主标题需强调时、对话框标题 |
| body | 17 / Regular | 1.35 | 列表行文字、正文默认 |
| callout | 16 / Regular | 1.35 | 按钮内文字、次要正文 |
| subheadline | 15 / Regular | 1.35 | 话题标题（列表）、对话框正文 |
| footnote | 13 / Regular | 1.3 | 分组页眉页脚、元信息（作者 · 时间） |
| caption | 12 / Regular | 1.3 | 角标、计数、说明 |

字重只用 Regular / Semibold / Bold 三档。颜色不跟样式绑定，由颜色角色决定。

## 3. 间距（4/8pt 网格）

| token | 值 | 用途 |
| --- | --- | --- |
| space1 | 4 | 图标与紧贴文字、角标内边距 |
| space2 | 8 | 同组元素间距、元信息项之间 |
| space3 | 12 | 图标到文字、行内左右块之间 |
| space4 | 16 | 页边距 `pageMargin`、分组内左右内边距 |
| space5 | 20 | 卡片内边距（大卡片） |
| space6 | 24 | 分组与分组之间 |

- 列表行最小高度 `rowMinHeight` = 44。
- 分组页眉：上 24、下 8，左缩进 = 页边距 + 16（与行内文字对齐）。
- 不用 6、10、14 这类网格外的值；确需半格用 2。

## 4. 圆角

| token | 值 | 用途 |
| --- | --- | --- |
| radiusS | 6 | 角标、小标签、输入框内元素 |
| radiusM | 10 | 分组列表（inset grouped）、卡片、输入框 |
| radiusL | 14 | 对话框、大卡片、浮层 |
| 底部弹框 | 12（仅上方两角） | AppSheetScaffold |
| 胶囊 | 高度 / 2 | 筛选胶囊、搜索框 |

同一层级的元素圆角一致；嵌套时内层圆角 = 外层圆角 − 间距（不小于 radiusS）。

## 5. 颜色角色（浅色 / 深色）

全部从当前 ColorScheme 派生，不新增颜色值。强调色来自调色板 / 种子色。

| 角色 | 浅色 | 深色 | 用途 |
| --- | --- | --- | --- |
| label | onSurface | onSurface | 主文字 |
| secondaryLabel | onSurfaceVariant | onSurfaceVariant | 次要文字、元信息 |
| tertiaryLabel | onSurfaceVariant @ 60% | 同左 | 占位、禁用说明 |
| separator | outlineVariant | outlineVariant | 发丝分隔线（1 物理像素） |
| tint | primary | primary | 可点的文字、选中态、开关 |
| groupedBackground | surfaceContainer | surface | 分组列表页的页面底色 |
| groupedCell | surfaceContainerLowest | surfaceContainerHigh | 分组列表的单元格 |

groupedBackground 和 groupedCell 必须成对使用：页面底色还没换成 groupedBackground 时，分组单元格继续用现有卡片色（第 1 期如此，第 3 期主框架统一换页面底色时一起启用）。

对比度：文字与背景至少 WCAG AA（正文 4.5:1，大字 3:1）；派生色不达标时调整色调（第 2 期由 `contrastRatio` 自动检查）。
不在页面里写死颜色（`Colors.*` 只允许 `transparent`）。

## 6. 材质与阴影

| token | 模糊 sigma | 表面不透明度 | 用途 |
| --- | --- | --- | --- |
| thin | 10 | 72% | 浮动小控件 |
| regular | 20 | 80% | 导航栏、标签栏 |
| thick | 30 | 88% | 底部弹框、菜单 |

- 卡片和列表不用阴影（`cardShadows = false`），层级靠底色区分。
- 只有浮在内容之上的元素（菜单、浮动按钮）用 `floatingShadow`：偏移 (0, 2)、模糊 8、黑色 8%（深色 30%）。
- 毛玻璃沿用现有开关和档位；关闭时退回不透明表面，布局不变。

## 7. 动效

| token | 值 | 用途 |
| --- | --- | --- |
| fast | 150ms | 按压反馈、开关、小图标切换 |
| standard | 250ms | 展开收起、淡入淡出、列表项插入 |
| slow | 350ms | 弹框、整块内容切换 |
| 曲线 standard | easeInOutCubic | 默认 |
| 曲线 enter / exit | easeOutCubic / easeInCubic | 出现 / 消失 |
| 曲线 emphasized | fastEaseInToSlowEaseOut | 跟随手势后的回弹落位 |

- 页面切换用 Cupertino 滑动（已有），支持边缘右滑返回。
- 系统开启“减弱动态效果”（`MediaQuery.disableAnimations`）时，非必要动画直接跳到终态。
- 不用弹跳、旋转、闪光之类的装饰动画；加载用骨架屏或系统样式的菊花。

## 8. 图标

- Material Symbols Rounded，iOS 上笔画粗细 300（接近 SF Symbols）。
- 尺寸：行内 17（与 body 同高）、列表前导 22、导航栏 / 标签栏 24。
- 颜色走颜色角色：普通 secondaryLabel，可点 tint，状态色只用于状态。

## 9. 组件

| 组件 | iOS 规范 |
| --- | --- |
| 导航栏 | 标题居中 headline；滚动时不加色调、不加阴影；一级页用可收起的大标题（第 3 期） |
| 分组列表 | 一个 radiusM 圆角容器，行间发丝分隔线缩进 16；单元格 groupedCell；行高 ≥ 44 |
| 列表行 | 左右内边距 16，前导图标 22 + 间距 12，标题 body，副标题 footnote，右侧箭头 secondaryLabel |
| 开关 | 系统样式（`.adaptive`） |
| 下拉刷新 | 系统样式菊花 |
| 底部弹框 | 贴底，上方圆角 12，拖拽条 36×5，标题 headline 居中 |
| 对话框 | 圆角 radiusL，标题 headline，正文 subheadline |
| 空 / 错 / 加载 | 图标 48 tertiaryLabel + 一行说明 + 一个按钮；加载用骨架屏 |

## 10. 布局规则（逐项检查）

1. 页面左右边距统一 `pageMargin`（16）；分组列表外边距也是 16。
2. 同一行里的元素垂直居中对齐；多行时首行基线对齐。
3. 文字只在宽度受限的位置单行截断（省略号），标题最多两行；不出现被裁掉一半的字。
4. 数字用等宽数字，计数列右对齐。
5. 点击区域不小于 44×44。
6. 不出现溢出条纹（RenderFlex overflow）；日志里出现即视为失败。
7. 深色模式、动态字体 1.3 倍下逐页检查一遍。

## 11. 每期验收

- `flutter analyze`：不新增问题。
- 全量测试：与基线相比没有新增失败。
- Windows debug 能编译通过。
- 截图：关键共用组件和改过的页面用带夹具数据的 widget 测试渲染成图（iOS 平台、浅色 / 深色、1.0 / 1.3 倍字号）检查对齐、溢出、截断。不在真机或桌面上驱动 App 去请求论坛。
- 版本号升一档，出包、本地解密，交付 `.ipa` 路径；每次推送前先问。

## 12. 分期

1. token 层 + iOS 主题 + 共用组件（分组列表、弹框外壳、开关、下拉刷新）
2. 外观设置页：预设（默认 / 紧凑 / 舒适 / 大字）、实时预览、字体导入、恢复默认
3. 主框架：毛玻璃标签栏、可收起的大标题
4. 关键页面：首页列表、话题详情、我的、设置、登录
5. 镜像页（只在本地镜像分支，随加密补丁出包）
6. 其余页面
