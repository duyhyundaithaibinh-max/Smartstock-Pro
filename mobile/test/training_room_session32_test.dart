import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartstock_pro/training_room_page.dart';

const _token = 'session32-owner-token';
const _question = 'Câu hỏi kiểm thử Create/List có độ dài hợp lệ';
const _answer = 'Đáp án kiểm thử đủ độ dài và được xác minh từ nguồn hợp lệ.';

http.Response _json(int status, Object value) => http.Response(
  jsonEncode(value), status, headers: {'content-type': 'application/json'});

Map<String, dynamic> _evaluation({int total = 0, int draft = 0, int approved = 0}) => {
  'total_examples': total, 'approved_examples': approved,
  'draft_examples': draft, 'rejected_examples': total - draft - approved,
  'duplicate_question_groups': 0,
  'readiness': 'collect_and_review_more_examples',
};

Map<String, dynamic> _example({int id = 41, String status = 'draft'}) => {
  'id': id, 'question': _question, 'expected_answer': _answer,
  'topic': 'fibonacci', 'citation_ids': ['kb:7:2'],
  'status': status, 'revision': 1,
};

Map<String, dynamic> _list(List<dynamic> items) =>
    {'items': items, 'total': items.length, 'limit': 100, 'offset': 0};

Future<void> _pump(WidgetTester tester, MockClient client, {
  void Function(String token)? onSessionExpired,
}) async {
  await tester.pumpWidget(MaterialApp(home: TrainingRoomPage(
    baseUrl: 'http://test', apiToken: _token, httpClient: client,
    onSessionExpired: onSessionExpired,
  )));
  await tester.pumpAndSettle();
}

Future<void> _fillCreate(WidgetTester tester) async {
  final values = <String, String>{
    'training-create-question': _question,
    'training-create-answer': _answer,
    'training-create-topic': 'fibonacci',
    'training-create-citations': 'kb:7:2',
  };
  for (final entry in values.entries) {
    final finder = find.byKey(ValueKey(entry.key));
    await tester.ensureVisible(finder);
    await tester.enterText(finder, entry.value);
  }
  await tester.ensureVisible(find.byKey(const ValueKey('training-create-submit')));
}

Future<void> _showApprove(WidgetTester tester, int id) async {
  final finder = find.byKey(ValueKey('training-approve-$id'));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final transport in ['timeout', 'socket']) {
    for (final unauthorizedEndpoint in ['examples', 'evaluation']) {
      for (final transportFirst in [true, false]) {
        testWidgets(
          'training loader prioritizes 401 over $transport on $unauthorizedEndpoint '
          'with transportFirst=$transportFirst',
          (tester) async {
            final list = Completer<http.Response>();
            final evaluation = Completer<http.Response>();
            var listCalls = 0;
            var evaluationCalls = 0;
            final expired = <String>[];
            final client = MockClient((request) async {
              if (request.url.path == '/api/v1/knowledge/documents') {
                return _json(200, {'items': []});
              }
              if (request.url.path == '/api/v1/training/examples') {
                listCalls++;
                return list.future;
              }
              if (request.url.path == '/api/v1/training/evaluation') {
                evaluationCalls++;
                return evaluation.future;
              }
              fail('Unexpected request: ${request.method} ${request.url}');
            });
            await tester.pumpWidget(MaterialApp(home: TrainingRoomPage(
              baseUrl: 'http://test', apiToken: _token, httpClient: client,
              onSessionExpired: expired.add,
            )));
            await tester.pump();
            expect(listCalls, 1);
            expect(evaluationCalls, 1);
            final unauthorized = _json(401, {'detail': 'PRIVATE_401_RESPONSE'});
            final transportError = transport == 'timeout'
                ? TimeoutException('PRIVATE_TIMEOUT_MARKER')
                : const SocketException('PRIVATE_SOCKET_MARKER');
            final unauthorizedCompleter =
                unauthorizedEndpoint == 'examples' ? list : evaluation;
            final failedCompleter =
                unauthorizedEndpoint == 'examples' ? evaluation : list;
            if (transportFirst) {
              failedCompleter.completeError(transportError);
              await tester.pump();
              unauthorizedCompleter.complete(unauthorized);
            } else {
              unauthorizedCompleter.complete(unauthorized);
              await tester.pump();
              failedCompleter.completeError(transportError);
            }
            await tester.pumpAndSettle();
            expect(expired, [_token]);
            expect(listCalls, 1);
            expect(evaluationCalls, 1);
            expect(find.textContaining('PRIVATE_'), findsNothing);
            expect(find.textContaining(_token), findsNothing);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
            client.close();
          },
        );
      }
    }
  }

  for (final transportFirst in [true, false]) {
    testWidgets('training loader suppresses late 401 after unmount '
        'transportFirst=$transportFirst', (tester) async {
      final list = Completer<http.Response>();
      final evaluation = Completer<http.Response>();
      final expired = <String>[];
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/knowledge/documents') {
          return _json(200, {'items': []});
        }
        if (request.url.path == '/api/v1/training/examples') return list.future;
        if (request.url.path == '/api/v1/training/evaluation') return evaluation.future;
        fail('Unexpected request: ${request.method} ${request.url}');
      });
      await tester.pumpWidget(MaterialApp(home: TrainingRoomPage(
        baseUrl: 'http://test', apiToken: _token, httpClient: client,
        onSessionExpired: expired.add,
      )));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      if (transportFirst) {
        list.completeError(TimeoutException('PRIVATE_UNMOUNT_TIMEOUT'));
        await tester.pump();
        evaluation.complete(_json(401, {'detail': 'PRIVATE_UNMOUNT_401'}));
      } else {
        evaluation.complete(_json(401, {'detail': 'PRIVATE_UNMOUNT_401'}));
        await tester.pump();
        list.completeError(const SocketException('PRIVATE_UNMOUNT_SOCKET'));
      }
      await tester.pumpAndSettle();
      expect(expired, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    });
  }

  testWidgets('training loader keeps session on transport errors and retry reloads list', (tester) async {
    var listCalls = 0;
    var evaluationCalls = 0;
    final expired = <String>[];
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples') {
        listCalls++;
        if (listCalls == 1) throw TimeoutException('PRIVATE_TIMEOUT');
        return _json(200, _list([_example()]));
      }
      if (request.url.path == '/api/v1/training/evaluation') {
        evaluationCalls++;
        if (evaluationCalls == 1) throw const SocketException('PRIVATE_SOCKET');
        return _json(200, _evaluation(total: 1, draft: 1));
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    await _pump(tester, client, onSessionExpired: expired.add);
    expect(listCalls, 1);
    expect(evaluationCalls, 1);
    expect(expired, isEmpty);
    expect(find.byKey(const ValueKey('training-data-retry')), findsOneWidget);
    expect(find.textContaining('PRIVATE_'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('training-data-retry')));
    await tester.pumpAndSettle();
    expect(listCalls, 2);
    expect(evaluationCalls, 2);
    expect(expired, isEmpty);
    expect(find.text(_question), findsOneWidget);
    expect(find.textContaining('Tổng: 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('create trims owner payload and refreshes list after 201', (tester) async {
    var listCalls = 0;
    http.Request? createRequest;
    final created = _example();
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples' && request.method == 'GET') {
        listCalls++;
        return _json(200, _list(listCalls == 1 ? [] : [created]));
      }
      if (request.url.path == '/api/v1/training/evaluation') {
        return _json(200, _evaluation(total: listCalls > 1 ? 1 : 0, draft: listCalls > 1 ? 1 : 0));
      }
      if (request.url.path == '/api/v1/training/examples' && request.method == 'POST') {
        createRequest = request;
        return _json(201, created);
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    await _pump(tester, client);
    await _fillCreate(tester);
    await tester.tap(find.byKey(const ValueKey('training-create-submit')));
    await tester.pumpAndSettle();
    expect(createRequest, isNotNull);
    expect(createRequest!.method, 'POST');
    expect(createRequest!.url.path, '/api/v1/training/examples');
    expect(createRequest!.headers['authorization'], 'Bearer $_token');
    expect(createRequest!.headers['content-type'], contains('application/json'));
    expect(jsonDecode(createRequest!.body), {
      'question': _question, 'expected_answer': _answer,
      'topic': 'fibonacci', 'citation_ids': ['kb:7:2'],
    });
    expect(listCalls, 2);
    expect(find.text(_question), findsOneWidget);
    expect(find.text('Chờ duyệt'), findsOneWidget);
    expect(find.textContaining('Tổng: 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('create pending request blocks duplicate taps', (tester) async {
    final pending = Completer<http.Response>();
    var postCount = 0;
    var listCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples' && request.method == 'GET') {
        listCalls++;
        return _json(200, _list(listCalls == 1 ? [] : [_example()]));
      }
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation(total: listCalls > 1 ? 1 : 0, draft: listCalls > 1 ? 1 : 0));
      if (request.url.path == '/api/v1/training/examples' && request.method == 'POST') {
        postCount++;
        return pending.future;
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    await _pump(tester, client);
    await _fillCreate(tester);
    final submit = find.byKey(const ValueKey('training-create-submit'));
    await tester.tap(submit);
    await tester.pump();
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.tap(submit, warnIfMissed: false);
    await tester.pump();
    expect(postCount, 1);
    pending.complete(_json(201, _example()));
    await tester.pumpAndSettle();
    expect(listCalls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('create 500 is sanitized, retains fields and permits retry', (tester) async {
    var postCount = 0;
    var listCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples' && request.method == 'GET') {
        listCalls++;
        return _json(200, _list(listCalls == 1 ? [] : [_example()]));
      }
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation(total: listCalls > 1 ? 1 : 0, draft: listCalls > 1 ? 1 : 0));
      if (request.url.path == '/api/v1/training/examples' && request.method == 'POST') {
        postCount++;
        if (postCount == 1) return http.Response('PRIVATE_CREATE_500_BODY', 500);
        return _json(201, _example());
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    await _pump(tester, client);
    await _fillCreate(tester);
    final submit = find.byKey(const ValueKey('training-create-submit'));
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(postCount, 1);
    expect(find.textContaining('PRIVATE_CREATE_500_BODY'), findsNothing);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('training-create-question'))).controller!.text, _question);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(postCount, 2);
    expect(listCalls, 2);
    expect(find.text(_question), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('create 401 expires owner session once and blocks further POST', (tester) async {
    var postCount = 0;
    final expired = <String>[];
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples') return _json(200, _list([]));
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.method == 'POST' && request.url.path == '/api/v1/training/examples') {
        postCount++;
        return http.Response('PRIVATE_CREATE_401_BODY', 401);
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    await _pump(tester, client, onSessionExpired: expired.add);
    await _fillCreate(tester);
    final submit = find.byKey(const ValueKey('training-create-submit'));
    await tester.tap(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(postCount, 1);
    expect(expired, [_token]);
    expect(find.textContaining('PRIVATE_CREATE_401_BODY'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('approve posts once with owner token and refreshes row after 200', (tester) async {
    var listCalls = 0;
    http.Request? approveRequest;
    var current = _example();
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples' && request.method == 'GET') {
        listCalls++;
        return _json(200, _list([current]));
      }
      if (request.url.path == '/api/v1/training/evaluation') {
        return _json(200, _evaluation(total: 1, draft: current['status'] == 'draft' ? 1 : 0, approved: current['status'] == 'approved' ? 1 : 0));
      }
      if (request.method == 'POST' && request.url.path == '/api/v1/training/examples/41/approve') {
        approveRequest = request;
        current = _example(status: 'approved');
        return _json(200, current);
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    await _pump(tester, client);
    await _showApprove(tester, 41);
    await tester.tap(find.byKey(const ValueKey('training-approve-41')));
    await tester.pumpAndSettle();
    expect(approveRequest, isNotNull);
    expect(approveRequest!.method, 'POST');
    expect(approveRequest!.url.path, '/api/v1/training/examples/41/approve');
    expect(approveRequest!.headers['authorization'], 'Bearer $_token');
    expect(approveRequest!.body, isEmpty);
    expect(listCalls, 2);
    expect(find.text('Đã duyệt'), findsOneWidget);
    expect(find.text('Duyệt'), findsNothing);
    expect(find.textContaining('Đã duyệt: 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('approve pending request blocks duplicate taps', (tester) async {
    final pending = Completer<http.Response>();
    var postCount = 0;
    var listCalls = 0;
    var current = _example();
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples' && request.method == 'GET') {
        listCalls++;
        return _json(200, _list([current]));
      }
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation(total: 1, draft: 1));
      if (request.method == 'POST' && request.url.path.endsWith('/41/approve')) {
        postCount++;
        return pending.future;
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    await _pump(tester, client);
    await _showApprove(tester, 41);
    final approve = find.byKey(const ValueKey('training-approve-41'));
    await tester.tap(approve);
    await tester.pump();
    expect(tester.widget<TextButton>(approve).onPressed, isNull);
    await tester.tap(approve, warnIfMissed: false);
    await tester.pump();
    expect(postCount, 1);
    current = _example(status: 'approved');
    pending.complete(_json(200, current));
    await tester.pumpAndSettle();
    expect(listCalls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('approve 500 is sanitized and permits deliberate retry', (tester) async {
    var postCount = 0;
    var listCalls = 0;
    var current = _example();
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples' && request.method == 'GET') {
        listCalls++;
        return _json(200, _list([current]));
      }
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation(total: 1, draft: current['status'] == 'draft' ? 1 : 0, approved: current['status'] == 'approved' ? 1 : 0));
      if (request.method == 'POST' && request.url.path.endsWith('/41/approve')) {
        postCount++;
        if (postCount == 1) return http.Response('PRIVATE_APPROVE_500_BODY', 500);
        current = _example(status: 'approved');
        return _json(200, current);
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    await _pump(tester, client);
    await _showApprove(tester, 41);
    final approve = find.byKey(const ValueKey('training-approve-41'));
    await tester.tap(approve);
    await tester.pumpAndSettle();
    expect(postCount, 1);
    expect(find.textContaining('PRIVATE_APPROVE_500_BODY'), findsNothing);
    await _showApprove(tester, 41);
    await tester.tap(approve);
    await tester.pumpAndSettle();
    expect(postCount, 2);
    expect(listCalls, 2);
    expect(find.text('Đã duyệt'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('approve 409 refreshes authoritative state without blind retry', (tester) async {
    var postCount = 0;
    var listCalls = 0;
    var evaluationCalls = 0;
    var current = _example();
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples' && request.method == 'GET') {
        listCalls++;
        return _json(200, _list([current]));
      }
      if (request.url.path == '/api/v1/training/evaluation') {
        evaluationCalls++;
        return _json(200, _evaluation(total: 1, draft: current['status'] == 'draft' ? 1 : 0, approved: current['status'] == 'approved' ? 1 : 0));
      }
      if (request.method == 'POST' && request.url.path.endsWith('/41/approve')) {
        postCount++;
        current = _example(status: 'approved');
        return http.Response('PRIVATE_APPROVE_CONFLICT', 409);
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    await _pump(tester, client);
    await _showApprove(tester, 41);
    await tester.tap(find.byKey(const ValueKey('training-approve-41')));
    await tester.pumpAndSettle();
    expect(postCount, 1);
    expect(listCalls, 2);
    expect(evaluationCalls, 2);
    expect(find.text('Đã duyệt'), findsOneWidget);
    expect(find.text('Duyệt'), findsNothing);
    expect(find.textContaining('đã được xử lý ở nơi khác'), findsOneWidget);
    expect(find.textContaining('PRIVATE_APPROVE_CONFLICT'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('approve 401 expires owner session once and suppresses another POST', (tester) async {
    var postCount = 0;
    final expired = <String>[];
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples') return _json(200, _list([_example()]));
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation(total: 1, draft: 1));
      if (request.method == 'POST' && request.url.path.endsWith('/41/approve')) {
        postCount++;
        return http.Response('PRIVATE_APPROVE_401_BODY', 401);
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    await _pump(tester, client, onSessionExpired: expired.add);
    await _showApprove(tester, 41);
    final approve = find.byKey(const ValueKey('training-approve-41'));
    await tester.tap(approve);
    await tester.pumpAndSettle();
    await tester.tap(approve);
    await tester.pumpAndSettle();
    expect(postCount, 1);
    expect(expired, [_token]);
    expect(find.textContaining('PRIVATE_APPROVE_401_BODY'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });
}
