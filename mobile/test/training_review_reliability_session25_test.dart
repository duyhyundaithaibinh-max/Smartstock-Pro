// ignore_for_file: prefer_interpolation_to_compose_strings, prefer_const_constructors

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartstock_pro/main.dart' show DashboardPage;
import 'package:smartstock_pro/training_room_page.dart';

const _oldToken = 'session25-old-owner-token';
const _newToken = 'session25-new-owner-token';

Map<String, dynamic> _example() => {
  'id': 21,
  'question': 'Câu hỏi kiểm thử phiên 25',
  'expected_answer': 'Đáp án kiểm thử',
  'topic': 'technical_analysis',
  'citation_ids': ['kb:8:3'],
  'status': 'approved',
  'revision': 1,
};

http.Response _json(int status, Object value) => http.Response(
  jsonEncode(value), status, headers: {'content-type': 'application/json'});

Map<String, dynamic> _evaluation() => {
  'total_examples': 1, 'approved_examples': 1, 'draft_examples': 0,
  'rejected_examples': 0, 'duplicate_question_groups': 0,
  'readiness': 'collect_and_review_more_examples',
};

Future<void> _pumpTraining(WidgetTester tester, MockClient client, {
  void Function(String token)? onExpired,
}) async {
  await tester.pumpWidget(MaterialApp(home: TrainingRoomPage(
    baseUrl: 'http://test', apiToken: _oldToken, httpClient: client,
    onSessionExpired: onExpired,
  )));
  await tester.pumpAndSettle();
}

Future<void> _startHistory(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.text('Lịch sử'), 250,
    scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Lịch sử'));
  await tester.pump();
}

void main() {
  testWidgets('401 completes first and remains authoritative over late TimeoutException',
      (tester) async {
    final events = Completer<http.Response>();
    final quality = Completer<http.Response>();
    final expired = <String>[];
    var eventRequests = 0;
    var qualityRequests = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples') return _json(200, {'items': [_example()], 'total': 1});
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.url.path.endsWith('/review-events')) { eventRequests++; return events.future; }
      if (request.url.path.endsWith('/quality-reviews')) { qualityRequests++; return quality.future; }
      throw StateError('Unexpected route');
    });
    await _pumpTraining(tester, client, onExpired: expired.add);
    await _startHistory(tester);
    expect(eventRequests, 1);
    expect(qualityRequests, 1);
    expect(eventRequests + qualityRequests, 2);
    events.complete(http.Response('PRIVATE-EARLY-401-$_oldToken', 401));
    await tester.pump();
    expect(expired, isEmpty); // Future.wait waits for the sibling result.
    quality.completeError(TimeoutException('PRIVATE-LATE-TIMEOUT-$_oldToken'));
    await tester.pumpAndSettle();
    expect(expired, [_oldToken]);
    expect(expired.length, 1);
    expect(find.text('Lịch sử review • ví dụ #21'), findsNothing);
    expect(find.textContaining('PRIVATE-EARLY-401'), findsNothing);
    expect(find.textContaining('PRIVATE-LATE-TIMEOUT'), findsNothing);
    expect(find.textContaining(_oldToken), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('401 completes first and remains authoritative over late SocketException',
      (tester) async {
    final events = Completer<http.Response>();
    final quality = Completer<http.Response>();
    final expired = <String>[];
    var requests = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples') return _json(200, {'items': [_example()], 'total': 1});
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.url.path.endsWith('/review-events')) { requests++; return events.future; }
      if (request.url.path.endsWith('/quality-reviews')) { requests++; return quality.future; }
      throw StateError('Unexpected route');
    });
    await _pumpTraining(tester, client, onExpired: expired.add);
    await _startHistory(tester);
    expect(requests, 2);
    quality.complete(http.Response('PRIVATE-401-$_oldToken', 401));
    await tester.pump();
    expect(expired, isEmpty);
    events.completeError(const SocketException('PRIVATE-LATE-SOCKET'));
    await tester.pumpAndSettle();
    expect(expired, [_oldToken]);
    expect(expired.length, 1);
    expect(find.textContaining('PRIVATE-401'), findsNothing);
    expect(find.textContaining('PRIVATE-LATE-SOCKET'), findsNothing);
    expect(find.textContaining(_oldToken), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('unmount while history requests pending suppresses late 401 callback and errors',
      (tester) async {
    final events = Completer<http.Response>();
    final quality = Completer<http.Response>();
    var requests = 0;
    var expiryCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples') return _json(200, {'items': [_example()], 'total': 1});
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.url.path.endsWith('/review-events')) { requests++; return events.future; }
      if (request.url.path.endsWith('/quality-reviews')) { requests++; return quality.future; }
      throw StateError('Unexpected route');
    });
    await _pumpTraining(tester, client, onExpired: (_) => expiryCalls++);
    await _startHistory(tester);
    expect(requests, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    events.complete(http.Response('PRIVATE-401-$_oldToken', 401));
    quality.completeError(const SocketException('PRIVATE-UNMOUNT-SOCKET'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(expiryCalls, 0);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('PRIVATE-401'), findsNothing);
    expect(find.textContaining('PRIVATE-UNMOUNT-SOCKET'), findsNothing);
    expect(find.textContaining(_oldToken), findsNothing);
    client.close();
  });

  testWidgets('transport failures without 401 restore loading and show only safe fallback',
      (tester) async {
    var requests = 0;
    var expiryCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples') return _json(200, {'items': [_example()], 'total': 1});
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.url.path.endsWith('/review-events')) { requests++; throw TimeoutException('PRIVATE-TIMEOUT-$_oldToken'); }
      if (request.url.path.endsWith('/quality-reviews')) { requests++; throw const SocketException('PRIVATE-SOCKET'); }
      throw StateError('Unexpected route');
    });
    await _pumpTraining(tester, client, onExpired: (_) => expiryCalls++);
    await _startHistory(tester);
    await tester.pumpAndSettle();
    expect(requests, 2);
    expect(expiryCalls, 0);
    expect(find.text('Lịch sử review • ví dụ #21'), findsNothing);
    expect(find.text('Không thể kết nối máy chủ. Vui lòng kiểm tra mạng và thử lại.'), findsOneWidget);
    expect(find.textContaining('PRIVATE-TIMEOUT'), findsNothing);
    expect(find.textContaining('PRIVATE-SOCKET'), findsNothing);
    expect(find.textContaining(_oldToken), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('real Dashboard session guard ignores callback from previous login token',
      (tester) async {
    var loginCount = 0;
    void Function(String token)? oldSessionExpiry;
    final client = MockClient((request) async {
      switch (request.url.path) {
        case '/api/v1/auth/status':
          return _json(200, {'owner_initialized': true});
        case '/api/v1/auth/login':
          loginCount++;
          return _json(200, {'access_token': loginCount == 1 ? _oldToken : _newToken});
        case '/health':
          return _json(200, {'status': 'ok', 'version': 'test'});
        case '/api/v1/watchlist':
          return _json(200, {'items': []});
        case '/api/v1/auth/logout':
          return _json(204, {});
        default:
          throw StateError('Unexpected route: ${request.url.path}');
      }
    });
    await tester.pumpWidget(MaterialApp(home: DashboardPage(
      httpClient: client,
      trainingRoomPageBuilder: (baseUrl, token, onExpired) {
        oldSessionExpiry ??= onExpired;
        return const Scaffold(body: Text('Training callback capture'));
      },
    )));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('username')), 'owner');
    await tester.enterText(find.byKey(const ValueKey('password')), 'password-one');
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Danh sách theo dõi'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Hybrid AI Training Room'), 250,
      scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Hybrid AI Training Room'));
    await tester.pumpAndSettle();
    expect(oldSessionExpiry, isNotNull);
    Navigator.of(tester.element(find.text('Training callback capture'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('logout')));
    await tester.pumpAndSettle();
    expect(find.text('SmartStock Pro • Đăng nhập'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('username')), 'owner');
    await tester.enterText(find.byKey(const ValueKey('password')), 'password-two');
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    await tester.pumpAndSettle();
    expect(loginCount, 2);
    expect(find.text('Danh sách theo dõi'), findsOneWidget);
    oldSessionExpiry!(_oldToken);
    await tester.pumpAndSettle();
    expect(find.text('Danh sách theo dõi'), findsOneWidget);
    expect(find.text('SmartStock Pro • Đăng nhập'), findsNothing);
    expect(find.textContaining('Phiên đăng nhập đã hết hạn'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });
}
