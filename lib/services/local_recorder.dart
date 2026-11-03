import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// 本地录像服务（采集端）。
/// 注意：摄像头可能被 WebRTC 占用，部分机型不支持同时采集；
/// 因此在录像前会尝试初始化，失败时返回错误由 UI 提示。
class LocalRecorder {
  CameraController? _controller;
  bool _recording = false;
  String? _currentPath;

  bool get isRecording => _recording;

  Future<String?> _pickBackCamera() async {
    try {
      final cams = await availableCameras();
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      return back.name;
    } catch (_) {
      return null;
    }
  }

  Future<bool> startRecording() async {
    if (_recording) return false;
    final name = await _pickBackCamera();
    if (name == null) return false;
    try {
      final cams = await availableCameras();
      final desc = cams.firstWhere((c) => c.name == name);
      _controller = CameraController(
        desc,
        ResolutionPreset.high,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await _controller!.initialize();

      final dir = await getApplicationDocumentsDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final path = p.join(dir.path, 'record_$stamp.mp4');
      await _controller!.startVideoRecording();
      _currentPath = path;
      _recording = true;
      debugPrint('Local recording started: $path');
      return true;
    } catch (e) {
      debugPrint('Local recording start failed: $e');
      await _controller?.dispose();
      _controller = null;
      return false;
    }
  }

  Future<String?> stopRecording() async {
    if (!_recording || _controller == null) return null;
    try {
      final file = await _controller!.stopVideoRecording();
      // 保存到持久目录
      if (_currentPath != null) {
        final saved = File(_currentPath!);
        await file.saveTo(saved.path);
      }
      _recording = false;
      final path = _currentPath;
      _currentPath = null;
      await _controller?.dispose();
      _controller = null;
      return path;
    } catch (e) {
      debugPrint('Local recording stop failed: $e');
      _recording = false;
      _currentPath = null;
      await _controller?.dispose();
      _controller = null;
      return null;
    }
  }

  Future<void> dispose() async {
    if (_recording) {
      await stopRecording();
    }
    await _controller?.dispose();
    _controller = null;
  }
}
