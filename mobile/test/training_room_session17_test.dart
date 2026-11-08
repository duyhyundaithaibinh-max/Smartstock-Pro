import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartstock_pro/main.dart' show DashboardPage;
import 'package:smartstock_pro/training_room_page.dart';

const _token = 'session17-test-token';

http.Response _json(int status, Map<String, dynamic> value) => http.Response(
      jsonEncode(value),
      status,
      headers: {'content-type': 'application/json'},
    );

Map<String, dynamic> _evaluation({int approved = 1}) => {
      'total_examples': approved,
      'approved_examples': approved,
      'draft_examples': 0,
      'duplicate_question_groups': 0,
      'readiness': 'collect_and_review_more_examples',
    };

Map<String, dynamic> _example({String citation = 'kb:7:2'}) => {
      'id': 12,
      'question': 'Câu hỏi mẫu để kiểm tra citation nguồn',
      'expected_answer': 'Đáp án tiếng Việt đã được kiểm chứng từ tài liệu nguồn.',
      'topic': 'fibonacci',
      'citation_ids': [citation],
      'status': 'approved',
    };

Map<String, dynamic> _export({
  int count = 1,
  String content = '{"messages":[{"role":"user","content":"Câu hỏi"},{"role":"assistant","content":"Đáp án tiếng Việt"}],"metadata":{"example_id":12}}',
}) => {'format': 'jsonl', 'count': count, 'content': content};

Future<void> _pumpTraining(
  WidgetTester tester,
  MockClient client, {
  TrainingFileSaveCallback? saveFile,
  void Function(String token)? onSessionExpired,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: TrainingRoomPage(
      baseUrl: 'http://test',
      apiToken: _token,
      httpClient: client,
      fileSaveCallback: saveFile,
      onSessionExpired: onSessionExpired,
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _showExport(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Lưu JSONL đã duyệt'),
    250,
    scrollable: find.byType(Scrollable).first,
  );
}

Future<void> _showCitation(WidgetTester tester, String citation) async {
  await tester.scrollUntilVisible(
    find.byKey(ValueKey('citation-open-$citation')),
    250,
    scrollable: find.byType(Scrollable).first,
  );
}

http.Response _trainingRoute(http.Request request, {
  int approved = 1,
  List<dynamic>? examples,
  http.Response? exportResponse,
  http.Response? citationResponse,
}) {
  switch (request.url.path) {
    case '/api/v1/knowledge/documents':
      return _json(200, {'total': 0, 'items': []});
    case '/api/v1/training/examples':
      return _json(200, {'total': examples?.length ?? (approved > 0 ? 1 : 0), 'items': examples ?? (approved > 0 ? [_example()] : [])});
    case '/api/v1/training/evaluation':
      return _json(200, _evaluation(approved: approved));
    case '/api/v1/training/export':
      return exportResponse ?? _json(200, _export());
    case '/api/v1/knowledge/citations/7/2':
      return citationResponse ?? _json(200, {
        'citation_id': 'kb:7:2',
        'document_id': 7,
        'chunk_index': 2,
        'chunk_id': 19,
        'filename': 'fibonacci.md',
        'title': 'Fibonacci time projection',
        'source': 'user_research',
        'category': 'fibonacci',
        'content_sha256': 'a' * 64,
        'char_start': 120,
        'char_end': 220,
        'content': 'Đoạn nguồn chính xác về Fibonacci và chu kỳ thời gian.',
      });
    default:
      throw StateError('Unexpected request: ${request.method} ${request.url}');
  }
}

void main() {
  group('Training Room JSONL file export', () {
    testWidgets('saves valid JSONL as UTF-8 and reports success only after save',
        (tester) async {
      Uint8List? savedBytes;
      String? savedName;
      final client = MockClient((request) async => _trainingRoute(request));
      await _pumpTraining(tester, client, saveFile: ({required fileName, required bytes}) async {
        savedName = fileName;
        savedBytes = bytes;
        return Uri.parse('content://downloads/smartstock.jsonl');
      });
      await _showExport(tester);
      await tester.tap(find.text('Lưu JSONL đã duyệt'));
      await tester.pumpAndSettle();

      expect(savedName, endsWith('.jsonl'));
      expect(savedBytes, isNotNull);
      expect(utf8.decode(savedBytes!), contains('Đáp án tiếng Việt'));
      expect(utf8.decode(savedBytes!).split('\n'), hasLength(1));
      expect(find.textContaining('Đã lưu 1 ví dụ JSONL'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    });

    testWidgets('empty export does not create an empty file', (tester) async {
      var saveCalls = 0;
      final client = MockClient((request) async => _trainingRoute(
            request,
            approved: 0,
            exportResponse: _json(200, _export(count: 0, content: '')),
          ));
      await _pumpTraining(tester, client, saveFile: ({required fileName, required bytes}) async {
        saveCalls++;
        return Uri.parse('file:///tmp/empty.jsonl');
      });
      await _showExport(tester);
      await tester.tap(find.text('Lưu JSONL đã duyệt'));
      await tester.pumpAndSettle();

      expect(saveCalls, 0);
      expect(find.text('Chưa có ví dụ đã duyệt hợp lệ để lưu JSONL.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    });

    testWidgets('save dialog cancellation is not reported as success',
        (tester) async {
      final client = MockClient((request) async => _trainingRoute(request));
      await _pumpTraining(tester, client, saveFile: ({required fileName, required bytes}) async => null);
      await _showExport(tester);
      await tester.tap(find.text('Lưu JSONL đã duyệt'));
      await tester.pumpAndSettle();

      expect(find.text('Đã hủy lưu tệp JSONL.'), findsOneWidget);
      expect(find.textContaining('Đã lưu 1 ví dụ JSONL'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    });

    testWidgets('write failure shows safe error and does not report success',
        (tester) async {
      final client = MockClient((request) async => _trainingRoute(request));
      await _pumpTraining(tester, client, saveFile: ({required fileName, required bytes}) async {
        throw const FileSystemException('PRIVATE-PATH-AND-DETAIL');
      });
      await _showExport(tester);
      await tester.tap(find.text('Lưu JSONL đã duyệt'));
      await tester.pumpAndSettle();

      expect(find.textContaining('PRIVATE-PATH-AND-DETAIL'), findsNothing);
      expect(find.textContaining('Không xuất được dữ liệu'), findsOneWidget);
      expect(find.textContaining('Đã lưu 1 ví dụ JSONL'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    });

    testWidgets('rejects malformed JSONL and count mismatch before saving',
        (tester) async {
      var saveCalls = 0;
      final client = MockClient((request) async => _trainingRoute(
            request,
            exportResponse: _json(200, _export(count: 2, content: '{"one":1}')),
          ));
      await _pumpTraining(tester, client, saveFile: ({required fileName, required bytes}) async {
        saveCalls++;
        return Uri.parse('file:///tmp/bad.jsonl');
      });
      await _showExport(tester);
      await tester.tap(find.text('Lưu JSONL đã duyệt'));
      await tester.pumpAndSettle();

      expect(saveCalls, 0);
      expect(find.textContaining('Số dòng JSONL không khớp'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    });
  });

  group('Training Room citation detail', () {
    testWidgets('resolves exact citation and displays source metadata and excerpt',
        (tester) async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return _trainingRoute(request);
      });
      await _pumpTraining(tester, client);
      await _showCitation(tester, 'kb:7:2');
      await tester.tap(find.byKey(const ValueKey('citation-open-kb:7:2')));
      await tester.pumpAndSettle();

      expect(requests.any((r) => r.url.path == '/api/v1/knowledge/citations/7/2'), isTrue);
      expect(requests.lastWhere((r) => r.url.path.endsWith('/7/2')).headers['authorization'], 'Bearer $_token');
      expect(find.text('Đoạn nguồn'), findsOneWidget);
      expect(find.text('Fibonacci time projection'), findsOneWidget);
      expect(find.textContaining('Đoạn nguồn chính xác về Fibonacci'), findsOneWidget);
      expect(find.textContaining('SHA-256:'), findsOneWidget);
      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    });

    testWidgets('citation 404 reports missing source without fabricating excerpt',
        (tester) async {
      final client = MockClient((request) async => _trainingRoute(
            request,
            citationResponse: _json(404, {'detail': 'PRIVATE-404-DETAIL'}),
          ));
      await _pumpTraining(tester, client);
      await _showCitation(tester, 'kb:7:2');
      await tester.tap(find.byKey(const ValueKey('citation-open-kb:7:2')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Không tìm thấy tài nguyên'), findsOneWidget);
      expect(find.textContaining('PRIVATE-404-DETAIL'), findsNothing);
      expect(find.text('Đoạn nguồn'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    });

    testWidgets('citation 401 expires session and never shows raw response',
        (tester) async {
      var expired = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/knowledge/citations/7/2') {
          return http.Response('PRIVATE-CITATION-TRACEBACK', 401);
        }
        return _trainingRoute(request);
      });
      await _pumpTraining(tester, client, onSessionExpired: (token) {
        expect(token, _token);
        expired++;
      });
      await _showCitation(tester, 'kb:7:2');
      await tester.tap(find.byKey(const ValueKey('citation-open-kb:7:2')));
      await tester.pumpAndSettle();

      expect(expired, 1);
      expect(find.textContaining('PRIVATE-CITATION-TRACEBACK'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    });

    testWidgets('citation network and malformed response errors are sanitized',
        (tester) async {
      for (final mode in ['network', 'malformed']) {
        final client = MockClient((request) async {
          if (request.url.path == '/api/v1/knowledge/citations/7/2') {
            if (mode == 'network') throw const SocketException('PRIVATE-NETWORK-DETAIL');
            return http.Response('not-json', 200);
          }
          return _trainingRoute(request);
        });
        await _pumpTraining(tester, client);
        await _showCitation(tester, 'kb:7:2');
        await tester.tap(find.byKey(const ValueKey('citation-open-kb:7:2')));
        await tester.pumpAndSettle();

        expect(find.textContaining('PRIVATE-NETWORK-DETAIL'), findsNothing);
        expect(find.textContaining('not-json'), findsNothing);
        expect(find.textContaining('Không mở được đoạn nguồn'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        client.close();
      }
    });
  });

  group('Dashboard auth error sanitization', () {
    testWidgets('auth-status socket failure is sanitized', (tester) async {
      final client = MockClient((request) async {
        throw const SocketException('AUTH-STATUS-PRIVATE-DETAIL');
      });
      await tester.pumpWidget(MaterialApp(home: DashboardPage(httpClient: client)));
      await tester.pumpAndSettle();

      expect(find.textContaining('Không thể kết nối máy chủ'), findsOneWidget);
      expect(find.textContaining('AUTH-STATUS-PRIVATE-DETAIL'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    });

    testWidgets('login 401 is a credential error, not a protected-session expiry',
        (tester) async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/auth/status')) {
          return _json(200, {'owner_initialized': true});
        }
        if (request.url.path.endsWith('/auth/login')) {
          return http.Response('LOGIN-PRIVATE-TRACEBACK-$_token', 401);
        }
        throw StateError('Unexpected request: ${request.url}');
      });
      await tester.pumpWidget(MaterialApp(home: DashboardPage(httpClient: client)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('username')), 'owner');
      await tester.enterText(find.byKey(const ValueKey('password')), 'incorrect-password');
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Tên đăng nhập hoặc mật khẩu không đúng.'), findsOneWidget);
      expect(find.textContaining('LOGIN-PRIVATE-TRACEBACK'), findsNothing);
      expect(find.textContaining(_token), findsNothing);
      expect(find.textContaining('Phiên đăng nhập đã hết hạn'), findsNothing);
      expect(find.text('SmartStock Pro • Đăng nhập'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    });

    testWidgets('login timeout is sanitized without creating a session',
        (tester) async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/auth/status')) {
          return _json(200, {'owner_initialized': true});
        }
        if (request.url.path.endsWith('/auth/login')) {
          throw TimeoutException('LOGIN-TIMEOUT-PRIVATE-$_token');
        }
        throw StateError('Unexpected request: ${request.url}');
      });
      await tester.pumpWidget(MaterialApp(home: DashboardPage(httpClient: client)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('username')), 'owner');
      await tester.enterText(find.byKey(const ValueKey('password')), 'incorrect-password');
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Không thể kết nối máy chủ'), findsOneWidget);
      expect(find.textContaining('LOGIN-TIMEOUT-PRIVATE'), findsNothing);
      expect(find.textContaining(_token), findsNothing);
      expect(find.text('SmartStock Pro • Đăng nhập'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    });
  });
}
