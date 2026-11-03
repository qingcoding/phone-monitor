import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/app_state.dart';
import '../../core/constants.dart';
import '../../services/device_info.dart';
import '../../services/local_recorder.dart';
import '../../services/permissions.dart';
import '../../services/signaling_server.dart';
import '../../services/webrtc_service.dart';

class CapturePage extends StatefulWidget {
  const CapturePage({super.key});

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  final WebRtcService _rtc = WebRtcService();
  final SignalingServer _signaling = SignalingServer(port: AppConstants.signalingPort);
  final LocalRecorder _recorder = LocalRecorder();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();

  StreamController<Map<String, dynamic>>? _outgoing;

  String? _wsUrl;
  String? _deviceId;
  bool _ready = false;
  bool _recording = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _localRenderer.initialize();
    final ok = await Permissions.requestCapture();
    if (!ok) {
      setState(() => _error = '未授予相机/麦克风权限，无法作为采集端使用。');
      return;
    }
    try {
      _outgoing = StreamController<Map<String, dynamic>>.broadcast();
      _rtc.setOutgoingSignaling(_outgoing!);
      _outgoing!.stream.listen((msg) => _signaling.send(msg));
      _signaling.incoming.stream.listen((msg) => _rtc.handleMessage(msg));

      _rtc.localStream.addListener(() {
        final s = _rtc.localStream.value;
        if (s != null) {
          _localRenderer.srcObject = s;
        }
      });

      await _rtc.startCapture(audio: true, video: true);

      final url = await _signaling.start();
      _wsUrl = url;
      _deviceId = await DeviceInfo.deviceId();
      setState(() => _ready = true);
      unawaited(WakelockPlus.enable());
    } catch (e) {
      setState(() => _error = '启动失败：$e');
    }
  }

  String get _qrData {
    final payload = {
      'url': _wsUrl ?? '',
      'id': _deviceId ?? '',
      'name': '家中摄像头',
    };
    return jsonEncode(payload);
  }

  Future<void> _toggleRecording() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_recording) {
      final path = await _recorder.stopRecording();
      setState(() => _recording = false);
      messenger.showSnackBar(
        SnackBar(content: Text('录像已保存：${path ?? '失败'}')),
      );
    } else {
      final ok = await _recorder.startRecording();
      if (ok) {
        setState(() => _recording = true);
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('本机摄像头被占用，无法同时直播与录像，请先停止直播再录像。'),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _rtc.dispose();
    _signaling.dispose();
    _recorder.dispose();
    _outgoing?.close();
    _localRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('采集端'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _error != null
          ? _buildError()
          : !_ready
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          RTCVideoView(
                            _localRenderer,
                            mirror: true,
                            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                          ),
                          // 水印（免费版）
                          if (!state.isVip)
                            const Positioned(
                              bottom: 12,
                              right: 12,
                              child: Text(
                                '旧手机监控',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                  shadows: [Shadow(color: Colors.black, blurRadius: 2)],
                                ),
                              ),
                            ),
                          if (_recording)
                            Positioned(
                              top: 12,
                              left: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.circle, color: Colors.white, size: 10),
                                    SizedBox(width: 4),
                                    Text('REC', style: TextStyle(color: Colors.white, fontSize: 12)),
                                  ],
                                ),
                              ),
                            ),
                          Positioned(
                            top: 12,
                            right: 12,
                            child: ValueListenableBuilder(
                              valueListenable: _signaling.viewerConnected,
                              builder: (_, connected, __) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: connected ? Colors.green : Colors.grey,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  connected ? '观看端已连接' : '等待观看端',
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 二维码绑定区
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.white,
                      child: Row(
                        children: [
                          QrImageView(
                            data: _qrData,
                            version: QrVersions.auto,
                            size: 110,
                            embeddedImage: null,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('观看端扫码连接',
                                    style: TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                Text('APP 地址：$_wsUrl',
                                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                const SizedBox(height: 4),
                                InkWell(
                                  onTap: () {
                                    Clipboard.setData(
                                        ClipboardData(text: _signaling.debugPageUrl));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('网页调试地址已复制')),
                                    );
                                  },
                                  child: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          '电脑浏览器：${_signaling.debugPageUrl}',
                                          style: const TextStyle(
                                              color: Colors.teal, fontSize: 12),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.copy,
                                          size: 14, color: Colors.teal),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 控制栏
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      color: Colors.grey.shade100,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _ctrlButton(
                            icon: Icons.mic,
                            label: '麦克风',
                            onTap: () async {
                              await _rtc.toggleMic();
                              setState(() {});
                            },
                            active: _rtc.micEnabled.value,
                          ),
                          _ctrlButton(
                            icon: Icons.videocam,
                            label: '摄像头',
                            onTap: () async {
                              await _rtc.toggleCamera();
                              setState(() {});
                            },
                            active: _rtc.cameraEnabled.value,
                          ),
                          _ctrlButton(
                            icon: Icons.flip_camera_ios,
                            label: '切换',
                            onTap: () => _rtc.switchCamera(),
                          ),
                          _ctrlButton(
                            icon: Icons.fiber_manual_record,
                            label: _recording ? '停止录像' : '本地录像',
                            onTap: _toggleRecording,
                            active: _recording,
                            activeColor: Colors.red,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _ctrlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = true,
    Color activeColor = Colors.teal,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: active ? activeColor : Colors.grey, size: 26),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: active ? Colors.black87 : Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(_error!, textAlign: TextAlign.center),
      ),
    );
  }
}
