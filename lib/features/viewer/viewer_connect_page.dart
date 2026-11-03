import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import 'viewer_page.dart';

class ViewerConnectPage extends StatefulWidget {
  const ViewerConnectPage({super.key});

  @override
  State<ViewerConnectPage> createState() => _ViewerConnectPageState();
}

class _ViewerConnectPageState extends State<ViewerConnectPage> {
  final TextEditingController _urlCtrl = TextEditingController();
  bool _scanning = false;

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  void _connect(String payload) {
    String? url;
    try {
      final map = jsonDecode(payload) as Map<String, dynamic>;
      url = map['url'] as String?;
    } catch (_) {
      if (payload.startsWith('ws://') || payload.startsWith('wss://')) {
        url = payload;
      }
    }
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无效的采集端地址')),
      );
      return;
    }
    final connectUrl = url;
    final state = context.read<AppState>();
    if (state.boundDevices.length >= state.maxDevices &&
        !state.boundDevices.contains(connectUrl)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已达绑定上限（${state.maxDevices} 台），升级会员可绑定 5 台')),
      );
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ViewerPage(url: connectUrl)),
    );
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
      body: Padding(
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
          ],
        ),
      ),
    );
  }
}
