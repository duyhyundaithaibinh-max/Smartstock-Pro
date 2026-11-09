import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartstock_pro/training_room_page.dart';

const _token = 'session21-owner-token';

Map<String, dynamic> _example({String status = 'draft', int revision = 1}) => {
  'id': 21,
  'question': 'Câu hỏi kiểm thử nội dung review phiên 21',
  'expected_answer': 'Đáp án đã được xác minh bằng nguồn trích dẫn.',
  'topic': 'technical_analysis',
  'citation_ids': ['kb:8:3'],
  'status': status,
  'revision': revision,
};

http.Response _json(int status, Object value) => http.Response(
  jsonEncode(value), status, headers: {'content-type': 'application/json'});

Map<String, dynamic> _evaluation() => {
  'total_examples': 1, 'approved_examples': 0, 'draft_examples': 1,
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

Future<void> _visible(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(
    find.text(label), 250, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('reject cancel never sends POST or DELETE', (tester) async {
    var mutations = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples') return _json(200, {'items': [_example()], 'total': 1});
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.method == 'POST' || request.method == 'DELETE') { mutations++; return _json(200, {}); }
      throw StateError('Unexpected route');
    });
    await _pump(tester, client);
    await _visible(tester, 'Từ chối');
    await tester.tap(find.text('Từ chối'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(mutations, 0);
    expect(find.text('Đã từ chối'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('reject 401 expires active token once and never exposes body or token', (tester) async {
    final expired = <String>[];
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples') return _json(200, {'items': [_example()], 'total': 1});
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.url.path.endsWith('/reject')) {
        expect(request.headers['authorization'], 'Bearer ' + _token);
        return http.Response('PRIVATE-TRACEBACK-' + _token, 401);
      }
      throw StateError('Unexpected route');
    });
    await _pump(tester, client, onSessionExpired: expired.add);
    await _visible(tester, 'Từ chối');
    await tester.tap(find.text('Từ chối'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('reject-reason')), 'Lý do hợp lệ để kiểm thử.');
    await tester.tap(find.byKey(const ValueKey('reject-confirm')));
    await tester.pumpAndSettle();
    expect(expired, [_token]);
    expect(find.textContaining('PRIVATE-TRACEBACK'), findsNothing);
    expect(find.textContaining(_token), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('reject 403, 429 and 500 do not expire session or expose raw body', (tester) async {
    for (final status in [403, 429, 500]) {
      var expiryCalls = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
        if (request.url.path == '/api/v1/training/examples') return _json(200, {'items': [_example()], 'total': 1});
        if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
        if (request.url.path.endsWith('/reject')) return http.Response('PRIVATE-RAW-' + _token, status);
        throw StateError('Unexpected route');
      });
      await _pump(tester, client, onSessionExpired: (_) => expiryCalls++);
      await _visible(tester, 'Từ chối');
      await tester.tap(find.text('Từ chối'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('reject-reason')), 'Lý do hợp lệ để kiểm thử.');
      await tester.tap(find.byKey(const ValueKey('reject-confirm')));
      await tester.pumpAndSettle();
      expect(expiryCalls, 0);
      expect(find.textContaining('PRIVATE-RAW'), findsNothing);
      expect(find.textContaining(_token), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    }
  });

  testWidgets('edit keeps actions busy until PATCH completes', (tester) async {
    final response = Completer<http.Response>();
    var patchCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples') return _json(200, {'items': [_example()], 'total': 1});
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.method == 'PATCH') { patchCalls++; return response.future; }
      throw StateError('Unexpected route');
    });
    await _pump(tester, client);
    await _visible(tester, 'Sửa');
    await tester.tap(find.text('Sửa'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('edit-topic')), 'elliott');
    await tester.tap(find.byKey(const ValueKey('edit-save')));
    await tester.pump();
    expect(patchCalls, 1);
    await tester.tap(find.text('Sửa'));
    await tester.pump();
    expect(patchCalls, 1);
    expect(find.textContaining('Sửa ví dụ #21'), findsNothing);
    response.complete(_json(200, {..._example(revision: 2), 'topic': 'elliott'}));
    await tester.pumpAndSettle();
    expect(find.text('Revision 2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('stale edit close preserves local draft and never retries automatically', (tester) async {
    var patchCalls = 0;
    var current = _example();
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples') return _json(200, {'items': [current], 'total': 1});
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.method == 'PATCH') {
        patchCalls++;
        current = {...current, 'topic': 'server-topic', 'revision': 2};
        return _json(409, {'detail': 'STALE-PRIVATE-DETAIL'});
      }
      throw StateError('Unexpected route');
    });
    await _pump(tester, client);
    await _visible(tester, 'Sửa');
    await tester.tap(find.text('Sửa'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('edit-topic')), 'local-edit');
    await tester.tap(find.byKey(const ValueKey('edit-save')));
    await tester.pumpAndSettle();
    expect(find.text('Revision đã thay đổi'), findsOneWidget);
    expect(find.textContaining('local-edit'), findsWidgets);
    expect(find.textContaining('STALE-PRIVATE-DETAIL'), findsNothing);
    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();
    expect(patchCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('quality review accepts 100 on approved and does not change status', (tester) async {
    Map<String, dynamic>? sent;
    final approved = _example(status: 'approved');
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples') return _json(200, {'items': [approved], 'total': 1});
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.method == 'POST' && request.url.path.endsWith('/quality-reviews')) {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return _json(201, {'id': 44, 'example_revision': 1, ...sent!});
      }
      throw StateError('Unexpected route');
    });
    await _pump(tester, client);
    await _visible(tester, 'Human Quality Review');
    await tester.tap(find.text('Human Quality Review'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('quality-score')), '100');
    await tester.enterText(find.byKey(const ValueKey('quality-rationale')),
      'Đạt toàn bộ tiêu chí đối chiếu nguồn và tính nhất quán.');
    await tester.tap(find.byKey(const ValueKey('quality-submit')));
    await tester.pumpAndSettle();
    expect(sent, {
      'score': 100, 'rubric_version': 'qa-quality-v1',
      'rationale': 'Đạt toàn bộ tiêu chí đối chiếu nguồn và tính nhất quán.',
    });
    expect(find.text('Đã duyệt'), findsOneWidget);
    expect(find.text('Đã từ chối'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('history tolerates empty quality history, future action and SQLite/ISO timestamps', (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples') return _json(200, {'items': [_example(status: 'approved')], 'total': 1});
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.url.path.endsWith('/review-events')) return _json(200, {
        'example_id': 21,
        'items': [
          {'id': 1, 'example_id': 21, 'action': 'future_action', 'reason': null,
           'revision_from': 1, 'revision_to': 1, 'changed_fields': [],
           'reviewer_user_id': null, 'reviewer_label': 'System',
           'created_at': '2026-11-09 00:21:00'},
          {'id': 2, 'example_id': 21, 'action': 'approved', 'reason': null,
           'revision_from': 1, 'revision_to': 1, 'changed_fields:': [],
           'reviewer_user_id': 9, 'reviewer_label': 'Owner',
           'created_at': '2026-11-09T00:22:00Z'},
        ],
        'count': 2, 'total': 2, 'limit': 50, 'offset': 0,
      });
      if (request.url.path.endsWith('/quality-reviews')) return _json(200, {'example_id': 21, 'items': [], 'count': 0});
      throw StateError('Unexpected route');
    });
    await _pump(tester, client);
    await _visible(tester, 'Lịch sử');
    await tester.tap(find.text('Lịch sử'));
    await tester.pumpAndSettle();
    expect(find.text('Sự kiện review • revision 1 → 1'), findsOneWidget);
    expect(find.text('Đã duyệt • revision 1 → 1'), findsOneWidget);
    expect(find.textContaining('2026-11-09 00:21:00'), findsOneWidget);
    expect(find.textContaining('2026-11-09T00:22:00Z'), findsOneWidget);
    expect(find.text('Chưa có đánh giá chất lượng thủ công.'), findsOneWidget);
    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('malformed history response is sanitized', (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples') return _json(200, {'items': [_example(status: 'approved')], 'total': 1});
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.url.path.endsWith('/review-events')) return http.Response('MALFORMED-SECRET-' + _token, 200);
      if (request.url.path.endsWith('/quality-reviews')) return _json(200, {'items': [], 'count': 0});
      throw StateError('Unexpected route');
    });
    await _pump(tester, client);
    await _visible(tester, 'Lịch sử');
    await tester.tap(find.text('Lịch sử'));
    await tester.pumpAndSettle();
    expect(find.textContaining('MALFORMED-SECRET'), findsNothing);
    expect(find.textContaining(_token), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('history 403 is a permission error, not session expiry', (tester) async {
    var expiryCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples') return _json(200, {'items': [_example(status: 'approved')], 'total': 1});
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.url.path.endsWith('/review-events')) return _json(403, {'detail': 'PRIVATE'});
      if (request.url.path.endsWith('/quality-reviews')) return _json(200, {'items': [], 'count': 0});
      throw StateError('Unexpected route');
    });
    await _pump(tester, client, onSessionExpired: (_) => expiryCalls++);
    await _visible(tester, 'Lịch sử');
    await tester.tap(find.text('Lịch sử'));
    await tester.pumpAndSettle();
    expect(expiryCalls, 0);
    expect(find.text('SmartStock Pro • Đăng nhập'), findsNothing);
    expect(find.textContaining('PRIVATE'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });
}
