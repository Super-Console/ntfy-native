# ntfy-native 网站

纯静态中文产品页；公开地址：<https://apps.timhuang.net/ntfy-native/>。

## 本地预览

在项目根运行 `python3 -m http.server 8766 --bind 127.0.0.1 --directory site`，访问 `http://127.0.0.1:8766/`。不需要安装依赖。

## 发布白名单

只发布 `index.html`、`assets/site.css`、`assets/site.js`、`assets/tokens.css`、`assets/app-icon.png`。不发布源码、开发文档、token JSON、日志、测试脚本或本地应用包。

所有静态引用为相对路径，兼容 `/ntfy-native/`；canonical / Open Graph 固定为正式地址。无斜线入口应 301 到 `/ntfy-native/`。

下载指向 GitHub v0.1.0 已发布 ZIP。当前仅 Apple silicon、macOS 13+，ad-hoc 签名、未公证。更新下载版本时须核对 GitHub API 的真实资产、大小与说明。

## 部署隔离

沿用 apps.timhuang.net 的 Nginx 与 HTTPS，单独为 `/ntfy-native/` 增加路径。ntfy-native 使用自己的 releases/current 链接，不切换整个 apps 站点的 current，不改 Local Transcribe 资源。发布前备份 apps 站点配置，`nginx -t` 成功后才 reload；不要重启服务。

颜色与设计约束见 DESIGN.md；检查矩阵见 design-tokens.json。开发预览 preview.html 不上线。
