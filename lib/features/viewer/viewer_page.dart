import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/app_state.dart';
import '../../services/permissions.dart';
import '../../services/signaling_client.dart';
import '../../services/webrtc_service.dart';

class ViewerPage extends StatefulWidget {
  final String url;

  /// 外网模式由中继服务器下发的 ICE 配置（含 TURN），局域网模式为空
  final List<Map<String, dynamic>>? iceServers;

  const ViewerPage({super.key, required this.url, this.iceServers});

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  final WebRtcService _rtc = WebRtcService();
  final SignalingClient _signaling = SignalingClient();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  StreamController<Map<String, dynamic>>? _outgoing;

  bool _connecting = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _remoteRenderer.initialize();
    final micOk = await Permissions.requestViewer();
    if (!micOk) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未授予麦克风权限，将无法对讲')),
        );
      }
    }
    try {
      _outgoing = StreamController<Map<String, dynamic>>.broadcast();
      _rtc.setOutgoingSignaling(_outgoing!);
      if (widget.iceServers != null && widget.iceServers!.isNotEmpty) {
        _rtc.setIceServers(widget.iceServers!);
      }
      _outgoing!.stream.listen((msg) => _signaling.send(msg));
      _signaling.incoming.stream.listen((msg) => _rtc.handleMessage(msg));

      _rtc.remoteStream.addListener(() {
        final s = _rtc.remoteStream.value;
        if (s != null) {
          _remoteRenderer.srcObject = s;
          if (mounted) setState(() {});
        }
      });

      if (micOk) {
        await _rtc.startViewerAudio();
      } else {
        await _rtc.initPeerConnection();
      }

      await _signaling.connect(widget.url);
      await _rtc.createOffer();

      setState(() => _connecting = false);
      unawaited(WakelockPlus.enable());
    } catch (e) {
      setState(() {
        _error = '连接失败：$e';
        _connecting = false;
      });
    }
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _rtc.dispose();
    _signaling.dispose();
    _outgoing?.close();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return ValueListenableBuilder<RTCIceConnectionState>(
      valueListenable: _rtc.iceState,
      builder: (context, ice, _) {
        final connected =
            ice == RTCIceConnectionState.RTCIceConnectionStateConnected ||
                ice == RTCIceConnectionState.RTCIceConnectionStateCompleted;

        return Scaffold(
          appBar: AppBar(
            title: const Text('观看中'),
            actions: [
              IconButton(
                icon: const Icon(Icons.call_end, color: Colors.redAccent),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          body: _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center),
                ))
              : Stack(
                  children: [
                    RTCVideoView(
                      _remoteRenderer,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                    ),
                    if (!state.isVip)
                      const Positioned(
                        bottom: 16,
                        right: 16,
                        child: Text(
                          '旧手机监控',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            shadows: [Shadow(color: Colors.black, blurRadius: 2)],
                          ),
                        ),
                      ),
                    Positioned(
                      top: 16,
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: connected ? Colors.green : Colors.orange,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          connected ? '已连接' : _connecting ? '连接中…' : '未连接',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ),
                    if (_connecting)
                      const Center(child: CircularProgressIndicator()),
                  ],
                ),
          bottomNavigationBar: BottomAppBar(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ValueListenableBuilder(
                  valueListenable: _rtc.micEnabled,
                  builder: (_, enabled, __) => IconButton(
                    icon: Icon(enabled ? Icons.mic : Icons.mic_off),
                    color: enabled ? Colors.teal : Colors.grey,
                    onPressed: () async {
                      await _rtc.toggleMic();
                    },
                    tooltip: '对讲麦克风',
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.volume_up),
                  onPressed: () {},
                  tooltip: '扬声器',
                ),
                IconButton(
                  icon: const Icon(Icons.fullscreen),
                  onPressed: () {},
                  tooltip: '全屏',
                ),
                if (!state.isVip)
                  TextButton(
                    onPressed: () {
                      // 引导升级
                    },
                    child: const Text('升级会员，远程观看'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

