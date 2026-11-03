import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../services/relay_config.dart';
import 'viewer_page.dart';

class ViewerConnectPage extends StatefulWidget {
  const ViewerConnectPage({super.key});

  @override
  State<ViewerConnectPage> createState() => _ViewerConnectPageState();
}

class _ViewerConnectPageState extends State<ViewerConnectPage> {
  final TextEditingController _urlCtrl = TextEditingController();
  final TextEditingController _serverCtrl = TextEditingController();
  final TextEditingController _roomCtrl = TextEditingController();
  bool _scanning = false;
  bool _busy = false;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _serverCtrl.dispose();
    _roomCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect(String payload) async {
    String? url;
    String? relayBase;
    try {
      final map = jsonDecode(payload) as Map<String, dynamic>;
      url = map['url'] as String?;
      relayBase = map['relay'] as String?;
    } catch (_) {
      if (payload.startsWith('ws://') || payload.startsWith('wss://')) {
        url = payload;
      }
    }
    if (url == null || url.isEmpty) {
      _toast('无效的采集端地址');
      return;
    }
    final connectUrl = url;
    final state = context.read<AppState>();
    if (state.boundDevices.length >= state.maxDevices &&
        !state.boundDevices.contains(connectUrl)) {
      _toast('已达绑定上限（${state.maxDevices} 台），升级会员可绑定 5 台');
      return;
    }

    // 远程二维码：需要先从中继服务器取回 TURN 配置
    List<Map<String, dynamic>>? ice;
    if (relayBase != null && relayBase.isNotEmpty) {
      setState(() => _busy = true);
      try {
        ice = (await RelayConfig.fetch(relayBase)).iceServers;
      } catch (e) {
        if (mounted) {
          setState(() => _busy = false);
          _toast('无法获取中继配置：$e');
        }
        return;
      }
      if (!mounted) return;
      setState(() => _busy = false);
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ViewerPage(url: connectUrl, iceServers: ice),
      ),
    );
  }

  Future<void> _connectRemote() async {
    final server = _serverCtrl.text.trim();
    final room = _roomCtrl.text.trim().toUpperCase();
    if (server.isEmpty || room.isEmpty) {
      _toast('请填写中继服务器地址与房间号');
      return;
    }
    setState(() => _busy = true);
    try {
      final cfg = await RelayConfig.fetch(server);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ViewerPage(
            url: cfg.roomUrl(room, 'viewer'),
            iceServers: cfg.iceServers,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast('连接失败：$e');
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    if (_scanning) {
      return Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              final code = capture.barcodes.first.rawValue;
              if (code != null) {
                setState(() => _scanning = false);
                _connect(code);
              }
            },
          ),
          Positioned(
            top: 40,
            left: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => setState(() => _scanning = false),
            ),
          ),
          const Positioned(
            top: 48,
            left: 0,
            right: 0,
            child: Text(
              '将二维码对准框内',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16, decoration: TextDecoration.none),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('观看端 - 连接采集端')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '方式一：扫码连接',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '用本机扫描采集端屏幕上的二维码即可连接（需在同一 WiFi 下）。',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('打开扫码'),
              onPressed: () => setState(() => _scanning = true),
            ),
            const SizedBox(height: 32),
            const Text(
              '方式二：手动输入地址',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _urlCtrl,
              decoration: const InputDecoration(
                hintText: 'ws://192.168.1.10:8765/ws',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _connect(_urlCtrl.text.trim()),
              child: const Text('连接'),
            ),
            const SizedBox(height: 32),
            const Text(
              '方式三：外网远程（任意网络）',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '需自建中继服务器。填写服务器地址与采集端显示的房间号，'
              '即使不在同一 WiFi 也能观看。',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _serverCtrl,
              decoration: const InputDecoration(
                labelText: '中继服务器',
                hintText: 'http://1.2.3.4:8080',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _roomCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: '房间号',
                hintText: '例如 ABC123',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _busy ? null : _connectRemote,
              child: Text(_busy ? '连接中…' : '远程连接'),
            ),
          ],
        ),
      ),
    );
  }
}
