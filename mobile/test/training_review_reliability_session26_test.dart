// ignore_for_file: prefer_const_constructors

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartstock_pro/training_room_page.dart';

const _session26Token = 'session26-private-owner-token';

Map<String, dynamic> _example26() => {
  'id': 21,
  'question': 'Câu hỏi kiểm thử phiên 26',
  'expected_answer': 'Đáp án kiểm thử',
  'topic': 'technical_analysis',
  'citation_ids': ['kb:8:3'],
  'status': 'approved',
  'revision': 1,
};

http.Response _json26(int status, Object value) => http.Response(
  jsonEncode(value), status,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _evaluation26() => {
  'total_examples': 1,
  'approved_examples': 1,
  'draft_examples': 0,
  'rejected_examples': 0,
  'duplicate_question_groups': 0,
  'readiness': 'collect_and_review_more_examples',
};

Future<void> _pumpTraining26(
  WidgetTester tester,
  MockClient client, {
  void Function(String token)? onExpired,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: TrainingRoomPage(
      baseUrl: 'http://test',
      apiToken: _session26Token,
      httpClient: client,
      onSessionExpired: onExpired,
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _openHistory26(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Lịch sử'),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Lịch sử'));
  await tester.pump();
}

void main() {
  testWidgets(
    'unmount with pending history requests suppresses transport-first then late 401',
    (tester) async {
      final events = Completer<http.Response>();
      final quality = Completer<http.Response>();
      var eventRequests = 0;
      var qualityRequests = 0;
      var expiryCalls = 0;

      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/knowledge/documents') {
          return _json26(200, {'items': []});
        }
        if (request.url.path == '/api/v1/training/examples') {
          return _json26(200, {'items': [_example26()], 'total': 1});
        }
        if (request.url.path == '/api/v1/training/evaluation') {
          return _json26(200, _evaluation26());
        }
        if (request.url.path.endsWith('/review-events')) {
          eventRequests++;
          return events.future;
        }
        if (request.url.path.endsWith('/quality-reviews')) {
          qualityRequests++;
          return quality.future;
        }
        throw StateError('Unexpected route: ${request.url.path}');
      });

      await _pumpTraining26(
        tester,
        client,
        onExpired: (_) => expiryCalls++,
      );
      await _openHistory26(tester);
      expect(eventRequests, 1);
      expect(qualityRequests, 1);
      expect(eventRequests + qualityRequests, 2);

      // Dispose the route while both actual HTTP requests are still pending.
      await tester.pumpWidget(const SizedBox.shrink());

      // Deliberately complete the transport failure first, then the sibling
      // HTTP 401. Both completions occur only after the widget is unmounted.
      events.completeError(
        TimeoutException('PRIVATE-UNMOUNT-FIRST-SESSION26-$_session26Token'),
      );
      await tester.pump();
      quality.complete(http.Response(
        'PRIVATE-LATE-401-SESSION26-$_session26Token',
        401,
      ));
      await tester.pumpAndSettle();

      expect(eventRequests, 1);
      expect(qualityRequests, 1);
      expect(eventRequests + qualityRequests, 2);
      expect(expiryCalls, 0);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('PRIVATE-UNMOUNT-FIRST'), findsNothing);
      expect(find.textContaining('PRIVATE-LATE-401'), findsNothing);
      expect(find.textContaining(_session26Token), findsNothing);

      client.close();
    },
  );

  testWidgets(
    'no-401 transport failure re-enables history action and a real retry renders history',
    (tester) async {
      final retryEvents = Completer<http.Response>();
      final retryQuality = Completer<http.Response>();
      var eventRequests = 0;
      var qualityRequests = 0;
      var expiryCalls = 0;

      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/knowledge/documents') {
          return _json26(200, {'items': []});
        }
        if (request.url.path == '/api/v1/training/examples') {
          return _json26(200, {'items': [_example26()], 'total': 1});
        }
        if (request.url.path == '/api/v1/training/evaluation') {
          return _json26(200, _evaluation26());
        }
        if (request.url.path.endsWith('/review-events')) {
          eventRequests++;
          if (eventRequests == 1) {
            throw TimeoutException('PRIVATE-FIRST-TIMEOUT-$_session26Token');
          }
          return retryEvents.future;
        }
        if (request.url.path.endsWith('/quality-reviews')) {
          qualityRequests++;
          if (qualityRequests == 1) {
            throw const SocketException('PRIVATE-FIRST-SOCKET');
          }
          return retryQuality.future;
        }
        throw StateError('Unexpected route: ${request.url.path}');
      });

      await _pumpTraining26(
        tester,
        client,
        onExpired: (_) => expiryCalls++,
      );
      await _openHistory26(tester);
      await tester.pumpAndSettle();

      expect(eventRequests, 1);
      expect(qualityRequests, 1);
      expect(eventRequests + qualityRequests, 2);
      expect(expiryCalls, 0);
      expect(
        find.text('Không thể kết nối máy chủ. Vui lòng kiểm tra mạng và thử lại.'),
        findsOneWidget,
      );
      expect(find.textContaining('PRIVATE-FIRST-TIMEOUT'), findsNothing);
      expect(find.textContaining('PRIVATE-FIRST-SOCKET'), findsNothing);
      expect(find.textContaining(_session26Token), findsNothing);

      final historyButton = find.widgetWithText(TextButton, 'Lịch sử');
      expect(historyButton, findsOneWidget);
      expect(tester.widget<TextButton>(historyButton).onPressed, isNotNull);

      // Exercise the enabled UI action: this must issue a fresh pair of
      // requests, not merely call a helper or inspect a callback.
      await tester.tap(historyButton);
      await tester.pump();
      expect(eventRequests, 2);
      expect(qualityRequests, 2);
      expect(eventRequests + qualityRequests, 4);
      expect(tester.widget<TextButton>(historyButton).onPressed, isNull);
      expect(expiryCalls, 0);

      retryEvents.complete(_json26(200, {
        'items': [{
          'id': 31,
          'example_id': 21,
          'action': 'approved',
          'reason': null,
          'revision_from': 1,
          'revision_to': 2,
          'changed_fields': <String>[],
          'reviewer_user_id': null,
          'reviewer_label': 'QA phiên 26',
          'created_at': '2026-11-09T02:00:00Z',
        }],
        'example_id': 21,
        'count': 1,
        'total': 1,
        'limit': 50,
        'offset': 0,
      }));
      retryQuality.complete(_json26(200, {
        'items': <dynamic>[],
        'example_id': 21,
        'count': 0,
      }));
      await tester.pumpAndSettle();

      expect(find.text('Lịch sử review • ví dụ #21'), findsOneWidget);
      expect(find.text('Đã duyệt • revision 1 → 2'), findsOneWidget);
      expect(find.textContaining('QA phiên 26'), findsOneWidget);
      expect(expiryCalls, 0);
      expect(find.textContaining('PRIVATE-FIRST-TIMEOUT'), findsNothing);
      expect(find.textContaining('PRIVATE-FIRST-SOCKET'), findsNothing);
      expect(find.textContaining(_session26Token), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(historyButton).onPressed, isNotNull);
      expect(expiryCalls, 0);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    },
  );
}
