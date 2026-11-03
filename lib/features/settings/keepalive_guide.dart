import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/permissions.dart';

class KeepAliveGuide extends StatefulWidget {
  const KeepAliveGuide({super.key});

  @override
  State<KeepAliveGuide> createState() => _KeepAliveGuideState();
}

class _KeepAliveGuideState extends State<KeepAliveGuide> {
  bool _batteryOk = false;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('后台保活设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '为保证采集端 7×24 小时稳定运行，请按以下步骤设置：',
            style: TextStyle(fontSize: 15, height: 1.5),
          ),
          const SizedBox(height: 16),
          _step('1. 关闭电池优化', '避免系统在息屏时杀掉监控进程。',
              action: ElevatedButton(
                onPressed: _loading ? null : () async {
                  setState(() => _loading = true);
                  final res = await Permissions.requestKeepAlive();
                  setState(() {
                    _loading = false;
                    _batteryOk = res.values.every(
                        (s) => s == PermissionStatus.granted || s == PermissionStatus.limited);
                  });
                },
                child: Text(_batteryOk ? '已授权' : '去授权'),
              )),
          _step('2. 允许后台运行',
              '在系统设置 → 应用 → 旧手机监控 → 电池 → 允许后台活动。',
              action: const Text('请手动设置', style: TextStyle(color: Colors.grey))),
          _step('3. 保持 WiFi 不断连',
              '在 WiFi 设置中关闭“息屏断开 WiFi”或选择“始终连接”。',
              action: const Text('请手动设置', style: TextStyle(color: Colors.grey))),
          _step('4. 锁定后台',
              '进入多任务界面，将本应用下拉锁定，防止被一键清理。',
              action: const Text('请手动设置', style: TextStyle(color: Colors.grey))),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '提示：不同品牌手机（华为/小米/OPPO/vivo 等）保活路径略有差异，建议按机型搜索“XX 手机后台保活设置”。',
              style: TextStyle(color: Colors.blueGrey, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _step(String title, String desc, {required Widget action}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(desc, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            ),
            action,
          ],
        ),
      ),
    );
  }
}
