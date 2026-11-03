import 'package:permission_handler/permission_handler.dart';

/// 权限申请工具
class Permissions {
  Permissions._();

  /// 采集端所需权限：相机、麦克风
  static Future<bool> requestCapture() async {
    final statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();
    return statuses[Permission.camera]!.isGranted &&
        statuses[Permission.microphone]!.isGranted;
  }

  /// 观看端所需权限：麦克风（对讲）
  static Future<bool> requestViewer() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// 后台保活相关权限（Android）
  static Future<Map<Permission, PermissionStatus>> requestKeepAlive() async {
    return await [
      Permission.ignoreBatteryOptimizations,
      Permission.systemAlertWindow,
    ].request();
  }
}
