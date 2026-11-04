package main

import (
	"context"
	"fmt"
	"log"
	"net"
	"sync"

	"github.com/pion/turn/v4"
	"golang.org/x/time/rate"
)

// quotaGenerator 在分配中继地址时做两件事：
//  1. 并发会话配额（信号量）：超过上限直接拒绝分配，客户端收到分配失败
//  2. 出向带宽整形：全局 + 单会话双重令牌桶，防止一条流打满服务器带宽
//
// 只对 WriteTo/Write（发往客户端的方向）限速，因为该方向最耗上行带宽。
type quotaGenerator struct {
	inner      turn.RelayAddressGenerator
	slots      chan struct{}
	global     *rate.Limiter
	sessionBps int
	mu         sync.Mutex
	active     int
	rejected   int
	maxSlots   int
}

func newQuotaGenerator(inner turn.RelayAddressGenerator, maxSessions int, totalKbps, sessionKbps float64) *quotaGenerator {
	if maxSessions < 1 {
		maxSessions = 1
	}
	burst := int(totalKbps * 1000 / 8) // 1 秒带宽作为突发
	if burst < 1 {
		burst = 1
	}
	return &quotaGenerator{
		inner:      inner,
		slots:      make(chan struct{}, maxSessions),
		global:     rate.NewLimiter(rate.Limit(totalKbps*1000/8), burst),
		sessionBps: int(sessionKbps * 1000 / 8),
		maxSlots:   maxSessions,
	}
}

func (g *quotaGenerator) Validate() error { return g.inner.Validate() }

func (g *quotaGenerator) AllocatePacketConn(network string, requestedPort int) (net.PacketConn, net.Addr, error) {
	if err := g.acquire(); err != nil {
		return nil, nil, err
	}
	pc, addr, err := g.inner.AllocatePacketConn(network, requestedPort)
	if err != nil {
		g.release()
		return nil, nil, err
	}
	return &quotaPacketConn{
		PacketConn: pc,
		global:     g.global,
		writer:     g.sessionLimiter(),
		onClose:    g.release,
	}, addr, nil
}

func (g *quotaGenerator) AllocateConn(network string, requestedPort int) (net.Conn, net.Addr, error) {
	if err := g.acquire(); err != nil {
		return nil, nil, err
	}
	c, addr, err := g.inner.AllocateConn(network, requestedPort)
	if err != nil {
		g.release()
		return nil, nil, err
	}
	return &quotaConn{
		Conn:    c,
		global:  g.global,
		writer:  g.sessionLimiter(),
		onClose: g.release,
	}, addr, nil
}

func (g *quotaGenerator) acquire() error {
	select {
	case g.slots <- struct{}{}:
		g.mu.Lock()
		g.active++
		active, max := g.active, g.maxSlots
		g.mu.Unlock()
		log.Printf("TURN 分配中继会话：%d/%d", active, max)
		return nil
	default:
		g.mu.Lock()
		g.rejected++
		g.mu.Unlock()
		log.Printf("TURN 拒绝分配：并发会话已达上限 %d", g.maxSlots)
		return fmt.Errorf("relay quota exhausted (max %d sessions)", g.maxSlots)
	}
}

func (g *quotaGenerator) release() {
	select {
	case <-g.slots:
		g.mu.Lock()
		g.active--
		active := g.active
		g.mu.Unlock()
		log.Printf("TURN 释放中继会话：剩余 %d", active)
	default:
	}
}

func (g *quotaGenerator) sessionLimiter() *rate.Limiter {
	burst := g.sessionBps
	if burst < 1 {
		burst = 1
	}
	return rate.NewLimiter(rate.Limit(g.sessionBps), burst)
}

func (g *quotaGenerator) snapshot() map[string]any {
	g.mu.Lock()
	defer g.mu.Unlock()
	return map[string]any{
		"active":   g.active,
		"max":      g.maxSlots,
		"rejected": g.rejected,
	}
}

type quotaPacketConn struct {
	net.PacketConn
	global  *rate.Limiter
	writer  *rate.Limiter
	onClose func()
	once    sync.Once
}

func (c *quotaPacketConn) WriteTo(b []byte, addr net.Addr) (int, error) {
	waitBytes(c.global, len(b))
	waitBytes(c.writer, len(b))
	return c.PacketConn.WriteTo(b, addr)
}

func (c *quotaPacketConn) Close() error {
	c.once.Do(c.onClose)
	return c.PacketConn.Close()
}

type quotaConn struct {
	net.Conn
	global  *rate.Limiter
	writer  *rate.Limiter
	onClose func()
	once    sync.Once
}

func (c *quotaConn) Write(b []byte) (int, error) {
	waitBytes(c.global, len(b))
	waitBytes(c.writer, len(b))
	return c.Conn.Write(b)
}

func (c *quotaConn) Close() error {
	c.once.Do(c.onClose)
	return c.Conn.Close()
}

// waitBytes 按字节数等待令牌；超过突发量时按突发量计，避免 WaitN 直接报错
func waitBytes(l *rate.Limiter, n int) {
	if l == nil || n <= 0 {
		return
	}
	if b := l.Burst(); n > b {
		n = b
	}
	_ = l.WaitN(context.Background(), n)
}
