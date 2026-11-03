import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:phone_monitor/app.dart';
import 'package:phone_monitor/core/app_state.dart';

void main() {
  testWidgets('Role selection page renders', (WidgetTester tester) async {
    final state = AppState();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const PhoneMonitorApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('请选择本机角色'), findsOneWidget);
    expect(find.text('采集端（摄像头）'), findsOneWidget);
  });
}
