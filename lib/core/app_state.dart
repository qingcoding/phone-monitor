import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全局应用状态：会员身份、绑定设备列表等
class AppState extends ChangeNotifier {
  bool _isVip = false;
  DateTime? _vipExpireAt;
  final List<String> _boundDevices = [];

  static const _kIsVip = 'is_vip';
  static const _kVipExpire = 'vip_expire';
  static const _kDevices = 'bound_devices';

  bool get isVip => _isVip;
  DateTime? get vipExpireAt => _vipExpireAt;
  List<String> get boundDevices => List.unmodifiable(_boundDevices);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _isVip = prefs.getBool(_kIsVip) ?? false;
    final exp = prefs.getString(_kVipExpire);
    if (exp != null) {
      _vipExpireAt = DateTime.tryParse(exp);
      if (_vipExpireAt != null && _vipExpireAt!.isBefore(DateTime.now())) {
        _isVip = false;
      }
    }
    _boundDevices
      ..clear()
      ..addAll(prefs.getStringList(_kDevices) ?? []);
    notifyListeners();
  }

  /// 开通会员（MVP：本地模拟，真实接入支付 SDK 后由服务端下发）
  Future<void> activateVip({int days = 30}) async {
    _isVip = true;
    _vipExpireAt = DateTime.now().add(Duration(days: days));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIsVip, true);
    await prefs.setString(_kVipExpire, _vipExpireAt!.toIso8601String());
    notifyListeners();
  }

  Future<void> restoreVip(bool vip, DateTime? expire) async {
    _isVip = vip;
    _vipExpireAt = expire;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIsVip, vip);
    if (expire != null) {
      await prefs.setString(_kVipExpire, expire.toIso8601String());
    }
    notifyListeners();
  }

  Future<void> bindDevice(String deviceId) async {
    if (!_boundDevices.contains(deviceId)) {
      _boundDevices.add(deviceId);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kDevices, _boundDevices);
      notifyListeners();
    }
  }

  Future<void> unbindDevice(String deviceId) async {
    _boundDevices.remove(deviceId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kDevices, _boundDevices);
    notifyListeners();
  }

  /// 当前账号允许绑定的最大设备数
  int get maxDevices => _isVip ? 5 : 1;
}
