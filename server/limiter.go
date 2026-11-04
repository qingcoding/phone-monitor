package main

import (
	"net"
	"net/http"
	"sync"
	"time"

	"golang.org/x/time/rate"
)

// clientIP 取直连对端地址；如部署在反向代理后请勿轻信 X-Forwarded-For，
// 需要时再按可信代理配置开启。
func clientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// ipLimiter 按 IP 做令牌桶限流
type ipLimiter struct {
	mu      sync.Mutex
	limit   rate.Limit
	burst   int
	buckets map[string]*ipBucket
}

type ipBucket struct {
	lim  *rate.Limiter
	seen time.Time
}

func newIPLimiter(limit rate.Limit, burst int) *ipLimiter {
	return &ipLimiter{
		limit:   limit,
		burst:   burst,
		buckets: make(map[string]*ipBucket),
	}
}

func (l *ipLimiter) allow(ip string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	b, ok := l.buckets[ip]
	if !ok {
		b = &ipBucket{lim: rate.NewLimiter(l.limit, l.burst)}
		l.buckets[ip] = b
	}
	b.seen = time.Now()
	return b.lim.Allow()
}

// prune 清理长时间不活跃的 IP，避免内存无限增长
func (l *ipLimiter) prune(idle time.Duration) {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := time.Now()
	for ip, b := range l.buckets {
		if now.Sub(b.seen) > idle {
			delete(l.buckets, ip)
		}
	}
}

// ipConcurrency 限制每 IP 的并发 WebSocket 连接数
type ipConcurrency struct {
	mu    sync.Mutex
	max   int
	count map[string]int
}

func newIPConcurrency(max int) *ipConcurrency {
	return &ipConcurrency{max: max, count: make(map[string]int)}
}

func (c *ipConcurrency) acquire(ip string) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.count[ip] >= c.max {
		return false
	}
	c.count[ip]++
	return true
}

func (c *ipConcurrency) release(ip string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if n, ok := c.count[ip]; ok {
		if n <= 1 {
			delete(c.count, ip)
		} else {
			c.count[ip] = n - 1
		}
	}
}
