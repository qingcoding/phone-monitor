import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'features/role_selection/role_selection_page.dart';

class PhoneMonitorApp extends StatelessWidget {
  const PhoneMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '旧手机监控',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const RoleSelectionPage(),
    );
  }
}
