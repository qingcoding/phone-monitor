import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 观看端信令客户端：连接采集端的 WebSocket 信令服务
class SignalingClient {
  WebSocketChannel? _channel;
  final StreamController<Map<String, dynamic>> incoming = StreamController.broadcast();
  final ValueNotifier<bool> connected = ValueNotifier(false);

  Future<void> connect(String url) async {
    final uri = Uri.parse(url);
    _channel = WebSocketChannel.connect(uri);
    connected.value = true;
    _channel!.stream.listen(
      (data) {
        try {
          final msg = jsonDecode(data as String) as Map<String, dynamic>;
          incoming.add(msg);
        } catch (_) {}
      },
      onDone: () => connected.value = false,
      onError: (_) => connected.value = false,
      cancelOnError: true,
    );
  }

  void send(Map<String, dynamic> msg) {
    _channel?.sink.add(jsonEncode(msg));
  }

  Future<void> disconnect() async {
    await _channel?.sink.close();
    _channel = null;
    connected.value = false;
  }

  void dispose() {
    disconnect();
    incoming.close();
    connected.dispose();
  }
}
