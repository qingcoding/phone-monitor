import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/constants.dart';

class MembershipPage extends StatelessWidget {
  const MembershipPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('会员中心')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Colors.amber.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('👑 会员专属权益',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _benefit('中继服务器兜底远程观看（外网随时随地可看）'),
                  _benefit('云端 7 天循环录像存储'),
                  _benefit('AI 婴儿哭声智能识别 + 推送告警'),
                  _benefit('最多 5 台设备同时绑定'),
                  _benefit('画面去水印、低延迟优先通道'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('订阅方案',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _planCard(
                  context,
                  title: '月度会员',
                  price: AppConstants.vipPriceMonthly,
                  onTap: () => _subscribe(context, days: 30),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _planCard(
                  context,
                  title: '年度会员',
                  price: AppConstants.vipPriceYearly,
                  highlight: true,
                  onTap: () => _subscribe(context, days: 365),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (state.isVip)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '当前状态：会员生效中，到期 ${state.vipExpireAt?.toString().substring(0, 10) ?? '-'}',
                style: const TextStyle(color: Colors.green),
              ),
            ),
          const SizedBox(height: 16),
          const Text(
            '说明：MVP 版本会员开通为本地模拟，正式上线将接入微信/支付宝订阅 SDK 与服务端鉴权。',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _benefit(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, color: Colors.amber, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
        ],
      ),
    );
  }

  Widget _planCard(
    BuildContext context, {
    required String title,
    required String price,
    required VoidCallback onTap,
    bool highlight = false,
  }) {
    return Card(
      color: highlight ? Colors.amber.shade100 : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: highlight ? Colors.amber : Colors.grey.shade300),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(price,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: highlight ? Colors.amber.shade800 : Colors.black)),
              const SizedBox(height: 8),
              Text(highlight ? '推荐' : '', style: const TextStyle(color: Colors.amber)),
            ],
          ),
        ),
      ),
    );
  }

  void _subscribe(BuildContext context, {required int days}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认开通'),
        content: Text('将开通 $days 天会员（MVP 模拟）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              context.read<AppState>().activateVip(days: days);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('会员已开通！')),
              );
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }
}
