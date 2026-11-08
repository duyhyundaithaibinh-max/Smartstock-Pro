import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartstock_pro/training_room_page.dart';

const _token = 'session20-owner-token';

Map<String, dynamic> _example({
  String status = 'draft',
  int revision = 1,
}) => {
  'id': 12,
  'question': 'Câu hỏi kiểm thử nội dung review',
  'expected_answer': 'Đáp án kiểm thử đã được xác minh từ nguồn.',
  'topic': 'fibonacci',
  'citation_ids': ['kb:7:2'],
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

Future<void> _pump(WidgetTester tester, MockClient client) async {
  await tester.pumpWidget(MaterialApp(home: TrainingRoomPage(
    baseUrl: 'http://test', apiToken: _token, httpClient: client)));
  await tester.pumpAndSettle();
}

Future<void> _visible(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.scrollUntilVisible(target, 250, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('reject sends trimmed reason and changes status without DELETE', (tester) async {
    var example = _example();
    var deleteCalls = 0;
    Map<String, dynamic>? rejectBody;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples') return _json(200, {'items': [example], 'total': 1});
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.url.path.endsWith('/reject') && request.method == 'POST') {
        rejectBody = jsonDecode(request.body) as Map<String, dynamic>;
        example = {...example, 'status': 'rejected'};
        return _json(200, example);
      }
      if (request.method == 'DELETE') { deleteCalls++; return _json(200, {'deleted': true}); }
      throw StateError('Unexpected route');
    });
    await _pump(tester, client);
    await _visible(tester, 'Từ chối');
    await tester.tap(find.text('Từ chối'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('reject-reason')), '  Nguồn chưa chứng minh kết luận.  ');
    await tester.tap(find.byKey(const ValueKey('reject-confirm')));
    await tester.pumpAndSettle();
    expect(rejectBody, {'reason': 'Nguồn chưa chứng minh kết luận.'});
    expect(deleteCalls, 0);
    expect(find.text('Đã từ chối'), findsOneWidget);
    expect(find.text('Sửa'), findsNothing);
    expect(find.text('Từ chối'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('reject blocks blank reason and allows cancel', (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples') return _json(200, {'items': [_example()], 'total': 1});
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      throw StateError('Unexpected route');
    });
    await _pump(tester, client);
    await _visible(tester, 'Từ chối');
    await tester.tap(find.text('Từ chối'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reject-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Lý do phải có 1–1.000 ký tự.'), findsOneWidget);
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(find.text('Đã từ chối'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('edit sends expected revision and only changed fields', (tester) async {
    var example = _example();
    Map<String, dynamic>? patchBody;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples') return _json(200, {'items': [example], 'total': 1});
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.method == 'PATCH') {
        patchBody = jsonDecode(request.body) as Map<String, dynamic>;
        example = {...example, 'topic': 'elliott', 'revision': 2};
        return _json(200, example);
      }
      throw StateError('Unexpected route');
    });
    await _pump(tester, client);
    await _visible(tester, 'Sửa');
    await tester.tap(find.text('Sửa'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('edit-topic')), 'elliott');
    await tester.tap(find.byKey(const ValueKey('edit-save')));
    await tester.pumpAndSettle();
    expect(patchBody, {'expected_revision': 1, 'topic': 'elliott'});
    expect(find.text('Revision 2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('stale edit keeps local draft and requires explicit revision refresh', (tester) async {
    var example = _example();
    var patchCount = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples') return _json(200, {'items': [example], 'total': 1});
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.method == 'PATCH') {
        patchCount++;
        if (patchCount == 1) {
          example = {...example, 'revision': 2, 'topic': 'server-topic'};
          return _json(409, {'detail': 'stale'});
        }
        expect((jsonDecode(request.body) as Map)['expected_revision'], 2);
        example = {...example, 'topic': 'elliott', 'revision': 3};
        return _json(200, example);
      }
      throw StateError('Unexpected route');
    });
    await _pump(tester, client);
    await _visible(tester, 'Sửa');
    await tester.tap(find.text('Sửa'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('edit-topic')), 'elliott');
    await tester.tap(find.byKey(const ValueKey('edit-save')));
    await tester.pumpAndSettle();
    expect(find.text('Revision đã thay đổi'), findsOneWidget);
    expect(find.textContaining('BẢN ĐANG SỬA'), findsOneWidget);
    expect(find.textContaining('elliott'), findsWidgets);
    await tester.tap(find.text('Tiếp tục trên revision mới'));
    await tester.pumpAndSettle();
    expect(find.textContaining('revision 2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('edit-save')));
    await tester.pumpAndSettle();
    expect(patchCount, 2);
    expect(find.text('Revision 3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('quality review accepts human score zero and leaves status unchanged', (tester) async {
    var example = _example(status: 'rejected');
    Map<String, dynamic>? qualityBody;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples') return _json(200, {'items': [example], 'total': 1});
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.url.path.endsWith('/quality-reviews') && request.method == 'POST') {
        qualityBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _json(201, {'id': 9, 'example_revision': 1, ...qualityBody!});
      }
      throw StateError('Unexpected route');
    });
    await _pump(tester, client);
    await _visible(tester, 'Human Quality Review');
    await tester.tap(find.text('Human Quality Review'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('quality-score')), '0');
    await tester.enterText(find.byKey(const ValueKey('quality-rationale')),
      'Nội dung chưa đạt tiêu chí kiểm chứng nguồn.');
    await tester.tap(find.byKey(const ValueKey('quality-submit')));
    await tester.pumpAndSettle();
    expect(qualityBody, {
      'score': 0, 'rubric_version': 'qa-quality-v1',
      'rationale': 'Nội dung chưa đạt tiêu chí kiểm chứng nguồn.',
    });
    expect(find.text('Đã từ chối'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('approved and rejected examples hide draft actions but retain quality and history', (tester) async {
    for (final status in ['approved', 'rejected']) {
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
        if (request.url.path == '/api/v1/training/examples') return _json(200, {'items': [_example(status: status)], 'total': 1});
        if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
        throw StateError('Unexpected route');
      });
      await _pump(tester, client);
      expect(find.text('Sửa'), findsNothing);
      expect(find.text('Từ chối'), findsNothing);
      expect(find.text('Human Quality Review'), findsOneWidget);
      expect(find.text('Lịch sử'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    }
  });

  testWidgets('history calls separate event and quality endpoints and renders server fields', (tester) async {
    var eventCalls = 0;
    var qualityCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples') return _json(200, {'items': [_example(status: 'approved')], 'total': 1});
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.url.path.endsWith('/review-events')) {
        eventCalls++;
        expect(request.url.queryParameters['limit'], '50');
        return _json(200, {'example_id': 12, 'items': [{
          'id': 31, 'example_id': 12, 'action': 'approved', 'reason': null,
          'revision_from': 1, 'revision_to': 1, 'changed_fields': [],
          'reviewer_user_id': 7, 'reviewer_label': 'Owner', 'created_at': '2026-11-09T00:00:00',
        }], 'count': 1, 'total': 1, 'limit': 50, 'offset': 0});
      }
      if (request.url.path.endsWith('/quality-reviews')) {
        qualityCalls++;
        return _json(200, {'example_id': 12, 'items': [{
          'id': 41, 'example_id': 12, 'example_revision': 1, 'score': 100,
          'rubric_version': 'qa-quality-v1', 'rationale': 'Đạt tiêu chí kiểm chứng nguồn.',
          'reviewer_user_id': 7, 'reviewed_at': '2026-11-09T00:01:00',
        }], 'count': 1});
      }
      throw StateError('Unexpected route');
    });
    await _pump(tester, client);
    await _visible(tester, 'Lịch sử');
    await tester.tap(find.text('Lịch sử'));
    await tester.pumpAndSettle();
    expect(eventCalls, 1);
    expect(qualityCalls, 1);
    expect(find.text('Đã duyệt • revision 1 → 1'), findsOneWidget);
    expect(find.textContaining('Điểm 100/100'), findsOneWidget);
    expect(find.textContaining('Thời gian máy chủ: 2026-11-09T00:00:00'), findsWidgets);
    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('review events pagination loads the next server page', (tester) async {
    var pageTwoCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/knowledge/documents') return _json(200, {'items': []});
      if (request.url.path == '/api/v1/training/examples') {
        return _json(200, {'items': [_example(status: 'approved')], 'total': 1});
      }
      if (request.url.path == '/api/v1/training/evaluation') return _json(200, _evaluation());
      if (request.url.path.endsWith('/review-events')) {
        final offset = request.url.queryParameters['offset'];
        if (offset == '0') {
          return _json(200, {'example_id': 12, 'items': [{
            'id': 1, 'example_id': 12, 'action': 'approved', 'reason': null,
            'revision_from': 1, 'revision_to': 1, 'changed_fields': [],
            'reviewer_user_id': 1, 'reviewer_label': 'Owner', 'created_at': 'first-event',
          }], 'count': 1, 'total': 2, 'limit': 1, 'offset': 0});
        }
        pageTwoCalls++;
        expect(offset, '1');
        return _json(200, {'example_id': 12, 'items': [{
          'id': 2, 'example_id': 12, 'action': 'edited', 'reason': null,
          'revision_from': 1, 'revision_to': 2, 'changed_fields': ['topic'],
          'reviewer_user_id': 1, 'reviewer_label': 'Owner', 'created_at': 'second-event',
        }], 'count': 1, 'total': 2, 'limit': 1, 'offset': 1});
      }
      if (request.url.path.endsWith('/quality-reviews')) {
        return _json(200, {'example_id': 12, 'items': [], 'count': 0});
      }
      throw StateError('Unexpected route');
    });
    await _pump(tester, client);
    await _visible(tester, 'Lịch sử');
    await tester.tap(find.text('Lịch sử'));
    await tester.pumpAndSettle();
    expect(find.textContaining('first-event'), findsOneWidget);
    await tester.tap(find.text('Tải thêm lịch sử'));
    await tester.pumpAndSettle();
    expect(pageTwoCalls, 1);
    expect(find.textContaining('second-event'), findsOneWidget);
    expect(find.text('Tải thêm lịch sử'), findsNothing);
    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

}
