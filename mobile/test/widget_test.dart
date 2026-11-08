import 'package:flutter_test/flutter_test.dart';
import 'package:smartstock_pro/api_auth.dart';
import 'package:smartstock_pro/main.dart' show SmartStockApp;

void main() {
  testWidgets('first launch shows the owner sign-in gate', (tester) async {
    await tester.pumpWidget(const SmartStockApp());
    expect(find.text('SmartStock Pro'), findsOneWidget);
    expect(find.text('SmartStock Pro • Đăng nhập'), findsOneWidget);
    expect(find.text('Backend URL'), findsOneWidget);
    expect(find.text('Tên đăng nhập'), findsOneWidget);
    expect(find.text('Mật khẩu'), findsOneWidget);
    expect(find.text('Thị trường Việt Nam'), findsNothing);
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
