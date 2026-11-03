import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 设备信息与局域网地址
class DeviceInfo {
  DeviceInfo._();

  static const _kDeviceId = 'device_id';

  /// 获取或生成本设备唯一 ID
  static Future<String> deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString(_kDeviceId);
    if (id == null || id.isEmpty) {
      id = 'dev_${DateTime.now().millisecondsSinceEpoch}_${_rand(6)}';
      await prefs.setString(_kDeviceId, id);
    }
    return id;
  }

  static String _rand(int len) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final buf = StringBuffer();
    for (var i = 0; i < len; i++) {
      buf.write(chars[DateTime.now().microsecond % chars.length]);
    }
    return buf.toString();
  }

  /// 获取本机局域网 IPv4 地址（用于观看端直连信令）
  static Future<String?> localIp() async {
    try {
      final info = NetworkInfo();
      final ip = await info.getWifiIP();
      if (ip != null && ip.isNotEmpty) return ip;
    } catch (_) {}
    // 兜底：遍历网络接口
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type.name == 'IPv4' && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return null;
  }
}
