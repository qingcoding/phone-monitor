import 'dart:convert';
import 'dart:io';

/// 中继服务器配置：由 /api/config 下发 WebSocket 地址与 ICE 服务器（含 TURN 账号）
class RelayConfig {
  final String wsUrl;
  final String baseUrl;
  final List<Map<String, dynamic>> iceServers;

  RelayConfig({
    required this.wsUrl,
    required this.baseUrl,
    required this.iceServers,
  });

  /// 允许用户只填 IP/域名，自动补协议与去除末尾斜杠
  static String normalizeBase(String input) {
    var s = input.trim();
    if (s.isEmpty) throw const FormatException('请填写中继服务器地址');
    if (s.startsWith('ws://')) s = 'http://${s.substring(5)}';
    if (s.startsWith('wss://')) s = 'https://${s.substring(6)}';
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'http://$s';
    }
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  static Future<RelayConfig> fetch(
    String base, {
    String? room,
    String? role,
  }) async {
    final normalized = normalizeBase(base);
    var uri = Uri.parse('$normalized/api/config');
    if (room != null || role != null) {
      uri = uri.replace(queryParameters: {
        if (room != null) 'room': room,
        if (role != null) 'role': role,
      });
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(uri);
      final res = await req.close().timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        throw Exception('中继服务器返回 HTTP ${res.statusCode}');
      }
      final body = await utf8.decoder.bind(res).join();
      final map = jsonDecode(body) as Map<String, dynamic>;
      final ws = map['ws'] as String?;
      if (ws == null || ws.isEmpty) {
        throw const FormatException('服务器未返回 ws 地址');
      }
      final ice = (map['iceServers'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      return RelayConfig(wsUrl: ws, baseUrl: normalized, iceServers: ice);
    } finally {
      client.close(force: true);
    }
  }
}
