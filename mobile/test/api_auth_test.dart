import 'package:flutter_test/flutter_test.dart';
import 'package:smartstock_pro/api_auth.dart';

void main() {
  group('apiAuthHeaders', () {
    test('returns no authorization header for an empty token', () {
      expect(apiAuthHeaders(''), isEmpty);
      expect(apiAuthHeaders('   '), isEmpty);
    });

    test('trims token and formats bearer authorization', () {
      expect(
        apiAuthHeaders('  demo-token  '),
        {'Authorization': 'Bearer demo-token'},
      );
    });
  });
}
