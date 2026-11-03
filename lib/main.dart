import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.load();
  runApp(
    ChangeNotifierProvider.value(
      value: state,
      child: const PhoneMonitorApp(),
    ),
  );
}
