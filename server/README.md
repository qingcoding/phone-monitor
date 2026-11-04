# phone-monitor relay server

旧手机监控的**外网中继服务**（Go）。一个进程同时提供：

1. **房间式 WebSocket 信令**：采集端与观看端在任意网络下交换 SDP/ICE
2. **TURN 中继**（[pion/turn](https://github.com/pion/turn)）：双方无法 P2P 直连时，媒体经服务器中转

> 已实现**短期 TURN 凭证**（REST 方式）与**房间令牌**：凭证/令牌带过期时间且由密钥签名，客户端无法伪造，泄露的凭证 10 分钟后自动失效。

## 快速启动

```bash
cd server
go mod tidy
go build -o phone-monitor-server .

# 生成两个随机密钥（务必替换默认值）
export TURN_SECRET=$(openssl rand -hex 32)
export ROOM_SECRET=$(openssl rand -hex 32)

# 本机测试
TURN_PUBLIC_IP=127.0.0.1 ./phone-monitor-server

# 公网部署（把 1.2.3.4 换成服务器公网 IP）
TURN_PUBLIC_IP=1.2.3.4 ./phone-monitor-server
```

需要放通的端口：

| 端口 | 协议 | 用途 |
|---|---|---|
| 8080 | TCP | HTTP + WebSocket 信令 |
| 8443 | TCP | HTTPS + WSS（启用 TLS 后） |
| 3478 | UDP + TCP | TURN 中继 |
| 5349 | TCP | TURN over TLS（启用 TLS 后） |

云服务器安全组需同时放行 UDP 3478，只开 TCP 会导致部分网络下中继失败。

## 启用 TLS（wss + turns）

```bash
# 用 Let's Encrypt 证书（推荐）
sudo certbot certonly --standalone -d monitor.example.com
TLS_CERT=/etc/letsencrypt/live/monitor.example.com/fullchain.pem \
TLS_KEY=/etc/letsencrypt/live/monitor.example.com/privkey.pem \
TURN_PUBLIC_IP=1.2.3.4 \
./phone-monitor-server -addr :443
```

启用后 `/api/config` 自动改为下发：

- `wss://<host>:<端口>/ws?...` 信令地址
- `turns:<host>:5349?transport=tcp` 中继地址（同时保留 `turn:` 3478）

APP 端无需改动：它按服务器下发的协议自动切换。注意自签证书在 APP 内会校验失败（这是预期行为），请使用受信任证书。

## 限流

所有限制按**客户端 IP** 计数，超限返回 `429` 并带 `Retry-After`：

| 配置 | 默认 | 说明 |
|---|---|---|
| `CFG_RATE` / `CFG_BURST` | `2` / `10` | `/api/config` 每秒令牌数 / 突发上限 |
| `WS_RATE` / `WS_BURST` | `0.2` / `10` | WS 握手每秒令牌数 / 突发上限（约 5 秒 1 次持续） |
| `WS_MAX_PER_IP` | `3` | 单 IP 最大并发 WS 连接数 |

限流表每 2 分钟清理一次闲置 IP，避免内存增长。用反向代理时 `RemoteAddr` 是代理 IP，需按可信代理配置改写取真实 IP（当前未实现）。

## 中继配额（3Mbps 小带宽必读）

TURN 转发是**纯额外流量**：一路 720p 约 1.5~2 Mbps，3Mbps 服务器最多只能承载 1~2 路。配额在分配阶段硬性拒绝，避免第三路连上后把所有人拖慢。

| 配置 | 默认 | 作用 |
|---|---|---|
| `RELAY_MAX_SESSIONS` | `2` | 全局最大并发中继会话，超限分配失败（客户端回落失败/无法连接） |
| `RELAY_TOTAL_KBPS` | `3000` | 全局出向带宽上限（kbps），令牌桶整形 |
| `RELAY_SESSION_KBPS` | `1200` | 单会话出向带宽上限（kbps） |

默认值按「3Mbps 总带宽、单路 720p」给出，留约 0.6Mbps 余量给信令与重传。若只看 480p，可把 `RELAY_SESSION_KBPS` 调到 `800`，`RELAY_MAX_SESSIONS` 提到 `3`。

实现方式：包装 `RelayAddressGenerator`，分配时占用信号量，关闭时释放；对转发 socket 的 `WriteTo`/`Write` 施加令牌桶（全局 + 单会话双重）。带宽限速作用于**服务器 → 客户端**方向。

运维观察：

```bash
curl -s http://127.0.0.1:8080/stats
# {"relay":{"active":1,"max":2,"rejected":3},"rooms":2}
```

`rejected` 持续增长说明配额或带宽不足，需要扩容或降低码率。

> 2 核 4G 参考：单进程可稳定支撑 4~6 路转发；瓶颈通常先出现在带宽而非 CPU。若开 TLS，握手与加解密约占单核 10%~15%/路。

## 配置项

| 环境变量 | 默认 | 说明 |
|---|---|---|
| `ADDR` | `:8080` | HTTP/WS 监听地址 |
| `TURN_PORT` | `3478` | TURN 监听端口 |
| `TURN_TLS_PORT` | `5349` | TURN over TLS 端口 |
| `TLS_CERT` / `TLS_KEY` | 空 | 同时提供才启用 HTTPS/WSS/TURNS |
| `TURN_SECRET` | 默认占位值 | TURN REST 凭证密钥，**生产必须改** |
| `ROOM_SECRET` | 默认占位值 | 房间令牌签名密钥，**生产必须改** |
| `TURN_TTL` | `600` | TURN 凭证有效期（秒） |
| `ROOM_TTL` | `21600` | 房间令牌有效期（秒） |
| `TURN_PUBLIC_IP` | 空 | TURN 对外 IP，跨 NAT 必须填公网 IP |
| `TURN_REALM` | `phone-monitor` | TURN realm |
| `RELAY_MAX_SESSIONS` | `2` | 最大并发中继会话 |
| `RELAY_TOTAL_KBPS` | `3000` | 中继总带宽上限（kbps） |
| `RELAY_SESSION_KBPS` | `1200` | 单会话带宽上限（kbps） |

也支持同名命令行参数，如 `-addr :8080`、`-ws-rate 0.5`。

## 鉴权机制

**TURN REST 短期凭证**（与 coturn 兼容）：

```
username   = "<过期时间戳>:phone-monitor"
credential = base64(HMAC-SHA1(TURN_SECRET, username))
```

服务器在 Allocate 时解析过期时间并重算密钥比对，过期即拒绝。客户端每 10 分钟重新拉取即可。

**房间令牌**：

```
token = "<过期时间戳>.<hex(HMAC-SHA256(ROOM_SECRET, room:role:exp))>"
```

`/ws` 校验 room、role、过期时间与签名，三者任一不匹配即 `401`。令牌绑定角色，观看端令牌不能用于采集端连接。

## 接口

```http
GET /healthz                                # {"ok":true,...}
GET /stats                                  # 中继占用/拒绝数、房间数
GET /api/config                             # ws 地址 + STUN（无房间时）
GET /api/config?room=ABC123&role=capture    # 带令牌的 ws + 短期 TURN 凭证
GET /ws?room=ABC123&role=capture&token=...  # 采集端
GET /ws?room=ABC123&role=viewer&token=...   # 观看端
```

`/ws` 只转发 `{"type":"offer|answer|ice"}` 消息给房间对端，并推送 `{"type":"peer","event":"joined|left"}` 状态事件。同房间同角色只保留最新连接。

## 验证

```bash
curl -s http://127.0.0.1:8080/healthz
curl -s "http://127.0.0.1:8080/api/config?room=TEST01&role=capture"
```

信令联调（先取回带令牌的 ws 地址，无令牌会被拒绝）：

```bash
WS=$(curl -s "http://127.0.0.1:8080/api/config?room=TEST01&role=capture" | python3 -c "import sys,json;print(json.load(sys.stdin)['ws'])")
node -e "
const c=new WebSocket(process.env.WS);
c.onopen=()=>c.send(JSON.stringify({type:'offer',sdp:'hi'}));
c.onmessage=e=>console.log('capture:',e.data);
" 
```

## 上线前必做

- [x] TURN REST 短期凭证（`TURN_SECRET` 签名，10 分钟过期）
- [x] 房间令牌校验（`ROOM_SECRET` 签名，绑定 room + role）
- [x] WS 走 TLS（`wss://` 与 `turns:`，同一套证书）
- [x] 按 IP 限流与并发上限（`CFG_RATE` / `WS_RATE` / `WS_MAX_PER_IP`）
- [x] TURN 配额：并发会话 + 全局/单会话带宽整形（`RELAY_*`）
- [ ] 反向代理场景下取真实 IP（`X-Forwarded-For` 可信代理白名单）
- [ ] 按 IP 的中继会话配额（当前为全局上限）
- [ ] 用 systemd / Docker 托管，开启日志轮转
- [ ] 拆分 `/api/config` 为需登录的接口，避免房间令牌被任意人换取

## License

MIT，与主仓库一致。
