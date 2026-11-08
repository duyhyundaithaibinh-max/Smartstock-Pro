import 'package:flutter_test/flutter_test.dart';
import 'package:smartstock_pro/api_auth.dart';
import 'package:smartstock_pro/main.dart' show SmartStockApp;

void main() {
  testWidgets('first launch shows backend connection and owner login gate', (tester) async {
    await tester.pumpWidget(const SmartStockApp());
    expect(find.text('SmartStock Pro • Đăng nhập'), findsOneWidget);
    expect(find.text('Kết nối backend'), findsOneWidget);
  });

  test('API auth omits empty tokens', () {
    expect(apiAuthHeaders(''), isEmpty);
    expect(apiAuthHeaders('   '), isEmpty);
  });

  test('API auth trims token and creates Bearer header', () {
    expect(
      apiAuthHeaders('  local-secret-token  '),
      equals({'Authorization': 'Bearer local-secret-token'}),
    );
  });
}
