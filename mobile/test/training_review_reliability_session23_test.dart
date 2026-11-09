import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartstock_pro/training_room_page.dart';

const _token = 'session23-owner-token';

Map<String, dynamic> _example() => {
  'id': 21,
  'question': 'Câu hỏi kiểm thử nội dung review phiên 23',
  'expected_answer': 'Đáp án đã được xác minh bằng nguồn trích dẫn.',
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

Future<void> _pump(WidgetTester tester, MockClient client, {
  void Function(String token)? onSessionExpired,
}) async {
  await tester.pumpWidget(MaterialApp(home: TrainingRoomPage(
    baseUrl: 'http://test', apiToken: _token, httpClient: client,
    onSessionExpired: onSessionExpired,
  )));
  await tester.pumpAndSettle();
}

Future<void> _openHistory(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Lịch sử'), 250, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Lịch sử'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('401 wins over sibling TimeoutException with no raw data leak', (tester) async {
    final expired = <String>[];
    var historyRequests = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples') return _json(200, {'items': [_example()], 'total': 1});
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.url.path.endsWith('/review-events')) {
        historyRequests++;
        throw TimeoutException('PRIVATE-TIMEOUT-' + _token);
      }
      if (request.url.path.endsWith('/quality-reviews')) {
        historyRequests++;
        return http.Response('PRIVATE-401-' + _token, 401);
      }
      throw StateError('Unexpected route');
    });
    await _pump(tester, client, onSessionExpired: expired.add);
    await _openHistory(tester);
    expect(historyRequests, 2);
    expect(expired, [_token]);
    expect(find.text('Lịch sử review • ví dụ #21'), findsNothing);
    expect(find.textContaining('PRIVATE-TIMEOUT'), findsNothing);
    expect(find.textContaining('PRIVATE-401'), findsNothing);
    expect(find.textContaining(_token), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('401 wins over sibling SocketException with no raw data leak', (tester) async {
    final expired = <String>[];
    var historyRequests = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples') return _json(200, {'items': [_example()], 'total': 1});
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.url.path.endsWith('/review-events')) {
        historyRequests++;
        throw SocketException('PRIVATE-SOCKET-' + _token);
      }
      if (request.url.path.endsWith('/quality-reviews')) {
        historyRequests++;
        return http.Response('PRIVATE-401-' + _token, 401);
      }
      throw StateError('Unexpected route');
    });
    await _pump(tester, client, onSessionExpired: expired.add);
    await _openHistory(tester);
    expect(historyRequests, 2);
    expect(expired, [_token]);
    expect(find.textContaining('PRIVATE-SOCKET'), findsNothing);
    expect(find.textContaining('PRIVATE-401'), findsNothing);
    expect(find.textContaining(_token), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('late 401 is retained when sibling transport failure completes first', (tester) async {
    final expired = <String>[];
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples') return _json(200, {'items': [_example()], 'total': 1});
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.url.path.endsWith('/review-events')) {
        throw TimeoutException('PRIVATE-FIRST-FAILURE');
      }
      if (request.url.path.endsWith('/quality-reviews')) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return http.Response('PRIVATE-LATE-401', 401);
      }
      throw StateError('Unexpected route');
    });
    await _pump(tester, client, onSessionExpired: expired.add);
    await _openHistory(tester);
    expect(expired, [_token]);
    expect(find.textContaining('PRIVATE-FIRST-FAILURE'), findsNothing);
    expect(find.textContaining('PRIVATE-LATE-401'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('401 wins over sibling HTTP 500', (tester) async {
    final expired = <String>[];
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples') return _json(200, {'items': [_example()], 'total': 1});
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.url.path.endsWith('/review-events')) return http.Response('PRIVATE-500', 500);
      if (request.url.path.endsWith('/quality-reviews')) return http.Response('PRIVATE-401', 401);
      throw StateError('Unexpected route');
    });
    await _pump(tester, client, onSessionExpired: expired.add);
    await _openHistory(tester);
    expect(expired, [_token]);
    expect(find.textContaining('PRIVATE-500'), findsNothing);
    expect(find.textContaining('PRIVATE-401'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('two transport failures without 401 remain sanitized and do not expire session', (tester) async {
    var expiryCalls = 0;
    var historyRequests = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples') return _json(200, {'items': [_example()], 'total': 1});
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.url.path.endsWith('/review-events')) {
        historyRequests++;
        throw SocketException('PRIVATE-TRANSPORT-' + _token);
      }
      if (request.url.path.endsWith('/quality-reviews')) {
        historyRequests++;
        throw TimeoutException('PRIVATE-TIMEOUT-' + _token);
      }
      throw StateError('Unexpected route');
    });
    await _pump(tester, client, onSessionExpired: (_) => expiryCalls++);
    await _openHistory(tester);
    expect(historyRequests, 2);
    expect(expiryCalls, 0);
    expect(find.text('Lịch sử review • ví dụ #21'), findsNothing);
    expect(find.textContaining('PRIVATE-TRANSPORT'), findsNothing);
    expect(find.textContaining('PRIVATE-TIMEOUT'), findsNothing);
    expect(find.textContaining(_token), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('expiry callback is idempotent when both history requests return 401', (tester) async {
    final expired = <String>[];
    var historyRequests = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples') return _json(200, {'items': [_example()], 'total': 1});
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.url.path.endsWith('/review-events') || request.url.path.endsWith('/quality-reviews')) {
        historyRequests++;
        return http.Response('PRIVATE-401-' + _token, 401);
      }
      throw StateError('Unexpected route');
    });
    await _pump(tester, client, onSessionExpired: expired.add);
    await _openHistory(tester);
    expect(historyRequests, 2);
    expect(expired, [_token]);
    expect(find.textContaining('PRIVATE-401'), findsNothing);
    expect(find.textContaining(_token), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('stale-token expiry callback cannot clear a newer active session', (tester) async {
    const activeToken = 'newer-active-owner-token';
    var activeSession = true;
    final callbackTokens = <String>[];
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples') return _json(200, {'items': [_example()], 'total': 1});
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.url.path.endsWith('/review-events')) return http.Response('PRIVATE-401', 401);
      if (request.url.path.endsWith('/quality-reviews')) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
        throw SocketException('PRIVATE-SOCKET');
      }
      throw StateError('Unexpected route');
    });
    await _pump(tester, client, onSessionExpired: (token) {
      callbackTokens.add(token);
      if (token == activeToken) activeSession = false;
    });
    await _openHistory(tester);
    expect(callbackTokens, [_token]);
    expect(activeSession, isTrue);
    expect(callbackTokens.where((token) => token == activeToken), isEmpty);
    expect(find.textContaining('PRIVATE-401'), findsNothing);
    expect(find.textContaining('PRIVATE-SOCKET'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });
}
