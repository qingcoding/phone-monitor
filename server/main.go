// phone-monitor relay server
//
// 一个进程同时提供两件事：
//  1. 房间式 WebSocket 信令转发：采集端与观看端在任意网络下都能交换 SDP/ICE
//  2. TURN 中继（基于 pion/turn）：双方无法 P2P 直连时，媒体经服务器中转
//
// 用法：
//
//	TURN_PUBLIC_IP=1.2.3.4 TURN_SECRET=<随机串> ROOM_SECRET=<随机串> go run .
//
// 对外接口：
//
//	GET /healthz     健康检查
//	GET /api/config?room=ABC123&role=capture  下发带令牌的 ws 地址与短期 TURN 凭证
//	GET /ws?room=ABC123&role=capture&token=... 信令房间
package main

import (
	"crypto/hmac"
	"crypto/sha1"
	"crypto/sha256"
	"crypto/tls"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/pion/turn/v4"
	"golang.org/x/time/rate"
)

type peer struct {
	conn *websocket.Conn
	mu   sync.Mutex
	role string
}

func (p *peer) send(v any) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.conn.WriteJSON(v)
}

type room struct {
	mu    sync.Mutex
	peers map[string]*peer // role -> peer
}

type hub struct {
	mu    sync.Mutex
	rooms map[string]*room
}

func newHub() *hub { return &hub{rooms: make(map[string]*room)} }

func (h *hub) join(roomID, role string, c *websocket.Conn) (*room, *peer, *peer) {
	h.mu.Lock()
	r, ok := h.rooms[roomID]
	if !ok {
		r = &room{peers: make(map[string]*peer)}
		h.rooms[roomID] = r
	}
	h.mu.Unlock()

	r.mu.Lock()
	defer r.mu.Unlock()
	old := r.peers[role]
	p := &peer{conn: c, role: role}
	r.peers[role] = p
	// 通知另一端
	other := r.peers[otherRole(role)]
	if other != nil {
		_ = other.send(map[string]any{"type": "peer", "event": "joined", "role": role})
	}
	return r, p, old
}

func (h *hub) count() int {
	h.mu.Lock()
	defer h.mu.Unlock()
	return len(h.rooms)
}

func (h *hub) leave(roomID string, p *peer) {
	h.mu.Lock()
	r, ok := h.rooms[roomID]
	h.mu.Unlock()
	if !ok {
		return
	}
	r.mu.Lock()
	if r.peers[p.role] == p {
		delete(r.peers, p.role)
	}
	other := r.peers[otherRole(p.role)]
	if other != nil {
		_ = other.send(map[string]any{"type": "peer", "event": "left", "role": p.role})
	}
	empty := len(r.peers) == 0
	r.mu.Unlock()

	if empty {
		h.mu.Lock()
		delete(h.rooms, roomID)
		h.mu.Unlock()
	}
}

func (r *room) forward(from *peer, msg map[string]any) {
	r.mu.Lock()
	to := r.peers[otherRole(from.role)]
	r.mu.Unlock()
	if to == nil {
		log.Printf("room forward: %s 的对端未在线，消息丢弃", from.role)
		return
	}
	if err := to.send(msg); err != nil {
		log.Printf("forward error: %v", err)
	}
}

func otherRole(role string) string {
	if role == "capture" {
		return "viewer"
	}
	return "capture"
}

var upgrader = websocket.Upgrader{
	CheckOrigin:     func(*http.Request) bool { return true },
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
}

func main() {
	addr := flag.String("addr", envOr("ADDR", ":8080"), "监听地址")
	turnPort := flag.String("turn-port", envOr("TURN_PORT", "3478"), "TURN 监听端口(UDP/TCP)")
	publicIP := flag.String("turn-public-ip", envOr("TURN_PUBLIC_IP", ""), "TURN 对外 IP（跨 NAT 时必须填公网 IP）")
	realm := flag.String("realm", envOr("TURN_REALM", "phone-monitor"), "TURN realm")
	turnSecret := flag.String("turn-secret", envOr("TURN_SECRET", "change-me-turn-secret"), "TURN REST 短期凭证的共享密钥")
	roomSecret := flag.String("room-secret", envOr("ROOM_SECRET", "change-me-room-secret"), "房间令牌签名密钥")
	turnTTL := flag.Int("turn-ttl", 600, "TURN 凭证有效期（秒）")
	roomTTL := flag.Int("room-ttl", 21600, "房间令牌有效期（秒）")
	tlsCert := flag.String("tls-cert", envOr("TLS_CERT", ""), "HTTPS/WSS 证书路径（.pem/.crt）")
	tlsKey := flag.String("tls-key", envOr("TLS_KEY", ""), "HTTPS/WSS 私钥路径")
	turnTLSPort := flag.String("turn-tls-port", envOr("TURN_TLS_PORT", "5349"), "TURN over TLS 端口（有证书时启用）")
	relayMax := flag.Int("relay-max-sessions", envOrInt("RELAY_MAX_SESSIONS", 2), "TURN 中继最大并发会话数")
	relayTotalKbps := flag.Float64("relay-total-kbps", envOrFloat("RELAY_TOTAL_KBPS", 3000), "TURN 中继总带宽上限（kbps）")
	relaySessionKbps := flag.Float64("relay-session-kbps", envOrFloat("RELAY_SESSION_KBPS", 1200), "单个中继会话带宽上限（kbps）")
	cfgRate := flag.Float64("cfg-rate", envOrFloat("CFG_RATE", 2), "/api/config 每 IP 每秒令牌数")
	cfgBurst := flag.Int("cfg-burst", envOrInt("CFG_BURST", 10), "/api/config 每 IP 突发上限")
	wsRate := flag.Float64("ws-rate", envOrFloat("WS_RATE", 0.2), "WS 握手每 IP 每秒令牌数")
	wsBurst := flag.Int("ws-burst", envOrInt("WS_BURST", 10), "WS 握手每 IP 突发上限")
	wsMaxPerIP := flag.Int("ws-max-per-ip", envOrInt("WS_MAX_PER_IP", 3), "每 IP 最大并发连接数")
	flag.Parse()

	if *turnSecret == "change-me-turn-secret" || *roomSecret == "change-me-room-secret" {
		log.Printf("警告：正在使用默认密钥，公网部署前请设置 TURN_SECRET / ROOM_SECRET")
	}
	ts := []byte(*turnSecret)
	rs := []byte(*roomSecret)

	useTLS := *tlsCert != "" && *tlsKey != ""
	if *tlsCert != "" != (*tlsKey != "") {
		log.Fatalf("TLS_CERT 与 TLS_KEY 必须同时提供")
	}
	var tlsConfig *tls.Config
	if useTLS {
		cert, err := tls.LoadX509KeyPair(*tlsCert, *tlsKey)
		if err != nil {
			log.Fatalf("加载 TLS 证书失败: %v", err)
		}
		tlsConfig = &tls.Config{
			Certificates: []tls.Certificate{cert},
			MinVersion:   tls.VersionTLS12,
		}
	}
	wsScheme := "ws"
	if useTLS {
		wsScheme = "wss"
	}

	// 限流器
	cfgLimiter := newIPLimiter(rate.Limit(*cfgRate), *cfgBurst)
	wsLimiter := newIPLimiter(rate.Limit(*wsRate), *wsBurst)
	wsGuard := newIPConcurrency(*wsMaxPerIP)
	go func() {
		for range time.Tick(2 * time.Minute) {
			cfgLimiter.prune(10 * time.Minute)
			wsLimiter.prune(10 * time.Minute)
		}
	}()

	h := newHub()

	// —— TURN ——
	udpListener, err := net.ListenPacket("udp4", ":"+*turnPort)
	if err != nil {
		log.Fatalf("TURN UDP 监听失败: %v", err)
	}
	tcpListener, err := net.Listen("tcp4", ":"+*turnPort)
	if err != nil {
		log.Fatalf("TURN TCP 监听失败: %v", err)
	}

	relayIP := net.ParseIP(*publicIP)
	if relayIP == nil {
		log.Printf("警告：未设置 TURN_PUBLIC_IP，TURN 只能用于本机/同网段测试")
		relayIP = net.ParseIP("127.0.0.1")
	}

	// 中继配额：并发会话 + 全局/单会话带宽（3Mbps 小水管必须限制）
	relayGen := newQuotaGenerator(
		staticRelay(relayIP),
		*relayMax,
		*relayTotalKbps,
		*relaySessionKbps,
	)
	log.Printf("中继配额：最多 %d 路并发，总带宽 %.0f kbps，单路 %.0f kbps",
		*relayMax, *relayTotalKbps, *relaySessionKbps)

	// TURN over TLS（有证书时启用，供限制 443/3478 的网络使用）
	listeners := []turn.ListenerConfig{
		{Listener: tcpListener, RelayAddressGenerator: relayGen},
	}
	if tlsConfig != nil {
		tlsListener, err := tls.Listen("tcp4", ":"+*turnTLSPort, tlsConfig)
		if err != nil {
			log.Fatalf("TURN TLS 监听失败: %v", err)
		}
		listeners = append(listeners, turn.ListenerConfig{
			Listener: tlsListener, RelayAddressGenerator: relayGen,
		})
		log.Printf("TURN over TLS 监听 :%s", *turnTLSPort)
	}

	turnSrv, err := turn.NewServer(turn.ServerConfig{
		Realm: *realm,
		// TURN REST 短期凭证：username = "<过期时间戳>:<标签>"，密码由共享密钥 HMAC-SHA1 派生
		AuthHandler: func(username, realm string, _ net.Addr) ([]byte, bool) {
			expStr, _, ok := strings.Cut(username, ":")
			if !ok {
				return nil, false
			}
			exp, err := strconv.ParseInt(expStr, 10, 64)
			if err != nil || time.Now().Unix() > exp {
				log.Printf("TURN 拒绝过期/非法凭证: %q", username)
				return nil, false
			}
			return turn.GenerateAuthKey(username, realm, restCredential(ts, username)), true
		},
		PacketConnConfigs: []turn.PacketConnConfig{
			{PacketConn: udpListener, RelayAddressGenerator: relayGen},
		},
		ListenerConfigs: listeners,
	})
	if err != nil {
		log.Fatalf("TURN 启动失败: %v", err)
	}
	defer turnSrv.Close()
	log.Printf("TURN 已启动: :%s (realm=%s, relayIP=%s, 凭证有效期=%ds)", *turnPort, *realm, relayIP, *turnTTL)

	mux := http.NewServeMux()

	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{"ok": true, "time": time.Now().UTC()})
	})

	// 运行状态：中继占用与房间数，便于运维观察 3Mbps 是否打满
	mux.HandleFunc("/stats", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"relay": relayGen.snapshot(),
			"rooms": h.count(),
		})
	})

	// 下发短期 TURN 凭证与带令牌的 ws 地址
	mux.HandleFunc("/api/config", func(w http.ResponseWriter, r *http.Request) {
		if !cfgLimiter.allow(clientIP(r)) {
			w.Header().Set("Retry-After", "3")
			http.Error(w, "请求过于频繁", http.StatusTooManyRequests)
			return
		}
		host := r.Host
		if h, _, err := net.SplitHostPort(host); err == nil {
			host = h
		}
		if *publicIP != "" {
			host = *publicIP
		}
		wsBase := wsScheme + "://" + net.JoinHostPort(host, portOf(*addr)) + "/ws"
		turnURL := "turn:" + net.JoinHostPort(host, *turnPort)

		room := strings.ToUpper(strings.TrimSpace(r.URL.Query().Get("room")))
		role := r.URL.Query().Get("role")

		ice := []map[string]any{}
		var wsURL string

		if room != "" || role != "" {
			if !validRoom(room) || (role != "capture" && role != "viewer") {
				http.Error(w, "room 与 role 参数不合法", http.StatusBadRequest)
				return
			}
			token := signRoom(rs, room, role, time.Now().Add(time.Duration(*roomTTL)*time.Second).Unix())
			wsURL = fmt.Sprintf("%s?room=%s&role=%s&token=%s", wsBase, room, role, token)
		} else {
			wsURL = wsBase
		}

		// TURN REST 凭证：username="过期时间戳:标签"，credential=base64(HMAC-SHA1(secret, username))
		exp := time.Now().Add(time.Duration(*turnTTL) * time.Second).Unix()
		turnUser := fmt.Sprintf("%d:phone-monitor", exp)
		turnURLs := []string{
			turnURL + "?transport=udp",
			turnURL + "?transport=tcp",
		}
		if tlsConfig != nil {
			turnURLs = append(turnURLs,
				"turns:"+net.JoinHostPort(host, *turnTLSPort)+"?transport=tcp")
		}
		ice = append(ice, map[string]any{
			"urls":       turnURLs,
			"username":   turnUser,
			"credential": restCredential(ts, turnUser),
		}, map[string]any{"urls": "stun:" + net.JoinHostPort(host, *turnPort)})

		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Access-Control-Allow-Origin", "*")
		log.Printf("/api/config room=%q role=%q → 已签发 TURN 凭证(exp=%d)", room, role, exp)
		_ = json.NewEncoder(w).Encode(map[string]any{
			"ws":         wsURL,
			"iceServers": ice,
			"turnExpiry": exp,
		})
	})

	mux.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		roomID := strings.ToUpper(strings.TrimSpace(r.URL.Query().Get("room")))
		role := r.URL.Query().Get("role")
		token := r.URL.Query().Get("token")
		if !validRoom(roomID) || (role != "capture" && role != "viewer") {
			http.Error(w, "room 与 role 参数不合法", http.StatusBadRequest)
			return
		}
		if !verifyRoom(rs, roomID, role, token) {
			log.Printf("拒绝无效房间令牌 room=%s role=%s", roomID, role)
			http.Error(w, "房间令牌无效或已过期", http.StatusUnauthorized)
			return
		}
		ip := clientIP(r)
		if !wsLimiter.allow(ip) {
			log.Printf("限流：%s 握手过于频繁", ip)
			w.Header().Set("Retry-After", "5")
			http.Error(w, "握手过于频繁", http.StatusTooManyRequests)
			return
		}
		if !wsGuard.acquire(ip) {
			log.Printf("限流：%s 并发连接数超限", ip)
			http.Error(w, "并发连接数超限", http.StatusTooManyRequests)
			return
		}
		defer wsGuard.release(ip)
		c, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			log.Printf("upgrade error: %v", err)
			return
		}
		r_, p, old := h.join(roomID, role, c)
		if old != nil {
			_ = old.conn.Close()
			log.Printf("room=%s role=%s 被新连接替换", roomID, role)
		}
		log.Printf("room=%s role=%s 已加入", roomID, role)

		defer func() {
			h.leave(roomID, p)
			_ = c.Close()
			log.Printf("room=%s role=%s 已离开", roomID, role)
		}()

		for {
			_, data, err := c.ReadMessage()
			if err != nil {
				return
			}
			var msg map[string]any
			if err := json.Unmarshal(data, &msg); err != nil {
				continue
			}
			switch msg["type"] {
			case "offer", "answer", "ice":
				r_.forward(p, msg)
			case "ping":
				_ = p.send(map[string]any{"type": "pong"})
			}
		}
	})

	srv := &http.Server{
		Addr:              *addr,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
		TLSConfig:         tlsConfig,
	}
	if useTLS {
		log.Printf("信令服务监听 %s（HTTPS/WSS，%s）", *addr, *tlsCert)
		if err := srv.ListenAndServeTLS(*tlsCert, *tlsKey); err != nil {
			log.Fatal(err)
		}
	} else {
		log.Printf("信令服务监听 %s（HTTP/WS，未启用 TLS）", *addr)
		if err := srv.ListenAndServe(); err != nil {
			log.Fatal(err)
		}
	}
}

func staticRelay(ip net.IP) turn.RelayAddressGenerator {
	return &turn.RelayAddressGeneratorStatic{
		RelayAddress: ip,
		Address:      "0.0.0.0",
	}
}

func envOr(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func envOrInt(k string, def int) int {
	if v := os.Getenv(k); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}

func envOrFloat(k string, def float64) float64 {
	if v := os.Getenv(k); v != "" {
		if f, err := strconv.ParseFloat(v, 64); err == nil {
			return f
		}
	}
	return def
}

func portOf(addr string) string {
	if _, p, err := net.SplitHostPort(addr); err == nil {
		return p
	}
	return "8080"
}

// TURN REST 凭证：password = base64(HMAC-SHA1(secret, username))
func restCredential(secret []byte, username string) string {
	mac := hmac.New(sha1.New, secret)
	mac.Write([]byte(username))
	return base64.StdEncoding.EncodeToString(mac.Sum(nil))
}

func validRoom(room string) bool {
	if len(room) < 4 || len(room) > 16 {
		return false
	}
	for _, c := range room {
		if (c < 'A' || c > 'Z') && (c < '0' || c > '9') {
			return false
		}
	}
	return true
}

// 房间令牌：<过期时间戳>.<hex(HMAC-SHA256(secret, room:role:exp))>
func signRoom(secret []byte, room, role string, exp int64) string {
	mac := hmac.New(sha256.New, secret)
	fmt.Fprintf(mac, "%s:%s:%d", room, role, exp)
	return strconv.FormatInt(exp, 10) + "." + hex.EncodeToString(mac.Sum(nil))
}

func verifyRoom(secret []byte, room, role, token string) bool {
	expStr, sig, ok := strings.Cut(token, ".")
	if !ok {
		return false
	}
	exp, err := strconv.ParseInt(expStr, 10, 64)
	if err != nil || time.Now().Unix() > exp {
		return false
	}
	want := hmac.New(sha256.New, secret)
	fmt.Fprintf(want, "%s:%s:%d", room, role, exp)
	got, err := hex.DecodeString(sig)
	if err != nil {
		return false
	}
	return hmac.Equal(want.Sum(nil), got)
}
