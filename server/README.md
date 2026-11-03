# phone-monitor relay server

旧手机监控的**外网中继服务**（Go）。一个进程同时提供：

1. **房间式 WebSocket 信令**：采集端与观看端在任意网络下交换 SDP/ICE
2. **TURN 中继**（[pion/turn](https://github.com/pion/turn)）：双方无法 P2P 直连时，媒体经服务器中转

> Demo 阶段使用固定 TURN 账号，仅适合自用测试；公网生产部署请改用短期凭证（见「上线前必做」）。

## 快速启动

```bash
cd server
go mod tidy
go build -o phone-monitor-server .

# 本机测试
TURN_PUBLIC_IP=127.0.0.1 ./phone-monitor-server

# 公网部署（把 1.2.3.4 换成服务器公网 IP）
TURN_PUBLIC_IP=1.2.3.4 TURN_USER=demo TURN_PASS=demo123 ./phone-monitor-server
```

需要放通的端口：

| 端口 | 协议 | 用途 |
|---|---|---|
| 8080 | TCP | HTTP + WebSocket 信令 |
| 3478 | UDP + TCP | TURN 中继 |

云服务器安全组需同时放行 UDP 3478，只开 TCP 会导致部分网络下中继失败。

## 配置项

| 环境变量 | 默认 | 说明 |
|---|---|---|
| `ADDR` | `:8080` | HTTP/WS 监听地址 |
| `TURN_PORT` | `3478` | TURN 监听端口 |
| `TURN_USER` / `TURN_PASS` | `demo` / `demo123` | TURN 静态账号 |
| `TURN_PUBLIC_IP` | 空 | TURN 对外 IP，跨 NAT 必须填公网 IP |
| `TURN_REALM` | `phone-monitor` | TURN realm |

也支持同名命令行参数，如 `-addr :8080`。

## 接口

```http
GET /healthz      # {"ok":true,...}
GET /api/config   # {"ws":"ws://host:8080/ws","iceServers":[...TURN...]}
GET /ws?room=ABC123&role=capture   # 采集端
GET /ws?room=ABC123&role=viewer    # 观看端
```

`/ws` 只转发 `{"type":"offer|answer|ice"}` 消息给房间对端，并推送 `{"type":"peer","event":"joined|left"}` 状态事件。同房间同角色只保留最新连接。

## 验证

```bash
curl -s http://127.0.0.1:8080/healthz
curl -s http://127.0.0.1:8080/api/config
```

信令联调（两个终端分别执行，需 Node 22+）：

```bash
node -e "
const c=new WebSocket('ws://127.0.0.1:8080/ws?room=TEST01&role=capture');
c.onopen=()=>c.send(JSON.stringify({type:'offer',sdp:'hi'}));
c.onmessage=e=>console.log('capture:',e.data);
"
```

## 上线前必做

- [ ] 固定账号改为 **TURN REST 短期凭证**（username 为 `时间戳:用户名`，password 用共享密钥 HMAC-SHA1 计算），防止账号被盗用跑流量
- [ ] 信令加房间令牌校验，避免陌生人猜房间号
- [ ] WS 走 TLS（`wss://`），APP 端把 `ws://` 换成 `wss://`
- [ ] 限制单 IP 并发与流量配额（`QuotaHandler`）
- [ ] 用 systemd / Docker 托管，开启日志轮转

## License

MIT，与主仓库一致。
