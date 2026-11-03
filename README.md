
# 旧手机监控 · PhoneMonitor

把闲置手机改成一台家用监控摄像头：**免费、纯局域网、点对点直连**，视频流不经过任何服务器。

用一台旧 Android 手机当**采集端**（放摄像头），另一台手机或电脑浏览器当**观看端**（看画面）。两端在同一 WiFi 下即可，无需云服务、无需账号。

- 技术栈：Flutter 3.27 + WebRTC（`flutter_webrtc`）+ WebSocket 信令
- 协议：局域网 P2P（ICE/STUN 直连），画面点对点传输
- 平台：Android（iOS 工程已生成，需在 macOS 自行编译）
- 许可证：MIT

> ⚠️ 仅用于**自己拥有/有权监控**的场景（婴儿看护、宠物看护、居家安防、老人看护）。请勿用于侵犯他人隐私，使用前请告知同住人员。

---

## 特性

| 功能 | 状态 |
|---|---|
| 采集端 / 观看端双角色，扫码或手输地址连接 | ✅ |
| 实时视频（P2P，局域网内延迟通常 < 200ms） | ✅ |
| 双向音频、观看端对讲 | ✅ |
| 摄像头切换（前/后）、闪光灯 | ✅ |
| 本地录像（MP4 存手机） | ✅ |
| 防息屏 + 后台保活引导 | ✅ |
| 网页调试页：电脑浏览器直接看画面 | ✅ |
| 多观看端并发 | ⬜ 计划中（当前单连接） |
| 远程外网观看（TURN 中继） | ⬜ 计划中 |
| AI 哭声识别 / 移动侦测告警 | ⬜ 计划中 |

---

## 架构

```
┌────────────── 采集端（旧手机）──────────────┐
│  Camera ──▶ WebRTC PeerConnection           │
│              │  ▲                            │
│              │  └── 答案 / ICE               │
│         SignalingServer (HttpServer:8765)   │
│           ├─ /ws   ← WebSocket 信令          │
│           ├─ /      → 网页调试页（浏览器看） │
│           └─ /info  → 状态 JSON              │
└───────────────────▲─────────────────────────┘
                    │ 局域网直连（无中转）
┌───────────────────┴─────────────────────────┐
│ 观看端：APP 或电脑浏览器                     │
│  WebSocket ──▶ WebRTC PeerConnection ──▶ UI  │
└─────────────────────────────────────────────┘
```

信令消息（JSON，经 WebSocket 传输）：

```jsonc
{"type": "offer",  "sdp": "..."}                    // 观看端 → 采集端
{"type": "answer", "sdp": "..."}                    // 采集端 → 观看端
{"type": "ice",    "candidate": {...}}              // 双向
```

---

## 快速开始

### 环境

- Flutter 3.27+（stable）
- Android SDK 36 / Build-Tools 35 / JDK 17

```bash
flutter --version
```

### 构建

```bash
git clone <本仓库地址>
cd phone_monitor
flutter pub get
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

调试运行：

```bash
flutter run                 # 真机调试
flutter analyze             # 静态检查
```

> 发布到应用商店需自行配置签名（`android/key.properties` + keystore，已在 `.gitignore` 中排除）。

### 使用

1. 两台设备连**同一个 WiFi**（2.4G / 5G 都行，但需在同一网段，见「常见问题」）
2. 旧手机安装 APP → 选「采集端」→ 授予相机/麦克风权限 → 点击「开始采集」
3. 页面上出现二维码与地址 `ws://192.168.x.x:8765/ws`
4. 另一台手机选「观看端」→ 扫码（或手输地址）→ 看到实时画面
5. 电脑调试：浏览器打开 `http://192.168.x.x:8765/` 即可直接预览

---

## 网页调试页

采集端启动后，用**电脑浏览器**访问：

```
http://<手机IP>:8765/
```

- 自动握手并播放实时画面，断线 3 秒自动重连
- 支持浏览器端对讲（重新协商 SDP）
- `http://<手机IP>:8765/info` 返回 JSON 状态：`wsUrl`、`debugPage`、`viewerConnected`

注意：`ws://` 地址**不能**直接粘贴到浏览器地址栏（浏览器只认 `http/https`，会报 `ERR_UNKNOWN_URL_SCHEME`）。想看画面请访问上面的 `http://` 地址。

---

## 常见问题

**5G WiFi 连不上，2.4G 可以？**
不是 APP 问题。多数路由器对 5G 频段单独开了「AP 隔离 / 客户端隔离」，或 5G SSID 落在不同子网/VLAN，导致同 WiFi 设备二层不可达。排查：手机与电脑 IP 前三段是否一致，电脑 `ping 手机IP`；不通则进路由器后台关闭「无线隔离 / 客户端隔离」，并确认两个频段同属一个 LAN。

**telnet 连 8765 立刻断开？**
正常。该端口是 HTTP/WebSocket 服务，telnet 不发 HTTP 请求头，服务端判定非升级请求后写完响应即关闭。验证请用 `curl -i http://手机IP:8765/`。

**手机息屏后画面中断？**
需要允许后台运行：设置 → 应用 → 旧手机监控 → 电池「不限制」+ 允许自启动；APP 内「保活引导」页有各品牌步骤。

**画面对端打不开 / 黑屏？**
检查两端是否同网段、采集端页面是否在前台、是否只有一路观看端连接（当前版本单连接，后连的会覆盖先连的）。

**录像与 WebRTC 冲突？**
部分机型摄像头不支持被两路同时占用，录像失败时 APP 会提示；建议采集与录像分时使用。

---

## 项目结构

```
lib/
├── main.dart / app.dart          入口与路由
├── core/                         常量、主题、全局状态
├── features/
│   ├── role_selection/           角色选择
│   ├── capture/                  采集端页面
│   ├── viewer/                   观看端连接页 + 播放页
│   └── settings/                 设置、会员、保活引导
├── services/
│   ├── signaling_server.dart     信令服务（HTTP + WebSocket + 调试页）
│   ├── signaling_client.dart     WebSocket 客户端
│   ├── webrtc_service.dart       PeerConnection 封装
│   ├── local_recorder.dart       本地录像
│   ├── device_info.dart          本机 IP / 网络信息
│   └── permissions.dart          权限申请
assets/web/index.html             网页调试页（原生 WebRTC，无第三方依赖）
```

---

## 路线图

- [ ] 采集端支持多观看端并发（每客户端一个 PeerConnection）
- [ ] 可选 TURN 中继，实现外网远程观看
- [ ] 移动侦测 / 声音触发告警与推送
- [ ] 录像分段、循环覆盖、云端存储
- [ ] iOS 客户端（需 macOS 构建）
- [ ] 深色/浅色主题与多语言

欢迎 Issue / PR。

---

## 合规声明

本项目仅为技术工具，不提供任何云端存储或远程转发服务。使用者须自行确保：

1. 只监控自己拥有或已获授权的场所与设备；
2. 遵守当地关于隐私、监控与数据保护的法律法规；
3. 不对他人隐私空间进行拍摄或传播。

因不当使用产生的一切后果由使用者自行承担。

## License

[MIT](LICENSE)
