/// 全局常量
class AppConstants {
  AppConstants._();

  static const String appName = '旧手机监控';
  static const String appVersion = '1.2.0';

  /// 采集端信令监听端口（同一局域网内观看端直连）
  static const int signalingPort = 8765;

  /// 免费版权益
  static const bool freeLanOnly = true;
  static const bool freeLocalRecording = true;
  static const bool freeTwoWayAudio = true;
  static const bool freeMotionDetect = true;
  static const int freeMaxDevices = 1;
  static const bool freeWatermark = true;

  /// 会员版权益
  static const bool vipRelayRemote = true;
  static const int vipCloudStorageDays = 7;
  static const bool vipAiCryDetect = true;
  static const int vipMaxDevices = 5;
  static const bool vipNoWatermark = true;

  /// 会员价格（展示用，实际支付走第三方 SDK）
  static const String vipPriceMonthly = '¥19/月';
  static const String vipPriceYearly = '¥168/年';

  /// 本地录像循环覆盖阈值（MB）
  static const int recordingMaxSizeMB = 512;

  /// 合规文案
  static const String complianceNotice =
      '本软件仅限家庭自用看护，禁止用于偷拍、侵犯他人隐私等违法用途。\n'
      'AI 哭声识别仅为辅助提醒，不能替代人工看护。';
}
