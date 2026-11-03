import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 采集端信令服务器：在本机开启 WebSocket，观看端扫码后直连交换 SDP/ICE。
/// 免费版纯局域网 P2P，服务器不转发视频流。
/// 同时提供网页调试页 http://手机IP:端口/ ，电脑浏览器可直接看实时画面。
class SignalingServer {
  HttpServer? _server;
  WebSocket? _client;
  final int _port;
  String? _debugPage;
  String? _localIp;

  final StreamController<Map<String, dynamic>> incoming = StreamController.broadcast();
  final ValueNotifier<bool> running = ValueNotifier(false);
  final ValueNotifier<bool> viewerConnected = ValueNotifier(false);

  SignalingServer({int port = 8765}) : _port = port;

  int get port => _port;

  /// 网页调试地址（电脑浏览器打开）
  String get debugPageUrl => 'http://${_localIp ?? '127.0.0.1'}:$_port/';

  /// 启动信令服务，返回实际监听地址
  Future<String?> start() async {
    if (_server != null) return null;
    try {
      _localIp = await _getLocalIp();
      _debugPage = await rootBundle.loadString('assets/web/index.html');
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
      running.value = true;
      _server!.listen((req) {
        if (req.uri.path == '/ws' || WebSocketTransformer.isUpgradeRequest(req)) {
          WebSocketTransformer.upgrade(req).then((ws) {
            _client = ws;
            viewerConnected.value = true;
            ws.listen(
              (data) {
                try {
                  final msg = jsonDecode(data as String) as Map<String, dynamic>;
                  incoming.add(msg);
                } catch (_) {}
              },
              onDone: () {
                viewerConnected.value = false;
                if (_client == ws) _client = null;
              },
              onError: (_) {
                viewerConnected.value = false;
              },
              cancelOnError: true,
            );
          });
        } else {
          _handleHttp(req);
        }
      });
      return 'ws://$_localIp:$_port/ws';
    } catch (e) {
      debugPrint('SignalingServer start error: $e');
      return null;
    }
  }

  /// 普通 HTTP 请求：/ 返回网页调试页，/info 返回状态 JSON
  void _handleHttp(HttpRequest req) {
    final path = req.uri.path;
    final res = req.response..headers.set('Cache-Control', 'no-store');

    if (path == '/' || path == '/index.html') {
      res
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write(_debugPage ?? '<h1>调试页未加载</h1>');
    } else if (path == '/info') {
      res
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'app': 'PhoneMonitor',
          'wsUrl': 'ws://${_localIp ?? '127.0.0.1'}:$_port/ws',
          'debugPage': debugPageUrl,
          'viewerConnected': viewerConnected.value,
        }));
    } else {
      res
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.text
        ..write('PhoneMonitor Signaling Server OK\n调试页: $debugPageUrl');
    }
    res.close();
  }

  Future<String> _getLocalIp() async {
    final interfaces = await NetworkInterface.list();
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (addr.type.name == 'IPv4' && !addr.isLoopback) {
          return addr.address;
        }
      }
    }
    return '127.0.0.1';
  }

  /// 向观看端发送信令消息
  void send(Map<String, dynamic> msg) {
    _client?.add(jsonEncode(msg));
  }

  Future<void> stop() async {
    await _client?.close();
    _client = null;
    viewerConnected.value = false;
    await _server?.close(force: true);
    _server = null;
    running.value = false;
  }

  void dispose() {
    stop();
    incoming.close();
    running.dispose();
    viewerConnected.dispose();
  }
}
