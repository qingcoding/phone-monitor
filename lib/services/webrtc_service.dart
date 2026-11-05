import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// WebRTC 封装：负责 PeerConnection 建连、媒体轨、信令消息生成
class WebRtcService {
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  final ValueNotifier<MediaStream?> localStream = ValueNotifier(null);
  final ValueNotifier<MediaStream?> remoteStream = ValueNotifier(null);
  final ValueNotifier<RTCIceConnectionState> iceState =
      ValueNotifier(RTCIceConnectionState.RTCIceConnectionStateNew);
  final ValueNotifier<bool> micEnabled = ValueNotifier(true);
  final ValueNotifier<bool> cameraEnabled = ValueNotifier(true);

  StreamController<Map<String, dynamic>>? _outgoingSignaling;

  /// ICE 服务器配置；外网模式会由中继服务器下发（含 TURN）
  List<Map<String, dynamic>> _iceServers = const [
    {'urls': 'stun:stun.l.google.com:19302'},
  ];

  /// 在创建 PeerConnection 之前调用，切换 STUN/TURN 配置
  void setIceServers(List<Map<String, dynamic>> servers) {
    if (servers.isNotEmpty) _iceServers = servers;
  }

  /// 设置信令输出（向对端发送 SDP/ICE 的回调通道）
  void setOutgoingSignaling(StreamController<Map<String, dynamic>> ctrl) {
    _outgoingSignaling = ctrl;
  }

  void _send(Map<String, dynamic> msg) {
    _outgoingSignaling?.add(msg);
  }

  /// 采集端：采集本地音视频，等待观看端发起 offer
  /// [height] 视频高度：480 / 720 / 1080，决定编码分辨率与帧率
  Future<void> startCapture({
    bool audio = true,
    bool video = true,
    int height = 720,
  }) async {
    final width = (height * 16 / 9).round();
    final fps = height <= 480 ? 20 : (height <= 720 ? 24 : 30);
    final constraints = <String, dynamic>{
      'audio': audio,
      'video': video
          ? {
              'facingMode': 'environment',
              'width': {'ideal': width},
              'height': {'ideal': height},
              'frameRate': {'ideal': fps},
            }
          : false,
    };
    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
    localStream.value = _localStream;

    await _createPeerConnection();
    // 采集端先把本地轨加入 PC，等待对端 offer
    for (final track in _localStream!.getTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }
  }

  /// 观看端：采集本地音频（用于对讲），不采集视频
  Future<void> startViewerAudio() async {
    final constraints = <String, dynamic>{'audio': true, 'video': false};
    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
    localStream.value = _localStream;
    await _createPeerConnection();
    for (final track in _localStream!.getTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }
  }

  /// 仅创建 PeerConnection，不采集媒体（如观看端无麦克风权限时建连）
  Future<void> initPeerConnection() async {
    await _createPeerConnection();
  }

  Future<void> _createPeerConnection() async {
    final config = <String, dynamic>{
      'iceServers': _iceServers,
    };
    _pc = await createPeerConnection(config);

    _pc!.onIceCandidate = (candidate) {
      _send({'type': 'ice', 'candidate': candidate.toMap()});
    };
    _pc!.onIceConnectionState = (state) {
      iceState.value = state;
    };
    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        remoteStream.value = _remoteStream;
      }
    };
    _pc!.onAddStream = (stream) {
      _remoteStream = stream;
      remoteStream.value = stream;
    };
  }

  /// 观看端：创建 offer
  Future<void> createOffer() async {
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    _send({'type': 'offer', 'sdp': offer.sdp});
  }

  /// 收到远端 SDP
  Future<void> handleRemoteDescription(Map<String, dynamic> msg) async {
    final type = msg['type'] as String;
    final sdp = msg['sdp'] as String;
    await _pc!.setRemoteDescription(
      RTCSessionDescription(sdp, type),
    );
    // 采集端：收到 offer 后生成 answer
    if (type == 'offer') {
      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);
      _send({'type': 'answer', 'sdp': answer.sdp});
    }
  }

  /// 收到远端 ICE candidate
  Future<void> handleIceCandidate(Map<String, dynamic> candidate) async {
    final ice = RTCIceCandidate(
      candidate['candidate'] as String,
      candidate['sdpMid'] as String?,
      candidate['sdpMLineIndex'] as int?,
    );
    await _pc!.addCandidate(ice);
  }

  /// 处理一条信令消息
  Future<void> handleMessage(Map<String, dynamic> msg) async {
    final type = msg['type'] as String;
    if (type == 'offer' || type == 'answer') {
      await handleRemoteDescription(msg);
    } else if (type == 'ice') {
      await handleIceCandidate(msg['candidate'] as Map<String, dynamic>);
    }
  }

  // —— 控制 ——
  Future<void> toggleMic() async {
    if (_localStream == null) return;
    final tracks = _localStream!.getAudioTracks();
    if (tracks.isNotEmpty) {
      final enabled = !tracks.first.enabled;
      for (final t in tracks) {
        t.enabled = enabled;
      }
      micEnabled.value = enabled;
    }
  }

  Future<void> toggleCamera() async {
    if (_localStream == null) return;
    final tracks = _localStream!.getVideoTracks();
    if (tracks.isNotEmpty) {
      final enabled = !tracks.first.enabled;
      for (final t in tracks) {
        t.enabled = enabled;
      }
      cameraEnabled.value = enabled;
    }
  }

  /// 切换前后摄像头
  Future<void> switchCamera() async {
    if (_localStream == null) return;
    final tracks = _localStream!.getVideoTracks();
    if (tracks.isNotEmpty) {
      await Helper.switchCamera(tracks.first);
    }
  }

  Future<void> hangUp() async {
    await _pc?.close();
    _pc = null;
    await _localStream?.dispose();
    _localStream = null;
    localStream.value = null;
    remoteStream.value = null;
    _remoteStream = null;
  }

  void dispose() {
    hangUp();
    localStream.dispose();
    remoteStream.dispose();
    iceState.dispose();
    micEnabled.dispose();
    cameraEnabled.dispose();
    _outgoingSignaling?.close();
  }
}
