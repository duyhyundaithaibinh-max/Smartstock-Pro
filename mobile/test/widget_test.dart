import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartstock_pro/api_auth.dart';
import 'package:smartstock_pro/chart_page.dart';
import 'package:smartstock_pro/training_room_page.dart';
import 'package:smartstock_pro/stock_detail_page.dart';
import 'package:smartstock_pro/analysis_page.dart';
import 'package:smartstock_pro/main.dart' show DashboardPage;

const _token = 'test-session-token';
const _secret = 'SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS';
const _password = 'test-password-123';

http.Response _json(int status, Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

Future<void> _pumpDashboard(
  WidgetTester tester,
  MockClient client, {
  Widget Function(String baseUrl, String symbol, String apiToken,
      void Function(String token) onSessionExpired)? chartBuilder,
  Widget Function(String baseUrl, String apiToken,
      void Function(String token) onSessionExpired)? trainingBuilder,
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
  testWidgets('first launch presents the owner login gate', (tester) async {
    final client = MockClient((request) async =>
        _json(200, {'owner_initialized': true}));
    await _pumpDashboard(tester, client);
    expect(find.text('SmartStock Pro • Đăng nhập'), findsOneWidget);
    expect(find.text('Đăng nhập chủ sở hữu'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('owner not initialized exposes bootstrap; initialized owner does not',
      (tester) async {
    final newOwnerClient = MockClient((request) async =>
        _json(200, {'owner_initialized': false}));
    await _pumpDashboard(tester, newOwnerClient);
    expect(find.byKey(const ValueKey('bootstrap-secret')), findsOneWidget);
    expect(find.text('Khởi tạo chủ sở hữu'), findsOneWidget);
    expect(
      tester.widget<TextField>(
        find.byKey(const ValueKey('bootstrap-secret')),
      ).obscureText,
      isTrue,
    );
    expect(
      tester.widget<TextField>(
        find.byKey(const ValueKey('password')),
      ).obscureText,
      isTrue,
    );
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

  testWidgets('bootstrap HTTP 403 shows safe secret error without response body',
      (tester) async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/status')) {
        return _json(200, {'owner_initialized': false});
      }
      if (request.url.path.endsWith('/register-first-owner')) {
        return http.Response(
          'LEAKED-SECRET-$_secret-LEAKED-PASSWORD-$_password',
          403,
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
    expect(find.textContaining(
      'Bootstrap secret không đúng hoặc đã được sử dụng.',
    ), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('bootstrap HTTP 422 validation shows generic safe error',
      (tester) async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/status')) {
        return _json(200, {'owner_initialized': false});
      }
      if (request.url.path.endsWith('/register-first-owner')) {
        return _json(422, {
          'detail':
              'username/password validation failed: LEAKED-USERNAME-$_password-$_secret',
        });
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

    expect(find.textContaining('Thông tin khởi tạo chưa hợp lệ.'),
        findsOneWidget);
    expect(find.textContaining('LEAKED-USERNAME'), findsNothing);
    expect(find.textContaining('LEAKED-PASSWORD'), findsNothing);
    final renderedText = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
        .join('\\n');
    expect(renderedText, isNot(contains(_secret)));
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('bootstrap HTTP 409 switches to owner login with safe guidance',
      (tester) async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/status')) {
        return _json(200, {'owner_initialized': false});
      }
      if (request.url.path.endsWith('/register-first-owner')) {
        return http.Response(
          'OWNER-CONFLICT-LEAKED-SECRET-$_secret-LEAKED-PASSWORD-$_password',
          409,
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

    expect(find.byKey(const ValueKey('bootstrap-secret')), findsNothing);
    expect(find.text('Đăng nhập chủ sở hữu'), findsOneWidget);
    expect(
      find.textContaining(
        'Tài khoản chủ sở hữu đã được khởi tạo. Hãy đăng nhập hoặc kiểm tra trạng thái backend.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('OWNER-CONFLICT-LEAKED'), findsNothing);
    expect(find.textContaining('LEAKED-PASSWORD'), findsNothing);
    expect(find.textContaining(_secret), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

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
    expect(find.textContaining('Đăng nhập thất bại (HTTP 401).'), findsOneWidget);
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
      chartBuilder: (baseUrl, symbol, token, onSessionExpired) =>
          Text('chart-probe:$symbol:$token'),
      trainingBuilder: (baseUrl, token, onSessionExpired) =>
          Text('training-probe:$token'),
    );
    await _login(tester);

    final watchlistGet = requests.firstWhere((request) =>
        request.method == 'GET' && request.url.path == '/api/v1/watchlist');
    expect(watchlistGet.headers['authorization'], 'Bearer $_token');

    await tester.scrollUntilVisible(
      find.text('FPT'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('FPT'));
    await tester.pumpAndSettle();
    expect(find.text('chart-probe:FPT:$_token'), findsOneWidget);
    Navigator.of(tester.element(find.text('chart-probe:FPT:$_token'))).pop();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Hybrid AI Training Room'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
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

  testWidgets('Chart HTTP 401 invokes session expiry without rendering response body',
      (tester) async {
    var expiredToken = '';
    final client = MockClient((request) async => http.Response(
      '<html>CHART-TRACEBACK-$_token</html>',
      401,
    ));
    await tester.pumpWidget(MaterialApp(
      home: ChartPage(
        baseUrl: 'http://test',
        symbol: 'FPT',
        apiToken: _token,
        httpClient: client,
        onSessionExpired: (token) => expiredToken = token,
      ),
    ));
    await tester.pumpAndSettle();

    expect(expiredToken, _token);
    expect(find.textContaining('CHART-TRACEBACK'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('Training Room 401s invoke expiry and never render raw response bodies',
      (tester) async {
    var expiredCalls = 0;
    final client = MockClient((request) async => http.Response(
      '<html>TRAINING-TRACEBACK-$_token</html>',
      401,
    ));
    await tester.pumpWidget(MaterialApp(
      home: TrainingRoomPage(
        baseUrl: 'http://test',
        apiToken: _token,
        httpClient: client,
        onSessionExpired: (token) {
          expect(token, _token);
          expiredCalls++;
        },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('Phiên đăng nhập đã hết hạn'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(expiredCalls, greaterThanOrEqualTo(1));
    expect(find.textContaining('TRAINING-TRACEBACK'), findsNothing);
    expect(
      find.textContaining(
        'Phiên đăng nhập đã hết hạn hoặc bị thu hồi. Vui lòng đăng nhập lại.',
      ),
      findsWidgets,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('Training Room prioritizes a concurrent 401 over another failed request',
      (tester) async {
    var expiredCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/training/examples')) {
        return http.Response('EXAMPLES-INTERNAL-500', 500);
      }
      if (request.url.path.endsWith('/training/evaluation')) {
        return http.Response('EVALUATION-PRIVATE-401', 401);
      }
      if (request.url.path.endsWith('/knowledge/documents')) {
        return _json(200, {'items': []});
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    await tester.pumpWidget(MaterialApp(
      home: TrainingRoomPage(
        baseUrl: 'http://test',
        apiToken: _token,
        httpClient: client,
        onSessionExpired: (token) {
          expect(token, _token);
          expiredCalls++;
        },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('Phiên đăng nhập đã hết hạn'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(expiredCalls, 1);
    expect(find.textContaining('EXAMPLES-INTERNAL-500'), findsNothing);
    expect(find.textContaining('EVALUATION-PRIVATE-401'), findsNothing);
    expect(find.textContaining('Phiên đăng nhập đã hết hạn'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('Training Room 422 sanitizes HTML and traceback response bodies',
      (tester) async {
    final client = MockClient((request) async => http.Response(
      '<html><pre>SQL-TRACEBACK-PRIVATE-DETAIL</pre></html>',
      422,
    ));
    await tester.pumpWidget(MaterialApp(
      home: TrainingRoomPage(
        baseUrl: 'http://test',
        apiToken: _token,
        httpClient: client,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('Dữ liệu gửi lên chưa hợp lệ'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.textContaining('SQL-TRACEBACK'), findsNothing);
    expect(find.textContaining('PRIVATE-DETAIL'), findsNothing);
    expect(find.textContaining('Dữ liệu gửi lên chưa hợp lệ'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('protected watchlist HTTP 401 expires the active session safely',
      (tester) async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/status')) {
        return _json(200, {'owner_initialized': true});
      }
      if (request.url.path.endsWith('/auth/login')) {
        return _json(200, {'access_token': _token});
      }
      if (request.url.path == '/health') {
        return _json(200, {'status': 'ok', 'version': 'test'});
      }
      if (request.url.path == '/api/v1/watchlist') {
        return http.Response(
          '<html>INTERNAL-TRACEBACK-LEAKED-TOKEN-$_token</html>',
          401,
        );
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    await _pumpDashboard(tester, client);
    await _login(tester);

    expect(find.text('SmartStock Pro • Đăng nhập'), findsOneWidget);
    expect(
      find.text(
        'Phiên đăng nhập đã hết hạn hoặc bị thu hồi. Vui lòng đăng nhập lại.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('INTERNAL-TRACEBACK'), findsNothing);
    expect(find.textContaining(_token), findsNothing);
    expect(find.text('Danh sách theo dõi'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('403, 422 and 500 do not clear an authenticated session',
      (tester) async {
    for (final status in [403, 409, 422, 500]) {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/auth/status')) {
          return _json(200, {'owner_initialized': true});
        }
        if (request.url.path.endsWith('/auth/login')) {
          return _json(200, {'access_token': _token});
        }
        if (request.url.path == '/health') {
          return _json(200, {'status': 'ok', 'version': 'test'});
        }
        if (request.url.path == '/api/v1/watchlist') {
          return http.Response('RAW-PRIVATE-BODY', status);
        }
        fail('Unexpected request: ${request.method} ${request.url}');
      });
      await _pumpDashboard(tester, client);
      await _login(tester);

      expect(find.text('SmartStock Pro • Đăng nhập'), findsNothing);
      expect(find.text('Danh sách theo dõi'), findsOneWidget);
      expect(find.textContaining('RAW-PRIVATE-BODY'), findsNothing);
      if (status == 403) {
        expect(find.textContaining('Bạn không có quyền'), findsOneWidget);
      } else if (status == 409) {
        expect(find.textContaining('Dữ liệu đang xung đột'), findsOneWidget);
      } else if (status == 422) {
        expect(find.textContaining('Dữ liệu gửi lên chưa hợp lệ'), findsOneWidget);
      } else {
        expect(find.textContaining('Máy chủ đang gặp sự cố'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    }
  });

  testWidgets('network failure does not clear the active session or expose exception text',
      (tester) async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/status')) {
        return _json(200, {'owner_initialized': true});
      }
      if (request.url.path.endsWith('/auth/login')) {
        return _json(200, {'access_token': _token});
      }
      if (request.url.path == '/health') {
        return _json(200, {'status': 'ok', 'version': 'test'});
      }
      if (request.url.path == '/api/v1/watchlist') {
        throw const SocketException('NETWORK-INTERNAL-DETAIL');
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    await _pumpDashboard(tester, client);
    await _login(tester);

    expect(find.text('SmartStock Pro • Đăng nhập'), findsNothing);
    expect(find.text('Danh sách theo dõi'), findsOneWidget);
    expect(find.textContaining('NETWORK-INTERNAL-DETAIL'), findsNothing);
    expect(find.textContaining('Không thể kết nối máy chủ'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('multiple expired-session callbacks only navigate once',
      (tester) async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/status')) {
        return _json(200, {'owner_initialized': true});
      }
      if (request.url.path.endsWith('/auth/login')) {
        return _json(200, {'access_token': _token});
      }
      if (request.url.path == '/health') {
        return _json(200, {'status': 'ok', 'version': 'test'});
      }
      if (request.url.path == '/api/v1/watchlist') {
        return _json(200, {'items': [
          {'symbol': 'FPT', 'name': 'FPT', 'exchange': 'HOSE', 'candle_count': 0}
        ]});
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    await _pumpDashboard(
      tester,
      client,
      chartBuilder: (baseUrl, symbol, token, onSessionExpired) =>
          ElevatedButton(
            onPressed: () {
              onSessionExpired(token);
              onSessionExpired(token);
            },
            child: const Text('expire-twice'),
          ),
    );
    await _login(tester);
    await tester.scrollUntilVisible(
      find.text('FPT'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('FPT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('expire-twice'));
    await tester.pumpAndSettle();

    expect(find.text('SmartStock Pro • Đăng nhập'), findsOneWidget);
    expect(
      find.text(
        'Phiên đăng nhập đã hết hạn hoặc bị thu hồi. Vui lòng đăng nhập lại.',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });


  testWidgets('TimeoutException does not clear session or expose exception text',
      (tester) async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/status')) {
        return _json(200, {'owner_initialized': true});
      }
      if (request.url.path.endsWith('/auth/login')) {
        return _json(200, {'access_token': _token});
      }
      if (request.url.path == '/health') {
        return _json(200, {'status': 'ok', 'version': 'test'});
      }
      if (request.url.path == '/api/v1/watchlist') {
        throw TimeoutException('TIMEOUT-INTERNAL-SECRET-$_token');
      }
      fail('Unexpected request: \${request.method} \${request.url}');
    });
    await _pumpDashboard(tester, client);
    await _login(tester);

    expect(find.text('SmartStock Pro • Đăng nhập'), findsNothing);
    expect(find.text('Danh sách theo dõi'), findsOneWidget);
    expect(find.textContaining('Không thể kết nối máy chủ'), findsOneWidget);
    expect(find.textContaining('TIMEOUT-INTERNAL-SECRET'), findsNothing);
    expect(find.textContaining(_token), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('HTTP 429 does not expire an authenticated session',
      (tester) async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/status')) {
        return _json(200, {'owner_initialized': true});
      }
      if (request.url.path.endsWith('/auth/login')) {
        return _json(200, {'access_token': _token});
      }
      if (request.url.path == '/health') {
        return _json(200, {'status': 'ok', 'version': 'test'});
      }
      if (request.url.path == '/api/v1/watchlist') {
        return http.Response('429-PRIVATE-DETAIL-$_token', 429);
      }
      fail('Unexpected request: \${request.method} \${request.url}');
    });
    await _pumpDashboard(tester, client);
    await _login(tester);

    expect(find.text('SmartStock Pro • Đăng nhập'), findsNothing);
    expect(find.text('Danh sách theo dõi'), findsOneWidget);
    expect(find.textContaining('Bạn thao tác quá thường xuyên'), findsOneWidget);
    expect(find.textContaining('429-PRIVATE-DETAIL'), findsNothing);
    expect(find.textContaining(_token), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('Stock Detail protected 401 invokes session expiry callback',
      (tester) async {
    var expiredToken = '';
    final client = MockClient((request) async => http.Response(
      '<html>STOCK-DETAIL-PRIVATE-TRACEBACK</html>', 401,
    ));
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        home: StockDetailPage(
          baseUrl: 'http://test',
          symbol: 'FPT',
          apiToken: _token,
          onSessionExpired: (token) => expiredToken = token,
        ),
      ));
      await tester.pumpAndSettle();

      expect(expiredToken, _token);
      expect(find.textContaining('STOCK-DETAIL-PRIVATE-TRACEBACK'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => client);
    client.close();
  });

  testWidgets('Analysis protected 401 invokes session expiry callback',
      (tester) async {
    var expiredToken = '';
    final client = MockClient((request) async => http.Response(
      '<html>ANALYSIS-PRIVATE-TRACEBACK</html>', 401,
    ));
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        home: AnalysisPage(
          baseUrl: 'http://test',
          symbol: 'FPT',
          apiToken: _token,
          onSessionExpired: (token) => expiredToken = token,
        ),
      ));
      await tester.pumpAndSettle();

      expect(expiredToken, _token);
      expect(find.textContaining('ANALYSIS-PRIVATE-TRACEBACK'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => client);
    client.close();
  });

  testWidgets('real Chart route returns to root Login on protected 401',
      (tester) async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/status')) {
        return _json(200, {'owner_initialized': true});
      }
      if (request.url.path.endsWith('/auth/login')) {
        return _json(200, {'access_token': _token});
      }
      if (request.url.path == '/health') {
        return _json(200, {'status': 'ok', 'version': 'test'});
      }
      if (request.url.path == '/api/v1/watchlist') {
        return _json(200, {'items': [
          {'symbol': 'FPT', 'name': 'FPT', 'exchange': 'HOSE', 'candle_count': 0}
        ]});
      }
      if (request.url.path == '/api/v1/candles/chart') {
        return http.Response('<html>CHART-ROUTE-PRIVATE-TRACEBACK</html>', 401);
      }
      fail('Unexpected request: \${request.method} \${request.url}');
    });
    await _pumpDashboard(
      tester,
      client,
      chartBuilder: (baseUrl, symbol, token, onSessionExpired) => ChartPage(
        baseUrl: baseUrl,
        symbol: symbol,
        apiToken: token,
        onSessionExpired: onSessionExpired,
        httpClient: client,
      ),
    );
    await _login(tester);
    await tester.scrollUntilVisible(
      find.text('FPT'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('FPT'));
    await tester.pumpAndSettle();

    expect(find.text('SmartStock Pro • Đăng nhập'), findsOneWidget);
    expect(find.text(
      'Phiên đăng nhập đã hết hạn hoặc bị thu hồi. Vui lòng đăng nhập lại.',
    ), findsOneWidget);
    expect(find.textContaining('CHART-ROUTE-PRIVATE-TRACEBACK'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('real Training Room route returns to root Login once on concurrent 401s',
      (tester) async {
    var trainingRequests = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/status')) {
        return _json(200, {'owner_initialized': true});
      }
      if (request.url.path.endsWith('/auth/login')) {
        return _json(200, {'access_token': _token});
      }
      if (request.url.path == '/health') {
        return _json(200, {'status': 'ok', 'version': 'test'});
      }
      if (request.url.path == '/api/v1/watchlist') {
        return _json(200, {'items': []});
      }
      if (request.url.path.startsWith('/api/v1/training/') ||
          request.url.path.startsWith('/api/v1/knowledge/')) {
        trainingRequests++;
        return http.Response('<html>TRAINING-ROUTE-PRIVATE-TRACEBACK</html>', 401);
      }
      fail('Unexpected request: \${request.method} \${request.url}');
    });
    await _pumpDashboard(
      tester,
      client,
      trainingBuilder: (baseUrl, token, onSessionExpired) => TrainingRoomPage(
        baseUrl: baseUrl,
        apiToken: token,
        onSessionExpired: onSessionExpired,
        httpClient: client,
      ),
    );
    await _login(tester);
    await tester.scrollUntilVisible(
      find.text('Hybrid AI Training Room'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Hybrid AI Training Room'));
    await tester.pumpAndSettle();

    expect(trainingRequests, greaterThan(1));
    expect(find.text('SmartStock Pro • Đăng nhập'), findsOneWidget);
    expect(find.text(
      'Phiên đăng nhập đã hết hạn hoặc bị thu hồi. Vui lòng đăng nhập lại.',
    ), findsOneWidget);
    expect(find.textContaining('TRAINING-ROUTE-PRIVATE-TRACEBACK'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('SmartStock Pro • Đăng nhập'), findsOneWidget);
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
