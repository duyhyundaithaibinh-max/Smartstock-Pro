import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartstock_pro/api_auth.dart';
import 'package:smartstock_pro/main.dart' show DashboardPage, SmartStockApp;

const _token = 'test-session-token';
const _secret = 'S' * 32;
const _password = 'test-password-123';

http.Response _json(int status, Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

Future<void> _pumpDashboard(
  WidgetTester tester,
  MockClient client, {
  Widget Function(String baseUrl, String symbol, String apiToken)?
      chartBuilder,
  Widget Function(String baseUrl, String apiToken)? trainingBuilder,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: DashboardPage(
      httpClient: client,
      chartPageBuilder: chartBuilder,
      trainingRoomPageBuilder: trainingBuilder,
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _login(
  WidgetTester tester, {
  String password = _password,
}) async {
  await tester.enterText(find.byKey(const ValueKey('username')), 'owner');
  await tester.enterText(find.byKey(const ValueKey('password')), password);
  await tester.tap(find.byKey(const ValueKey('auth-submit')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('first launch shows backend connection while status loads',
      (tester) async {
    final client = MockClient((request) async =>
        _json(200, {'owner_initialized': true}));
    await tester.pumpWidget(const SmartStockApp());
    await tester.pump();
    expect(find.text('SmartStock Pro • Đăng nhập'), findsOneWidget);
    expect(find.text('Kết nối backend'), findsOneWidget);
    client.close();
  });

  testWidgets('owner not initialized exposes bootstrap; initialized owner does not',
      (tester) async {
    final newOwnerClient = MockClient((request) async =>
        _json(200, {'owner_initialized': false}));
    await _pumpDashboard(tester, newOwnerClient);
    expect(find.byKey(const ValueKey('bootstrap-secret')), findsOneWidget);
    expect(find.text('Khởi tạo chủ sở hữu'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    newOwnerClient.close();

    final existingOwnerClient = MockClient((request) async =>
        _json(200, {'owner_initialized': true}));
    await _pumpDashboard(tester, existingOwnerClient);
    expect(find.byKey(const ValueKey('bootstrap-secret')), findsNothing);
    expect(find.text('Đăng nhập'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    existingOwnerClient.close();
  });

  for (final status in [403, 422]) {
    testWidgets('bootstrap HTTP $status shows safe error without response body',
        (tester) async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/auth/status')) {
          return _json(200, {'owner_initialized': false});
        }
        if (request.url.path.endsWith('/register-first-owner')) {
          return http.Response(
            'LEAKED-SECRET-$_secret-LEAKED-PASSWORD-$_password',
            status,
          );
        }
        fail('Unexpected request: ${request.method} ${request.url}');
      });
      await _pumpDashboard(tester, client);
      await tester.enterText(find.byKey(const ValueKey('username')), 'owner');
      await tester.enterText(find.byKey(const ValueKey('password')), _password);
      await tester.enterText(
          find.byKey(const ValueKey('bootstrap-secret')), _secret);
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pumpAndSettle();

      expect(find.textContaining('LEAKED-SECRET'), findsNothing);
      expect(find.textContaining('LEAKED-PASSWORD'), findsNothing);
      expect(find.textContaining(status == 403
          ? 'Bootstrap secret không đúng hoặc đã được sử dụng.'
          : 'Bootstrap secret chưa hợp lệ (32–256 ký tự).'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    });
  }

  testWidgets('bootstrap success submits expected payload then logs in',
      (tester) async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      switch (request.url.path) {
        case '/api/v1/auth/status':
          return _json(200, {'owner_initialized': false});
        case '/api/v1/auth/register-first-owner':
          return _json(201, {'created': true});
        case '/api/v1/auth/login':
          return _json(200, {'access_token': _token});
        case '/health':
          return _json(200, {'status': 'ok', 'version': 'test'});
        case '/api/v1/watchlist':
          return _json(200, {'items': []});
        default:
          fail('Unexpected request: ${request.method} ${request.url}');
      }
    });
    await _pumpDashboard(tester, client);
    await tester.enterText(find.byKey(const ValueKey('username')), 'owner');
    await tester.enterText(find.byKey(const ValueKey('password')), _password);
    await tester.enterText(
        find.byKey(const ValueKey('bootstrap-secret')), _secret);
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    await tester.pumpAndSettle();

    final setup = requests.firstWhere(
        (request) => request.url.path.endsWith('/register-first-owner'));
    final payload = jsonDecode(setup.body) as Map<String, dynamic>;
    expect(payload['username'], 'owner');
    expect(payload['password'], _password);
    expect(payload['bootstrap_secret'], _secret);
    expect(find.text('Danh sách theo dõi'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('login failure does not echo raw backend response',
      (tester) async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/status')) {
        return _json(200, {'owner_initialized': true});
      }
      if (request.url.path.endsWith('/auth/login')) {
        return http.Response('RAW-SECRET-$_secret-RAW-TOKEN-$_token', 401);
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    await _pumpDashboard(tester, client);
    await tester.enterText(find.byKey(const ValueKey('username')), 'owner');
    await tester.enterText(find.byKey(const ValueKey('password')), _password);
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    await tester.pumpAndSettle();

    expect(find.textContaining('RAW-SECRET'), findsNothing);
    expect(find.textContaining('RAW-TOKEN'), findsNothing);
    expect(find.text('Đăng nhập thất bại (HTTP 401).'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('login sends Bearer to watchlist and passes token to Chart and Training Room',
      (tester) async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      switch (request.url.path) {
        case '/api/v1/auth/status':
          return _json(200, {'owner_initialized': true});
        case '/api/v1/auth/login':
          return _json(200, {'access_token': _token});
        case '/health':
          return _json(200, {'status': 'ok', 'version': 'test'});
        case '/api/v1/watchlist':
          return _json(200, {'items': [
            {'symbol': 'FPT', 'name': 'FPT', 'exchange': 'HOSE', 'candle_count': 0}
          ]});
        default:
          fail('Unexpected request: ${request.method} ${request.url}');
      }
    });
    await _pumpDashboard(
      tester,
      client,
      chartBuilder: (baseUrl, symbol, token) =>
          Text('chart-probe:$symbol:$token'),
      trainingBuilder: (baseUrl, token) => Text('training-probe:$token'),
    );
    await _login(tester);

    final watchlistGet = requests.firstWhere((request) =>
        request.method == 'GET' && request.url.path == '/api/v1/watchlist');
    expect(watchlistGet.headers['authorization'], 'Bearer $_token');

    await tester.tap(find.text('FPT'));
    await tester.pumpAndSettle();
    expect(find.text('chart-probe:FPT:$_token'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Hybrid AI Training Room'));
    await tester.pumpAndSettle();
    expect(find.text('training-probe:$_token'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('logout clears local session even when logout request fails',
      (tester) async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      switch (request.url.path) {
        case '/api/v1/auth/status':
          return _json(200, {'owner_initialized': true});
        case '/api/v1/auth/login':
          return _json(200, {'access_token': _token});
        case '/health':
          return _json(200, {'status': 'ok', 'version': 'test'});
        case '/api/v1/watchlist':
          return _json(200, {'items': []});
        case '/api/v1/auth/logout':
          throw Exception('network failure containing $_token');
        default:
          fail('Unexpected request: ${request.method} ${request.url}');
      }
    });
    await _pumpDashboard(tester, client);
    await _login(tester);
    expect(find.text('Danh sách theo dõi'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('logout')));
    await tester.pumpAndSettle();
    expect(find.text('SmartStock Pro • Đăng nhập'), findsOneWidget);
    expect(find.text('Danh sách theo dõi'), findsNothing);
    expect(requests.last.headers['authorization'], 'Bearer $_token');
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
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
