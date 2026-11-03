// phone-monitor relay server
//
// 一个进程同时提供两件事：
//  1. 房间式 WebSocket 信令转发：采集端与观看端在任意网络下都能交换 SDP/ICE
//  2. TURN 中继（基于 pion/turn）：双方无法 P2P 直连时，媒体经服务器中转
//
// 用法：
//
//	TURN_PUBLIC_IP=1.2.3.4 TURN_USER=demo TURN_PASS=demo123 go run .
//
// 对外接口：
//
//	GET /healthz     健康检查
//	GET /api/config  下发 ws 地址与 ICE 服务器（含 TURN 账号）
//	GET /ws          信令：?room=ABC123&role=capture|viewer
package main

import (
	"encoding/json"
	"flag"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/pion/turn/v4"
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
	mu     sync.Mutex
	peers  map[string]*peer // role -> peer
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
	turnUser := flag.String("turn-user", envOr("TURN_USER", "demo"), "TURN 用户名")
	turnPass := flag.String("turn-pass", envOr("TURN_PASS", "demo123"), "TURN 密码")
	publicIP := flag.String("turn-public-ip", envOr("TURN_PUBLIC_IP", ""), "TURN 对外 IP（跨 NAT 时必须填公网 IP）")
	realm := flag.String("realm", envOr("TURN_REALM", "phone-monitor"), "TURN realm")
	flag.Parse()

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

	turnSrv, err := turn.NewServer(turn.ServerConfig{
		Realm: *realm,
		AuthHandler: func(username, realm string, _ net.Addr) ([]byte, bool) {
			if username != *turnUser {
				return nil, false
			}
			return turn.GenerateAuthKey(username, realm, *turnPass), true
		},
		PacketConnConfigs: []turn.PacketConnConfig{
			{PacketConn: udpListener, RelayAddressGenerator: staticRelay(relayIP)},
		},
		ListenerConfigs: []turn.ListenerConfig{
			{Listener: tcpListener, RelayAddressGenerator: staticRelay(relayIP)},
		},
	})
	if err != nil {
		log.Fatalf("TURN 启动失败: %v", err)
	}
	defer turnSrv.Close()
	log.Printf("TURN 已启动: %s:%s (user=%s, realm=%s, relayIP=%s)", "0.0.0.0", *turnPort, *turnUser, *realm, relayIP)

	mux := http.NewServeMux()

	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{"ok": true, "time": time.Now().UTC()})
	})

	// 下发 ICE 配置，避免把 TURN 账号硬编码进 APP
	mux.HandleFunc("/api/config", func(w http.ResponseWriter, r *http.Request) {
		host := r.Host
		if h, _, err := net.SplitHostPort(host); err == nil {
			host = h
		}
		if *publicIP != "" {
			host = *publicIP
		}
		turnURL := "turn:" + net.JoinHostPort(host, *turnPort)
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Access-Control-Allow-Origin", "*")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"ws": "ws://" + net.JoinHostPort(host, portOf(*addr)) + "/ws",
			"iceServers": []map[string]any{
				{
					"urls": []string{
						turnURL + "?transport=udp",
						turnURL + "?transport=tcp",
					},
					"username":   *turnUser,
					"credential": *turnPass,
				},
				{"urls": "stun:" + net.JoinHostPort(host, *turnPort)},
			},
		})
	})

	mux.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		roomID := strings.ToUpper(strings.TrimSpace(r.URL.Query().Get("room")))
		role := r.URL.Query().Get("role")
		if roomID == "" || len(roomID) > 16 || (role != "capture" && role != "viewer") {
			http.Error(w, "room 与 role 参数不合法", http.StatusBadRequest)
			return
		}
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

	log.Printf("信令服务监听 %s", *addr)
	if err := http.ListenAndServe(*addr, mux); err != nil {
		log.Fatal(err)
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

func portOf(addr string) string {
	if _, p, err := net.SplitHostPort(addr); err == nil {
		return p
	}
	return "8080"
}
