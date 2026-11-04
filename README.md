
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
| 外网远程观看（自建 Go 中继 + TURN） | ✅ Demo |
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

## 外网访问（自建中继）

不在同一 WiFi 时，用 [`server/`](server/) 里的 Go 服务做信令 + TURN 中继：

```bash
cd server
go build -o phone-monitor-server .
export TURN_SECRET=$(openssl rand -hex 32) ROOM_SECRET=$(openssl rand -hex 32)
TURN_PUBLIC_IP=<服务器公网IP> ./phone-monitor-server   # 放通 8080/tcp 与 3478/udp+tcp
```

使用流程：

1. 采集端点底部「外网访问 → 开启」，填入 `http://<服务器IP>:8080`
2. 采集端会显示**房间号**，二维码同步变为远程二维码
3. 观看端扫码即可（自动换取观看端专属令牌）；也可在「方式三」里手填服务器地址 + 房间号
4. 双方无法 P2P 直连时，媒体自动走 TURN 中转

说明：

- 中继只是兜底，能直连时仍走 P2P，服务器不承载视频流量
- TURN 凭证 10 分钟过期、房间令牌 6 小时过期，均由服务端密钥签名，客户端无法伪造；详见 [server/README.md](server/README.md)
- 配置 `TLS_CERT` / `TLS_KEY` 即自动切换为 `https/wss` 与 `turns:`，APP 无需改动
- 默认按 IP 限流：`/api/config` 10 次突发、WS 握手 5 秒/次、单 IP 最多 3 条连接，超限返回 429
- 中继配额：默认最多 2 路并发、总带宽 3000 kbps、单路 1200 kbps，超限在分配阶段直接拒绝；`/stats` 可观测占用
- 公网部署必须设置 `TURN_PUBLIC_IP`，否则 TURN 只在本机/同网段可用
- 仍待完善：`/api/config` 发放令牌需登录鉴权（当前凭房间号即可换取）

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
server/                           外网中继（Go）：房间信令 + TURN
```

---

## 路线图

- [ ] 采集端支持多观看端并发（每客户端一个 PeerConnection）
- [ ] 中继生产化：wss、按 IP 限流、房间令牌发放加登录鉴权
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
