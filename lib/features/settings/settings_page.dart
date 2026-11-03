import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/constants.dart';
import 'membership_page.dart';
import 'keepalive_guide.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.workspace_premium),
            title: const Text('会员中心'),
            subtitle: Text(state.isVip ? '会员生效中' : '免费版，仅局域网观看'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MembershipPage()),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.battery_charging_full),
            title: const Text('后台保活设置'),
            subtitle: const Text('关闭电池优化、允许后台运行'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const KeepAliveGuide()),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.gavel),
            title: const Text('使用须知与免责声明'),
            onTap: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('使用须知'),
                content: const Text(AppConstants.complianceNotice),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('我已知晓'),
                  ),
                ],
              ),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于'),
            subtitle: Text('${AppConstants.appName} v${AppConstants.appVersion}'),
          ),
        ],
      ),
    );
  }
}
