import 'package:flutter_test/flutter_test.dart';
import 'package:smartstock_pro/main.dart';

void main() {
  testWidgets('dashboard renders SmartStock Pro', (tester) async {
    await tester.pumpWidget(const SmartStockApp());
    expect(find.text('SmartStock Pro'), findsOneWidget);
    expect(find.text('Thị trường Việt Nam'), findsOneWidget);
  });
}
