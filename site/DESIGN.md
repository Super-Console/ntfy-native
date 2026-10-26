# ntfy-native 网站视觉规范

## 技术与定位

纯静态 HTML、CSS、JavaScript；无框架、Tailwind 或组件库，不安装依赖。固定深色主题，使用 color-scheme: dark，并支持 prefers-reduced-motion。中英双语单页；中文默认部署于 `/ntfy-native/`，英文版部署于 `/ntfy-native/en/`。

方向：现代、克制、宽松。区别于 Local Transcribe / Murmur 的浅色天空与居中首屏，采用石墨底色、薄荷绿信号、左右分栏首屏与终端式说明。产品交互是明确标注的 HTML 示意，不冒充截图。

## 层级与尺度

- 产品定位为第一层，演示/功能/下载为第二层，版本/边界为第三层。
- 文字三级：`--color-text` / `--color-secondary` / `--color-muted`。品牌绿只用于语义强调与信号。
- 字重仅 400 与 600。系统无衬线字体；英文技术标记、命令和时间使用系统等宽字体，无外部字体请求。
- 字号基准：12、14、16、18、20、24、30、36、48、60、72px。移动端元数据和长命令补充 10/11px 紧凑 token；主要正文不低于 14px。
- 间距：4、8、12、16、24、32、48、64、96、128px；组间距大于组内距。
- 圆角基准 16px，菜单栏示意小物件 8px；边框 1px；键盘焦点 2px。
- 唯一品牌色实心行动是首屏下载入口；底部下载使用中性色，导航与演示降级处理。
- 五级阴影沿用技能基准；只在悬浮产品示意上使用最高级。普通内容以底色、留白、必要的分隔线区分。

## 调色来源

品牌基色 `#6de7b7` 呼应应用绿色图标，由 refactoring-ui 的 generate_palette.py 算法生成完整色阶。中性色用 neutral temperature、darkest=9、extended 生成，950 作为页面背景，900 作为抬升表面。真实文字组合记录于 design-tokens.json 的 pairs，须通过 check_contrast.py。

CSS 使用语义 token；没有 Tailwind，因此不生成或引入 Tailwind 配置。preview.html 仅作为开发预览，不发布到线上。

## 内容边界

只陈述 README、代码与已发布 v0.1.0 安装包可核实的功能。不可写“端到端加密”“完全离线”“已公证”“开源”“支持 Intel”“登录自启完整验证”。下载指向已存在的 GitHub Release，不重新分发或改包。

新增尺度应先加入 token 文档，不按组件随意造色。调亮文字优先于牺牲对比度；不靠颜色单独说明连接状态。交互演示不申请系统通知、不连接 ntfy、不收集数据。
