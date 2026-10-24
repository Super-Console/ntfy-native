# ntfy-native

A lightweight, native macOS menu bar client for [ntfy](https://ntfy.sh). Built with SwiftUI, AppKit, URLSession, and UserNotifications, with no third-party runtime dependencies.

## Features

- Subscribe to multiple ntfy topics at the same time, including topics on a self-hosted server. Each stream reconnects with backoff.
- Add an optional Note to each subscription. Topic names are not used as labels in the main menu panel or as fallback notification titles; a Note is used instead. Explicit message titles and message bodies are shown as received.
- Receive macOS notifications and view the latest 50 messages while the app is running.
- Publish a message to the first configured subscription.
- Store the server address, topics, and Notes in local preferences. An optional Bearer token is stored in the macOS Keychain. Subscriptions use the same configured server and token.
- Use the app in Simplified Chinese, English, French, German, or Spanish; the language follows the macOS preferred language.
- Keep the app in the menu bar without a Dock icon. The panel uses native macOS materials and adapts to the system version.
- Optionally launch at login through `SMAppService.mainApp`.

## Requirements

- macOS 13 or later
- Swift 6 or later
- Xcode Command Line Tools for building the app bundle

## Build and test

```sh
swift test
swift run ntfy-native
./scripts/build-app.sh
```

The app bundle is created at `dist/ntfy-native.app`. Pass a different `.app` path to `scripts/build-app.sh` to choose another output location.

`swift run ntfy-live-smoke` performs a live send/receive test using a randomly generated public topic by default. It publishes a test message. To use a self-hosted server and a topic you control:

```sh
swift run ntfy-live-smoke <server> <topic>
```

The development-only `scripts/ntfy-reconnect-proxy.py` can simulate a dropped stream and reconnect. It binds to localhost and forwards its test traffic to `ntfy.sh`.

## Distribution

GitHub releases currently provide an Apple silicon app bundle. The distributed app is ad-hoc signed and is not notarized; it is not signed with a Developer ID certificate. Building from source is also supported.

This is an independent client and is not affiliated with or endorsed by ntfy.

## Website

Product page: <https://apps.timhuang.net/ntfy-native/>. Its static site source is in [`site/`](site/).

## License

This project is available under the [MIT License](LICENSE).

---

# ntfy-native（简体中文）

一个轻量、原生的 macOS 菜单栏 ntfy 客户端。使用 SwiftUI、AppKit、URLSession 和 UserNotifications 构建，无第三方运行时依赖。

## 功能

- 可同时订阅多个 ntfy Topic，也支持自托管服务器；每个连接都会在中断后按退避策略重连。
- 每个订阅都可添加可选 Note。主面板和系统通知不会把 Topic 名称作为频道标签或无标题通知的回退标题；有 Note 时使用 Note。ntfy 消息自带的标题和正文仍按收到的内容显示。
- 接收 macOS 通知，并在应用运行期间查看最近 50 条消息。
- 向第一个已配置的订阅发布消息。
- 服务器地址、Topic 和 Note 保存在本机偏好设置中；可选 Bearer Token 保存在 macOS 钥匙串中。所有订阅共用当前配置的服务器和 Token。
- 支持简体中文、英文、法语、德语和西班牙语，界面语言跟随 macOS 首选语言。
- 常驻菜单栏且不显示 Dock 图标；面板使用原生 macOS 材质，并适配系统版本。
- 可通过 `SMAppService.mainApp` 选择是否登录时启动。

## 系统要求

- macOS 13 或更高版本
- Swift 6 或更高版本
- 构建 app bundle 需要 Xcode Command Line Tools

## 构建与测试

```sh
swift test
swift run ntfy-native
./scripts/build-app.sh
```

App bundle 默认生成到 `dist/ntfy-native.app`。也可以给 `scripts/build-app.sh` 传入其他 `.app` 路径作为输出位置。

运行 `swift run ntfy-live-smoke` 会默认使用随机生成的公开 Topic 进行真实收发测试，并发布一条测试消息。也可以指定自托管服务器和自己控制的 Topic：

```sh
swift run ntfy-live-smoke <server> <topic>
```

仅供开发测试的 `scripts/ntfy-reconnect-proxy.py` 可模拟连接中断和重连。它只监听本机，并将测试流量转发到 `ntfy.sh`。

## 分发说明

GitHub Releases 当前提供 Apple silicon 版 app bundle。分发包使用 ad-hoc 签名，尚未公证，也未使用 Developer ID 证书签名；同时支持从源码自行构建。

本项目是独立客户端，与 ntfy 官方无隶属或背书关系。

## 官网

产品页：<https://apps.timhuang.net/ntfy-native/>。静态网站源码位于 [`site/`](site/)。

## 许可证

本项目采用 [MIT 许可证](LICENSE)。
