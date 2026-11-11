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
  'status': status, 'created_at': '2026-01-15T10:30:00Z', 'revision': 1,
};

Map<String, dynamic> _list(
  List<dynamic> items, {
  int limit = 100,
  int offset = 0,
  int? total,
}) => {
  'items': items,
  'total': total ?? items.length,
  'limit': limit,
  'offset': offset,
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

Future<void> _fillCreate(WidgetTester tester) async {
  final values = <String, String>{
    'training-create-question': '  $_question  ',
    'training-create-answer': '  $_answer  ',
    'training-create-topic': ' fibonacci ',
    'training-create-citations': ' kb:7:2 ',
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
            expect(find.textContaining('Không tải được bộ dữ liệu huấn luyện'), findsNothing);
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
    final retry = find.byKey(const ValueKey('training-data-retry'));
    await tester.ensureVisible(retry);
    await tester.pumpAndSettle();
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(listCalls, 2);
    expect(evaluationCalls, 2);
    expect(expired, isEmpty);
    expect(find.text(_question), findsOneWidget);
    expect(find.textContaining('Tổng: 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('create rejects invalid and duplicate citation payloads without POST', (tester) async {
    var postCount = 0;
    final expired = <String>[];
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples' && request.method == 'GET') return _json(200, _list([]));
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.method == 'POST' && request.url.path == '/api/v1/training/examples') {
        postCount++;
        return _json(201, _example());
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    await _pump(tester, client, onSessionExpired: expired.add);
    final cases = <Map<String, String>>[
      {'question': 'short', 'answer': _answer, 'citations': 'kb:7:2'},
      {'question': _question, 'answer': 'short answer', 'citations': 'kb:7:2'},
      {'question': _question, 'answer': _answer, 'citations': ''},
      {'question': _question, 'answer': _answer, 'citations': 'not-a-citation'},
      {'question': _question, 'answer': _answer, 'citations': 'kb:7:2, kb:7:2'},
      {'question': _question, 'answer': _answer,
        'citations': List.generate(11, (i) => 'kb:${i + 1}:0').join(', ')},
    ];
    for (final value in cases) {
      for (final entry in <String, String>{
        'training-create-question': value['question']!,
        'training-create-answer': value['answer']!,
        'training-create-topic': 'fibonacci',
        'training-create-citations': value['citations']!,
      }.entries) {
        final field = find.byKey(ValueKey(entry.key));
        await tester.ensureVisible(field);
        await tester.enterText(field, entry.value);
      }
      final submit = find.byKey(const ValueKey('training-create-submit'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(postCount, 0);
      expect(find.byKey(const ValueKey('training-create-error')), findsOneWidget);
      expect(find.textContaining('Câu hỏi cần'), findsOneWidget);
    }
    expect(expired, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('create 422 is sanitized and retains the draft for a deliberate retry', (tester) async {
    var postCount = 0;
    var listCalls = 0;
    final expired = <String>[];
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples' && request.method == 'GET') {
        listCalls++;
        final limit = int.parse(request.url.queryParameters['limit']!);
        final offset = int.parse(request.url.queryParameters['offset']!);
        return _json(200, _list(
          listCalls == 1 ? [] : [_example()],
          limit: limit,
          offset: offset,
        ));
      }
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation(total: listCalls > 1 ? 1 : 0, draft: listCalls > 1 ? 1 : 0));
      if (request.method == 'POST' && request.url.path == '/api/v1/training/examples') {
        postCount++;
        if (postCount == 1) return http.Response('PRIVATE_CREATE_422_BODY', 422);
        return _json(201, _example());
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    await _pump(tester, client, onSessionExpired: expired.add);
    await _fillCreate(tester);
    final submit = find.byKey(const ValueKey('training-create-submit'));
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(postCount, 1);
    expect(expired, isEmpty);
    expect(find.textContaining('PRIVATE_CREATE_422_BODY'), findsNothing);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('training-create-question'))).controller!.text, '  $_question  ');
    expect(find.text('Đã lưu ví dụ ở trạng thái chờ duyệt.'), findsNothing);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(postCount, 2);
    expect(listCalls, 4);
    expect(find.text(_question), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('list requests exact owner page and renders draft approved rejected states', (tester) async {
    http.Request? listRequest;
    http.Request? evaluationRequest;
    final items = <Map<String, dynamic>>[
      {..._example(id: 41), 'question': 'Draft row unique question'},
      {..._example(id: 42, status: 'approved'), 'question': 'Approved row unique question'},
      {..._example(id: 43, status: 'rejected'), 'question': 'Rejected row unique question'},
    ];
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples') {
        listRequest = request;
        return _json(200, _list(items));
      }
      if (request.url.path == '/api/v1/training/evaluation') {
        evaluationRequest = request;
        return _json(200, _evaluation(total: 3, draft: 1, approved: 1));
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    await _pump(tester, client);
    expect(listRequest, isNotNull);
    expect(listRequest!.method, 'GET');
    expect(listRequest!.url.path, '/api/v1/training/examples');
    expect(listRequest!.url.queryParameters, {'limit': '100', 'offset': '0'});
    expect(listRequest!.headers['authorization'], 'Bearer $_token');
    expect(evaluationRequest, isNotNull);
    expect(evaluationRequest!.method, 'GET');
    expect(evaluationRequest!.url.path, '/api/v1/training/evaluation');
    expect(evaluationRequest!.headers['authorization'], 'Bearer $_token');
    expect(find.text('Draft row unique question'), findsOneWidget);
    expect(find.text('Approved row unique question'), findsOneWidget);
    expect(find.text('Rejected row unique question'), findsOneWidget);
    expect(find.text('Chờ duyệt'), findsOneWidget);
    expect(find.text('Đã duyệt'), findsOneWidget);
    expect(find.text('Đã từ chối'), findsOneWidget);
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
        final limit = int.parse(request.url.queryParameters['limit']!);
        final offset = int.parse(request.url.queryParameters['offset']!);
        return _json(200, _list(
          listCalls == 1 ? [] : [created],
          limit: limit,
          offset: offset,
        ));
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
    expect(find.textContaining('Chưa có ví dụ huấn luyện.'), findsOneWidget);
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
    expect(listCalls, 3);
    expect(find.text(_question), findsOneWidget);
    expect(find.text('Chờ duyệt'), findsOneWidget);
    expect(find.textContaining('Tổng: 1'), findsOneWidget);
    expect(find.textContaining('ID 41'), findsOneWidget);
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
        final limit = int.parse(request.url.queryParameters['limit']!);
        final offset = int.parse(request.url.queryParameters['offset']!);
        return _json(200, _list(
          listCalls == 1 ? [] : [_example()],
          limit: limit,
          offset: offset,
        ));
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
    expect(listCalls, 3);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('create 500 locks POST until GET reconciliation and explicit retry confirmation', (tester) async {
    var postCount = 0;
    var baselineCalls = 0;
    var listRefreshCalls = 0;
    var evaluationCalls = 0;
    final postBodies = <String>[];
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples' && request.method == 'GET') {
        final limit = int.parse(request.url.queryParameters['limit']!);
        final offset = int.parse(request.url.queryParameters['offset']!);
        if (limit == 500) {
          baselineCalls++;
          return _json(200, _list([], limit: 500, offset: offset));
        }
        listRefreshCalls++;
        return _json(200, _list(listRefreshCalls == 1 ? [] : [_example()], limit: limit, offset: offset));
      }
      if (request.url.path == '/api/v1/training/evaluation') {
        evaluationCalls++;
        return _json(200, _evaluation(total: listRefreshCalls > 1 ? 1 : 0, draft: listRefreshCalls > 1 ? 1 : 0));
      }
      if (request.method == 'POST' && request.url.path == '/api/v1/training/examples') {
        postCount++;
        postBodies.add(request.body);
        if (postCount == 1) return http.Response('PRIVATE_CREATE_500_BODY', 500);
        return _json(201, _example(id: 42));
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    await _pump(tester, client);
    await _fillCreate(tester);
    final submit = find.byKey(const ValueKey('training-create-submit'));
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(postCount, 1);
    expect(baselineCalls, 1);
    expect(find.textContaining('PRIVATE_CREATE_500_BODY'), findsNothing);
    expect(find.text('Kết quả gửi chưa xác định'), findsOneWidget);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('training-create-question'))).controller!.text, '  $_question  ');

    final reconcile = find.byKey(const ValueKey('training-create-reconcile'));
    await tester.ensureVisible(reconcile);
    await tester.tap(reconcile);
    await tester.pumpAndSettle();
    expect(postCount, 1);
    expect(baselineCalls, 2);
    expect(find.text('Không tìm thấy bản ghi mới trong snapshot'), findsOneWidget);
    expect(find.textContaining('không chứng minh'), findsOneWidget);
    expect(evaluationCalls, 1); // Reconciliation is List-only; no Evaluation GET.

    final review = find.byKey(const ValueKey('training-create-retry-review'));
    await tester.ensureVisible(review);
    await tester.tap(review);
    await tester.pumpAndSettle();
    expect(find.textContaining('yêu cầu cũ muộn'), findsOneWidget);
    expect(postCount, 1);
    await tester.tap(find.byKey(const ValueKey('training-create-retry-confirm')));
    await tester.pumpAndSettle();
    expect(postCount, 2);
    expect(baselineCalls, 3);
    expect(postBodies[0], postBodies[1]);
    expect(find.textContaining('Đã lưu ví dụ ở trạng thái chờ duyệt'), findsOneWidget);
    expect(evaluationCalls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('create 500 after commit is shown as a possible match, never auto-retried', (tester) async {
    var postCount = 0;
    var baselineCalls = 0;
    var rowExists = false;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples' && request.method == 'GET') {
        final limit = int.parse(request.url.queryParameters['limit']!);
        final offset = int.parse(request.url.queryParameters['offset']!);
        if (limit == 500) {
          baselineCalls++;
          return _json(200, _list(rowExists ? [_example(id: 77)] : [], limit: 500, offset: offset));
        }
        return _json(200, _list([], limit: limit, offset: offset));
      }
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.method == 'POST' && request.url.path == '/api/v1/training/examples') {
        postCount++;
        rowExists = true;
        return http.Response('PRIVATE_RESPONSE_LOST_AFTER_COMMIT', 500);
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    await _pump(tester, client);
    await _fillCreate(tester);
    await tester.tap(find.byKey(const ValueKey('training-create-submit')));
    await tester.pumpAndSettle();
    expect(postCount, 1);
    expect(baselineCalls, 1);
    await tester.ensureVisible(find.byKey(const ValueKey('training-create-reconcile')));
    await tester.tap(find.byKey(const ValueKey('training-create-reconcile')));
    await tester.pumpAndSettle();
    expect(postCount, 1);
    expect(find.text('Có bản ghi có khả năng khớp'), findsOneWidget);
    expect(find.byKey(const ValueKey('training-create-match-77')), findsOneWidget);
    expect(find.byKey(const ValueKey('training-create-retry-review')), findsNothing);
    expect(find.textContaining('không chứng minh chắc chắn'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  for (final transport in ['timeout', 'socket', 'client']) {
    testWidgets('Create $transport after dispatch enters unknown outcome and retains payload', (tester) async {
      var postCount = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
        if (request.url.path == '/api/v1/training/examples' && request.method == 'GET') {
          final limit = int.parse(request.url.queryParameters['limit']!);
          final offset = int.parse(request.url.queryParameters['offset']!);
          return _json(200, _list([], limit: limit, offset: offset));
        }
        if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
        if (request.method == 'POST' && request.url.path == '/api/v1/training/examples') {
          postCount++;
          if (transport == 'timeout') throw TimeoutException('PRIVATE_TIMEOUT');
          if (transport == 'socket') throw const SocketException('PRIVATE_SOCKET');
          throw http.ClientException('PRIVATE_CONNECTION_RESET');
        }
        fail('Unexpected request: ${request.method} ${request.url}');
      });
      await _pump(tester, client);
      await _fillCreate(tester);
      await tester.tap(find.byKey(const ValueKey('training-create-submit')));
      await tester.pumpAndSettle();
      expect(postCount, 1);
      expect(find.text('Kết quả gửi chưa xác định'), findsOneWidget);
      expect(find.textContaining('PRIVATE_'), findsNothing);
      final question = tester.widget<TextField>(
        find.byKey(const ValueKey('training-create-question')),
      );
      expect(question.enabled, isFalse);
      expect(question.controller!.text, '  $_question  ');
      expect(tester.widget<FilledButton>(
        find.byKey(const ValueKey('training-create-submit')),
      ).onPressed, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    });
  }

  testWidgets('Create reconciliation failure keeps POST locked and retries GET only', (tester) async {
    var postCount = 0;
    var reconcileCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples' && request.method == 'GET') {
        final limit = int.parse(request.url.queryParameters['limit']!);
        final offset = int.parse(request.url.queryParameters['offset']!);
        if (limit == 500) {
          reconcileCalls++;
          if (reconcileCalls == 2) return http.Response('PRIVATE_LIST_500', 500);
          return _json(200, _list([], limit: limit, offset: offset));
        }
        return _json(200, _list([], limit: limit, offset: offset));
      }
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.method == 'POST' && request.url.path == '/api/v1/training/examples') {
        postCount++;
        return http.Response('PRIVATE_CREATE_500', 500);
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    await _pump(tester, client);
    await _fillCreate(tester);
    await tester.tap(find.byKey(const ValueKey('training-create-submit')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('training-create-reconcile')));
    await tester.tap(find.byKey(const ValueKey('training-create-reconcile')));
    await tester.pumpAndSettle();
    expect(find.text('Chưa đối soát đầy đủ'), findsOneWidget);
    expect(postCount, 1);
    final reconcile = find.byKey(const ValueKey('training-create-reconcile'));
    await tester.ensureVisible(reconcile);
    await tester.tap(reconcile);
    await tester.pumpAndSettle();
    expect(reconcileCalls, 3);
    expect(postCount, 1);
    expect(find.text('Không tìm thấy bản ghi mới trong snapshot'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  for (final candidateCount in [1, 2]) {
    testWidgets('Create reconciliation reports $candidateCount matching candidate(s) without retry', (tester) async {
      var postCount = 0;
      var reconcileCalls = 0;
      final rows = List<Map<String, dynamic>>.generate(
        candidateCount,
        (index) => _example(id: 80 + index),
      );
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
        if (request.url.path == '/api/v1/training/examples' && request.method == 'GET') {
          final limit = int.parse(request.url.queryParameters['limit']!);
          final offset = int.parse(request.url.queryParameters['offset']!);
          if (limit == 500) {
            reconcileCalls++;
            return _json(200, _list(reconcileCalls == 1 ? [] : rows, limit: limit, offset: offset));
          }
          return _json(200, _list([], limit: limit, offset: offset));
        }
        if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
        if (request.method == 'POST' && request.url.path == '/api/v1/training/examples') {
          postCount++;
          return http.Response('PRIVATE_CREATE_500', 500);
        }
        fail('Unexpected request: ${request.method} ${request.url}');
      });
      await _pump(tester, client);
      await _fillCreate(tester);
      await tester.tap(find.byKey(const ValueKey('training-create-submit')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('training-create-reconcile')));
      await tester.tap(find.byKey(const ValueKey('training-create-reconcile')));
      await tester.pumpAndSettle();
      expect(postCount, 1);
      if (candidateCount == 1) {
        expect(find.text('Có bản ghi có khả năng khớp'), findsOneWidget);
      } else {
        expect(find.text('Có nhiều bản ghi khớp'), findsOneWidget);
      }
      for (var id = 80; id < 80 + candidateCount; id++) {
        expect(find.byKey(ValueKey('training-create-match-$id')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('training-create-retry-review')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    });
  }

  testWidgets('pre-existing same-content row is excluded by baseline ID set', (tester) async {
    var postCount = 0;
    var snapshotCalls = 0;
    final oldRow = _example(id: 41);
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples' && request.method == 'GET') {
        final limit = int.parse(request.url.queryParameters['limit']!);
        final offset = int.parse(request.url.queryParameters['offset']!);
        if (limit == 500) {
          snapshotCalls++;
          return _json(200, _list([oldRow], limit: limit, offset: offset));
        }
        return _json(200, _list([], limit: limit, offset: offset));
      }
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.method == 'POST' && request.url.path == '/api/v1/training/examples') {
        postCount++;
        return http.Response('PRIVATE_CREATE_500', 500);
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    await _pump(tester, client);
    await _fillCreate(tester);
    await tester.tap(find.byKey(const ValueKey('training-create-submit')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('training-create-reconcile')));
    await tester.tap(find.byKey(const ValueKey('training-create-reconcile')));
    await tester.pumpAndSettle();
    expect(snapshotCalls, 2);
    expect(postCount, 1);
    expect(find.text('Không tìm thấy bản ghi mới trong snapshot'), findsOneWidget);
    expect(find.byKey(const ValueKey('training-create-match-41')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('reconciliation paginates beyond 500 rows before reporting a match', (tester) async {
    var postCount = 0;
    var snapshotPhase = 0;
    final firstPage = List<Map<String, dynamic>>.generate(
      500,
      (index) => {
        ..._example(id: index + 1),
        'question': 'Existing row question number $index',
      },
    );
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples' && request.method == 'GET') {
        final limit = int.parse(request.url.queryParameters['limit']!);
        final offset = int.parse(request.url.queryParameters['offset']!);
        if (limit == 500) {
          if (snapshotPhase == 0) {
            snapshotPhase++;
            return _json(200, _list([], limit: limit, offset: offset));
          }
          if (offset == 0) {
            return _json(200, _list(firstPage, limit: limit, offset: offset, total: 501));
          }
          return _json(200, _list([_example(id: 900)], limit: limit, offset: offset, total: 501));
        }
        return _json(200, _list([], limit: limit, offset: offset));
      }
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.method == 'POST' && request.url.path == '/api/v1/training/examples') {
        postCount++;
        return http.Response('PRIVATE_CREATE_500', 500);
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    await _pump(tester, client);
    await _fillCreate(tester);
    await tester.tap(find.byKey(const ValueKey('training-create-submit')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('training-create-reconcile')));
    await tester.tap(find.byKey(const ValueKey('training-create-reconcile')));
    await tester.pumpAndSettle();
    expect(postCount, 1);
    expect(find.text('Có bản ghi có khả năng khớp'), findsOneWidget);
    expect(find.byKey(const ValueKey('training-create-match-900')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('incomplete pagination never unlocks Create retry', (tester) async {
    var postCount = 0;
    var snapshotPhase = 0;
    final shortPage = List<Map<String, dynamic>>.generate(
      499,
      (index) => {
        ..._example(id: index + 1),
        'question': 'Existing row question number $index',
      },
    );
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples' && request.method == 'GET') {
        final limit = int.parse(request.url.queryParameters['limit']!);
        final offset = int.parse(request.url.queryParameters['offset']!);
        if (limit == 500) {
          if (snapshotPhase++ == 0) return _json(200, _list([], limit: limit, offset: offset));
          return _json(200, _list(shortPage, limit: limit, offset: offset, total: 501));
        }
        return _json(200, _list([], limit: limit, offset: offset));
      }
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.method == 'POST' && request.url.path == '/api/v1/training/examples') {
        postCount++;
        return http.Response('PRIVATE_CREATE_500', 500);
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    await _pump(tester, client);
    await _fillCreate(tester);
    await tester.tap(find.byKey(const ValueKey('training-create-submit')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('training-create-reconcile')));
    await tester.tap(find.byKey(const ValueKey('training-create-reconcile')));
    await tester.pumpAndSettle();
    expect(postCount, 1);
    expect(find.text('Chưa đối soát đầy đủ'), findsOneWidget);
    expect(find.byKey(const ValueKey('training-create-retry-review')), findsNothing);
    expect(find.byKey(const ValueKey('training-create-reconcile')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('reconcile List 401 expires session once and keeps Create locked', (tester) async {
    var postCount = 0;
    var snapshotCalls = 0;
    final expired = <String>[];
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples' && request.method == 'GET') {
        final limit = int.parse(request.url.queryParameters['limit']!);
        final offset = int.parse(request.url.queryParameters['offset']!);
        if (limit == 500) {
          snapshotCalls++;
          if (snapshotCalls == 2) return http.Response('PRIVATE_RECONCILE_401', 401);
        }
        return _json(200, _list([], limit: limit, offset: offset));
      }
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.method == 'POST' && request.url.path == '/api/v1/training/examples') {
        postCount++;
        return http.Response('PRIVATE_CREATE_500', 500);
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    await _pump(tester, client, onSessionExpired: expired.add);
    await _fillCreate(tester);
    await tester.tap(find.byKey(const ValueKey('training-create-submit')));
    await tester.pumpAndSettle();
    expect(postCount, 1);
    await tester.ensureVisible(find.byKey(const ValueKey('training-create-reconcile')));
    await tester.tap(find.byKey(const ValueKey('training-create-reconcile')));
    await tester.pumpAndSettle();
    expect(snapshotCalls, 2);
    expect(postCount, 1);
    expect(expired, [_token]);
    expect(find.text('Chưa đối soát đầy đủ'), findsOneWidget);
    expect(find.textContaining('Phiên đăng nhập đã hết hạn trong khi đối soát'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('training-create-reconcile')),
    ).onPressed, isNull);
    expect(find.textContaining('PRIVATE_RECONCILE_401'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('Create 409 reconciles List and never blindly retries POST', (tester) async {
    var postCount = 0;
    var listOnlyCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples' && request.method == 'GET') {
        final limit = int.parse(request.url.queryParameters['limit']!);
        final offset = int.parse(request.url.queryParameters['offset']!);
        if (limit == 500) {
          listOnlyCalls++;
          return _json(200, _list([], limit: limit, offset: offset));
        }
        return _json(200, _list([], limit: limit, offset: offset));
      }
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.method == 'POST' && request.url.path == '/api/v1/training/examples') {
        postCount++;
        return http.Response('PRIVATE_CREATE_409', 409);
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    await _pump(tester, client);
    await _fillCreate(tester);
    await tester.tap(find.byKey(const ValueKey('training-create-submit')));
    await tester.pumpAndSettle();
    expect(postCount, 1);
    expect(listOnlyCalls, 2);
    expect(find.text('Không tìm thấy bản ghi mới trong snapshot'), findsOneWidget);
    expect(find.textContaining('xung đột'), findsOneWidget);
    expect(find.byKey(const ValueKey('training-create-retry-review')), findsOneWidget);
    expect(postCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('create 401 expires owner session once and blocks further POST', (tester) async {
    var postCount = 0;
    var baselineCalls = 0;
    final expired = <String>[];
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.method == 'POST' && request.url.path == '/api/v1/training/examples') {
        postCount++;
        return http.Response('PRIVATE_CREATE_401_BODY', 401);
      }
      if (request.method == 'GET' && request.url.path == '/api/v1/training/examples') {
        final limit = int.parse(request.url.queryParameters['limit']!);
        final offset = int.parse(request.url.queryParameters['offset']!);
        if (limit == 500) baselineCalls++;
        return _json(200, _list([], limit: limit, offset: offset));
      }
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
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
    expect(baselineCalls, 1); // Pre-POST baseline only; no reconcile after 401.
    expect(expired, [_token]);
    expect(find.text('Phiên đăng nhập đã hết hạn'), findsOneWidget);
    expect(find.textContaining('Create bị khóa'), findsOneWidget);
    expect(find.text('Đang gửi...'), findsNothing);
    expect(find.byKey(const ValueKey('training-create-reconcile')), findsNothing);
    expect(find.byKey(const ValueKey('training-create-error')), findsNothing);
    expect(find.textContaining('PRIVATE_CREATE_401_BODY'), findsNothing);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('training-create-question'))).controller!.text.trim(), _question);
    expect(find.text('Đã lưu ví dụ ở trạng thái chờ duyệt.'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  for (final status in [408, 429]) {
    testWidgets('Create HTTP status remains UNKNOWN and never retries automatically', (tester) async {
      var postCount = 0;
      var listGets = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
        if (request.url.path == '/api/v1/training/examples' && request.method == 'GET') {
          listGets++;
          final limit = int.parse(request.url.queryParameters['limit']!);
          final offset = int.parse(request.url.queryParameters['offset']!);
          return _json(200, _list([], limit: limit, offset: offset));
        }
        if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
        if (request.method == 'POST' && request.url.path == '/api/v1/training/examples') {
          postCount++;
          return http.Response('PRIVATE_CREATE_STATUS', status);
        }
        fail('Unexpected request');
      });
      await _pump(tester, client);
      await _fillCreate(tester);
      final submit = find.byKey(const ValueKey('training-create-submit'));
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(postCount, 1);
      expect(find.text('Kết quả gửi chưa xác định'), findsOneWidget);
      expect(find.textContaining('HTTP ' + status.toString()), findsOneWidget);
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('training-create-question'))).enabled, isFalse);
      expect(find.textContaining('PRIVATE_CREATE_STATUS'), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('training-create-reconcile')));
      await tester.tap(find.byKey(const ValueKey('training-create-reconcile')));
      await tester.pumpAndSettle();
      expect(listGets, 2);
      expect(postCount, 1);
      expect(find.text('Không tìm thấy bản ghi mới trong snapshot'), findsOneWidget);
      expect(find.byKey(const ValueKey('training-create-retry-review')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    });
  }

  for (final malformed in ['missing-status', 'invalid-status', 'missing-created-at', 'invalid-created-at']) {
    testWidgets('reconcile rejects malformed List row', (tester) async {
      var postCount = 0;
      var listGets = 0;
      final row = _example();
      if (malformed == 'missing-status') row.remove('status');
      if (malformed == 'invalid-status') row['status'] = 'archived';
      if (malformed == 'missing-created-at') row.remove('created_at');
      if (malformed == 'invalid-created-at') row['created_at'] = 'not-a-date';
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
        if (request.url.path == '/api/v1/training/examples' && request.method == 'GET') {
          listGets++;
          final limit = int.parse(request.url.queryParameters['limit']!);
          final offset = int.parse(request.url.queryParameters['offset']!);
          return _json(200, _list(listGets == 1 ? [] : [row], limit: limit, offset: offset));
        }
        if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
        if (request.method == 'POST' && request.url.path == '/api/v1/training/examples') {
          postCount++;
          return http.Response('PRIVATE_CREATE_500', 500);
        }
        fail('Unexpected request');
      });
      await _pump(tester, client);
      await _fillCreate(tester);
      await tester.tap(find.byKey(const ValueKey('training-create-submit')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('training-create-reconcile')));
      await tester.tap(find.byKey(const ValueKey('training-create-reconcile')));
      await tester.pumpAndSettle();
      expect(postCount, 1);
      expect(listGets, 2);
      expect(find.text('Chưa đối soát đầy đủ'), findsOneWidget);
      expect(find.textContaining('status hoặc created_at không hợp lệ'), findsOneWidget);
      expect(find.byKey(const ValueKey('training-create-match-41')), findsNothing);
      expect(find.byKey(const ValueKey('training-create-retry-review')), findsNothing);
      expect(find.byKey(const ValueKey('training-create-reconcile')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    });
  }

  testWidgets('malformed preflight List row prevents Create POST', (tester) async {
    var postCount = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples' && request.method == 'GET') {
        final limit = int.parse(request.url.queryParameters['limit']!);
        final offset = int.parse(request.url.queryParameters['offset']!);
        return _json(200, _list([_example()..remove('created_at')], limit: limit, offset: offset));
      }
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.method == 'POST' && request.url.path == '/api/v1/training/examples') postCount++;
      fail('Unexpected request');
    });
    await _pump(tester, client);
    await _fillCreate(tester);
    await tester.tap(find.byKey(const ValueKey('training-create-submit')));
    await tester.pumpAndSettle();
    expect(postCount, 0);
    expect(find.textContaining('Chưa gửi Create'), findsOneWidget);
    expect(find.text('Đang gửi...'), findsNothing);
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
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Sửa')).onPressed, isNull);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Từ chối')).onPressed, isNull);
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
    expect(find.text('Đã duyệt ví dụ huấn luyện.'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });
}
