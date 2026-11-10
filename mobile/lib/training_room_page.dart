import 'dart:convert';


import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'api_auth.dart';
import 'training_review_controls.dart';

typedef TrainingFileSaveCallback = Future<Uri?> Function({
  required String fileName,
  required Uint8List bytes,
});

class _TrainingDataRequestResult {
  const _TrainingDataRequestResult({this.response, this.error, this.stackTrace});
  final http.Response? response;
  final Object? error;
  final StackTrace? stackTrace;
}


enum _TrainingCreateOutcome {
  idle,
  submitting,
  unknownOutcome,
  reconciling,
  possibleMatch,
  ambiguousMatch,
  notFoundInSnapshot,
  reconcileFailed,
}

class _TrainingExamplesSnapshot {
  const _TrainingExamplesSnapshot({required this.items, required this.ids});
  final List<Map<String, dynamic>> items;
  final Set<int> ids;
}

/// Local knowledge retrieval and document management.
/// Search results are source passages, not AI-generated answers.
class TrainingRoomPage extends StatefulWidget {
  const TrainingRoomPage({
    super.key, required this.baseUrl, this.apiToken = '',
    this.onSessionExpired,
    this.httpClient,
    this.fileSaveCallback,
  });

  final String baseUrl;
  final String apiToken;
  final SessionExpiredCallback? onSessionExpired;
  final http.Client? httpClient;
  final TrainingFileSaveCallback? fileSaveCallback;

  @override
  State<TrainingRoomPage> createState() => _TrainingRoomPageState();
}

class _TrainingRoomPageState extends State<TrainingRoomPage> {
  late final http.Client _httpClient = widget.httpClient ?? http.Client();
  bool get _ownsHttpClient => widget.httpClient == null;

  final TextEditingController _queryController = TextEditingController();
  final TextEditingController _trainingQuestionController = TextEditingController();
  final TextEditingController _trainingAnswerController = TextEditingController();
  final TextEditingController _trainingTopicController = TextEditingController(text: 'technical_analysis');
  final TextEditingController _trainingCitationsController = TextEditingController();
  List<dynamic> _results = [];
  List<dynamic> _examples = [];
  Map<String, dynamic>? _evaluation;
  bool _savingExample = false;
  String? _trainingCreateError;
  _TrainingCreateOutcome _createOutcome = _TrainingCreateOutcome.idle;
  Map<String, dynamic>? _pendingCreatePayload;
  Set<int> _baselineCreateIds = <int>{};
  List<Map<String, dynamic>> _createMatches = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _createCandidates = <Map<String, dynamic>>[];
  String? _createOutcomeMessage;
  int? _lastCreatedExampleId;
  bool _trainingDataLoading = false;
  bool _exportingTraining = false;
  final Set<String> _citationLoadingIds = <String>{};
  final Set<int> _trainingActionIds = <int>{};
  final Set<int> _documentActionIds = <int>{};
  int _trainingDataRequestVersion = 0;
  int _documentsRequestVersion = 0;
  int _searchRequestVersion = 0;
  List<dynamic> _documents = [];
  Map<String, dynamic>? _context;
  String? _error;
  bool _loading = false;
  bool _uploading = false;
  bool _documentsLoading = false;
  bool _searched = false;
  bool _sessionExpired = false;
  String _categoryFilter = 'all';
  String _uploadCategory = 'other';

  static const Map<String, String> _categories = {
    'all': 'Tất cả nhóm',
    'technical_analysis': 'Phân tích kỹ thuật',
    'elliott_wave': 'Sóng Elliott',
    'fibonacci': 'Fibonacci',
    'wyckoff': 'Wyckoff',
    'risk_management': 'Quản trị rủi ro',
    'fundamental_analysis': 'Phân tích cơ bản',
    'market_data': 'Dữ liệu thị trường',
    'other': 'Khác',
  };

  String _categoryLabel(String? value) => _categories[value] ?? 'Khác';

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('${widget.baseUrl}$path').replace(queryParameters: query);
  }

  void _checkResponse(http.Response response, {required int expectedStatus}) {
    if (response.statusCode == 401) {
      if (!_sessionExpired) {
        _sessionExpired = true;
        widget.onSessionExpired?.call(widget.apiToken);
      }
      throw const ApiRequestException(401);
    }
    if (response.statusCode != expectedStatus) {
      throw ApiRequestException(response.statusCode);
    }
  }

  String _safeError(Object error, String fallback) =>
      safeApiErrorMessage(error, fallback: fallback);

  Future<_TrainingDataRequestResult> _captureTrainingDataRequest(
    Future<http.Response> Function() request,
  ) async {
    try {
      return _TrainingDataRequestResult(response: await request());
    } catch (error, stackTrace) {
      return _TrainingDataRequestResult(error: error, stackTrace: stackTrace);
    }
  }

  Future<void> _loadTrainingData() async {
    if (!mounted || _sessionExpired) return;
    final requestVersion = ++_trainingDataRequestVersion;
    if (mounted) {
      setState(() {
        _trainingDataLoading = true;
      });
    }
    try {
      // Capture each bounded request as response-or-error so a sibling
      // transport failure cannot hide an HTTP 401 from the other endpoint.
      final results = await Future.wait<_TrainingDataRequestResult>([
        _captureTrainingDataRequest(() => _httpClient.get(
          _uri('/api/v1/training/examples', {'limit': '100', 'offset': '0'}),
          headers: apiAuthHeaders(widget.apiToken),
        ).timeout(const Duration(seconds: 20))),
        _captureTrainingDataRequest(() => _httpClient.get(
          _uri('/api/v1/training/evaluation'),
          headers: apiAuthHeaders(widget.apiToken),
        ).timeout(const Duration(seconds: 20))),
      ]);

      // A disposed page must not deliver a late session-expiry callback.
      if (!mounted) return;

      // Session expiry takes precedence over sibling HTTP/transport failures.
      final unauthorized = results.where(
        (result) => result.response?.statusCode == 401,
      );
      if (unauthorized.isNotEmpty) {
        _checkResponse(unauthorized.first.response!, expectedStatus: 200);
      }

      final responses = <http.Response>[];
      for (final result in results) {
        if (result.error != null) {
          Error.throwWithStackTrace(
            result.error!,
            result.stackTrace ?? StackTrace.current,
          );
        }
        final response = result.response!;
        _checkResponse(response, expectedStatus: 200);
        responses.add(response);
      }
      if (!mounted || _sessionExpired) return;
      final examples = jsonDecode(responses[0].body) as Map<String, dynamic>;
      final evaluation = jsonDecode(responses[1].body) as Map<String, dynamic>;
      if (!mounted || requestVersion != _trainingDataRequestVersion) return;
      setState(() {
        _examples = examples['items'] as List<dynamic>? ?? [];
        _evaluation = evaluation;
        _error = null;
      });
    } catch (error) {
      if (mounted && !_sessionExpired && requestVersion == _trainingDataRequestVersion) {
        setState(() => _error = 'Không tải được bộ dữ liệu huấn luyện: ${_safeError(error, 'Đã xảy ra lỗi khi tải dữ liệu huấn luyện.')}');
      }
    } finally {
      if (mounted && requestVersion == _trainingDataRequestVersion) {
        setState(() => _trainingDataLoading = false);
      }
    }
  }


  List<Object?>? _normalizedTrainingTuple(Map<String, dynamic> item) {
    final question = item['question'];
    final answer = item['expected_answer'];
    final topic = item['topic'];
    final rawCitations = item['citation_ids'];
    if (question is! String || answer is! String || topic is! String ||
        rawCitations is! List || rawCitations.any((value) => value is! String)) {
      return null;
    }
    final citations = rawCitations
        .cast<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    final normalizedTopic = topic.trim().isEmpty ? 'general' : topic.trim();
    return [question.trim(), answer.trim(), normalizedTopic, citations];
  }

  bool _trainingExampleMatchesPayload(
    Map<String, dynamic> item,
    Map<String, dynamic> payload,
  ) {
    final rowTuple = _normalizedTrainingTuple(item);
    final payloadTuple = _normalizedTrainingTuple(payload);
    return rowTuple != null &&
        payloadTuple != null &&
        jsonEncode(rowTuple) == jsonEncode(payloadTuple);
  }

  Future<_TrainingExamplesSnapshot> _fetchTrainingExamplesSnapshot() async {
    const pageSize = 500;
    var offset = 0;
    int? expectedTotal;
    final items = <Map<String, dynamic>>[];
    final ids = <int>{};

    while (expectedTotal == null || offset < expectedTotal) {
      final response = await _httpClient.get(
        _uri('/api/v1/training/examples', {
          'limit': '$pageSize',
          'offset': '$offset',
        }),
        headers: apiAuthHeaders(widget.apiToken),
      ).timeout(const Duration(seconds: 20));
      _checkResponse(response, expectedStatus: 200);

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> ||
          decoded['items'] is! List ||
          decoded['total'] is! int ||
          (decoded['total'] as int) < 0 ||
          decoded['offset'] != offset ||
          decoded['limit'] != pageSize) {
        throw const SafeApiException(
          'Danh sách đối soát không đúng cấu trúc hoặc thiếu phân trang.',
        );
      }
      final pageTotal = decoded['total'] as int;
      if (expectedTotal == null) {
        expectedTotal = pageTotal;
      } else if (pageTotal != expectedTotal) {
        throw const SafeApiException(
          'Tổng số bản ghi thay đổi trong khi phân trang; chưa thể đối soát đầy đủ.',
        );
      }

      final pageItems = decoded['items'] as List<dynamic>;
      if (pageItems.length > pageSize ||
          pageItems.length > expectedTotal - offset) {
        throw const SafeApiException(
          'Trang danh sách trả về số bản ghi không hợp lệ.',
        );
      }
      for (final rawItem in pageItems) {
        if (rawItem is! Map<String, dynamic>) {
          throw const SafeApiException(
            'Một bản ghi trong danh sách đối soát không hợp lệ.',
          );
        }
        final id = rawItem['id'];
        if (id is! int || id <= 0 || !ids.add(id) ||
            _normalizedTrainingTuple(rawItem) == null) {
          throw const SafeApiException(
            'Danh sách đối soát có ID trùng hoặc dữ liệu bản ghi không hợp lệ.',
          );
        }
        items.add(Map<String, dynamic>.from(rawItem));
      }

      final nextOffset = offset + pageItems.length;
      if (nextOffset < expectedTotal && pageItems.length != pageSize) {
        throw const SafeApiException(
          'Danh sách đối soát chưa đọc hết các trang; không thể kết luận không có bản ghi.',
        );
      }
      if (nextOffset == offset && offset < expectedTotal) {
        throw const SafeApiException(
          'Phân trang không tiến triển; danh sách đối soát chưa đầy đủ.',
        );
      }
      offset = nextOffset;
    }

    if (items.length != expectedTotal) {
      throw const SafeApiException(
        'Số bản ghi đã đọc không khớp tổng số; đối soát chưa đầy đủ.',
      );
    }
    return _TrainingExamplesSnapshot(items: items, ids: ids);
  }

  Future<void> _reconcileUnknownCreate() async {
    if (!mounted || _sessionExpired ||
        _pendingCreatePayload == null ||
        !{
          _TrainingCreateOutcome.unknownOutcome,
          _TrainingCreateOutcome.reconcileFailed,
        }.contains(_createOutcome)) {
      return;
    }
    final wasConflict = _createOutcomeMessage?.contains('xung đột') ?? false;
    setState(() {
      _createOutcome = _TrainingCreateOutcome.reconciling;
      _createOutcomeMessage = 'Đang đọc riêng danh sách ví dụ; thao tác này chỉ gọi GET, không gửi Create.';
    });
    try {
      final snapshot = await _fetchTrainingExamplesSnapshot();
      if (!mounted || _sessionExpired) return;
      final payload = _pendingCreatePayload!;
      final matches = snapshot.items
          .where((item) => _trainingExampleMatchesPayload(item, payload))
          .toList();
      final candidates = matches
          .where((item) => !_baselineCreateIds.contains(item['id'] as int))
          .toList();

      setState(() {
        _createMatches = matches;
        _createCandidates = candidates;
        if (candidates.length == 1) {
          _createOutcome = _TrainingCreateOutcome.possibleMatch;
          _createOutcomeMessage = wasConflict
              ? 'Máy chủ trả về xung đột. Có một bản ghi mới khớp nội dung; đây chỉ là possible match, không chứng minh chắc chắn bản ghi được tạo bởi lần gửi vừa rồi.'
              : 'Có một bản ghi mới khớp nội dung. Đây chỉ là possible match, không chứng minh chắc chắn bản ghi được tạo bởi lần gửi vừa rồi.';
        } else if (candidates.length > 1) {
          _createOutcome = _TrainingCreateOutcome.ambiguousMatch;
          _createOutcomeMessage = wasConflict
              ? 'Máy chủ trả về xung đột. Có nhiều bản ghi mới khớp nội dung; không thể xác định bản ghi nào liên quan đến lần gửi vừa rồi.'
              : 'Có nhiều bản ghi mới khớp nội dung. Không thể xác định bản ghi nào liên quan đến lần gửi vừa rồi.';
        } else {
          _createOutcome = _TrainingCreateOutcome.notFoundInSnapshot;
          _createOutcomeMessage = wasConflict
              ? 'Máy chủ trả về xung đột. Không tìm thấy bản ghi mới khớp nội dung trong snapshot danh sách đã đọc đầy đủ; điều này không chứng minh máy chủ chưa lưu và yêu cầu cũ vẫn có thể hoàn tất muộn.'
              : 'Không tìm thấy bản ghi mới khớp nội dung trong snapshot danh sách đã đọc đầy đủ. Điều này không chứng minh máy chủ chưa lưu; yêu cầu cũ vẫn có thể hoàn tất muộn.';
        }
      });
    } catch (error) {
      if (mounted && !_sessionExpired) {
        setState(() {
          _createOutcome = _TrainingCreateOutcome.reconcileFailed;
          _createOutcomeMessage =
              'Chưa đối soát được danh sách: ${_safeError(error, 'Danh sách chưa đọc được đầy đủ. Vui lòng thử GET lại.')}';
        });
      }
    }
  }

  Future<void> _confirmCreateRetry() async {
    if (!mounted ||
        _sessionExpired ||
        _createOutcome != _TrainingCreateOutcome.notFoundInSnapshot ||
        _pendingCreatePayload == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xác nhận gửi Create lần nữa?'),
        content: const Text(
          'Không tìm thấy bản ghi mới khớp nội dung trong snapshot vừa đọc. '
          'Đây không phải bằng chứng lần gửi trước chưa được lưu: máy chủ vẫn có thể '
          'hoàn tất yêu cầu cũ muộn. Gửi lại có thể tạo bản ghi trùng. '
          'Chỉ tiếp tục nếu bạn đã hiểu và chấp nhận rủi ro này.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Quay lại'),
          ),
          FilledButton(
            key: const ValueKey('training-create-retry-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Tôi hiểu rủi ro, cho phép gửi lại'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _sessionExpired ||
        _createOutcome != _TrainingCreateOutcome.notFoundInSnapshot) {
      return;
    }

    final currentPayload = <String, dynamic>{
      'question': _trainingQuestionController.text.trim(),
      'expected_answer': _trainingAnswerController.text.trim(),
      'topic': _trainingTopicController.text.trim().isEmpty
          ? 'general'
          : _trainingTopicController.text.trim(),
      'citation_ids': _trainingCitationsController.text
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(),
    };
    if (jsonEncode(currentPayload) != jsonEncode(_pendingCreatePayload)) {
      setState(() {
        _createOutcome = _TrainingCreateOutcome.reconcileFailed;
        _createOutcomeMessage =
            'Nội dung biểu mẫu không còn trùng payload đang đối soát. Không gửi lại để tránh gửi sai dữ liệu.';
      });
      return;
    }

    setState(() {
      _createOutcome = _TrainingCreateOutcome.idle;
      _pendingCreatePayload = null;
      _baselineCreateIds = <int>{};
      _createMatches = <Map<String, dynamic>>[];
      _createCandidates = <Map<String, dynamic>>[];
      _createOutcomeMessage = null;
      _trainingCreateError = null;
    });
    await _saveTrainingExample();
  }

  Widget _buildCreateOutcomePanel() {
    final outcome = _createOutcome;
    if (outcome == _TrainingCreateOutcome.idle ||
        outcome == _TrainingCreateOutcome.submitting) {
      return const SizedBox.shrink();
    }
    final details = outcome == _TrainingCreateOutcome.possibleMatch
        ? _createCandidates
        : outcome == _TrainingCreateOutcome.ambiguousMatch
            ? _createCandidates
            : outcome == _TrainingCreateOutcome.notFoundInSnapshot
                ? _createMatches
                : const <Map<String, dynamic>>[];
    return Card(
      key: const ValueKey('training-create-outcome-panel'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              switch (outcome) {
                _TrainingCreateOutcome.unknownOutcome =>
                  'Kết quả gửi chưa xác định',
                _TrainingCreateOutcome.reconciling =>
                  'Đang đối soát danh sách',
                _TrainingCreateOutcome.possibleMatch =>
                  'Có bản ghi có khả năng khớp',
                _TrainingCreateOutcome.ambiguousMatch =>
                  'Có nhiều bản ghi khớp',
                _TrainingCreateOutcome.notFoundInSnapshot =>
                  'Không tìm thấy bản ghi mới trong snapshot',
                _TrainingCreateOutcome.reconcileFailed =>
                  'Chưa đối soát đầy đủ',
                _ => 'Đang xử lý Create',
              },
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(_createOutcomeMessage ?? ''),
            if (outcome == _TrainingCreateOutcome.reconciling)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...details.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'ID ${item['id']} • ${item['status'] ?? 'draft'}'
                  '${item['created_at'] is String ? ' • ${item['created_at']}' : ''}',
                  key: ValueKey('training-create-match-${item['id']}'),
                ),
              )),
            ],
            if (outcome == _TrainingCreateOutcome.unknownOutcome ||
                outcome == _TrainingCreateOutcome.reconcileFailed)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const ValueKey('training-create-reconcile'),
                  onPressed: _sessionExpired ? null : _reconcileUnknownCreate,
                  icon: const Icon(Icons.sync),
                  label: const Text('Đối soát danh sách (chỉ GET)'),
                ),
              ),
            if (outcome == _TrainingCreateOutcome.notFoundInSnapshot)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  key: const ValueKey('training-create-retry-review'),
                  onPressed: _sessionExpired ? null : _confirmCreateRetry,
                  child: const Text('Xem cảnh báo trước khi gửi lại'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveTrainingExample() async {
    if (!mounted || _sessionExpired || _savingExample ||
        _createOutcome != _TrainingCreateOutcome.idle) {
      return;
    }
    final question = _trainingQuestionController.text.trim();
    final answer = _trainingAnswerController.text.trim();
    final topic = _trainingTopicController.text.trim();
    final citations = _trainingCitationsController.text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    final citationPattern = RegExp(r'^kb:\d+:\d+$');
    if (question.length < 10 || question.length > 1000 ||
        answer.length < 20 || answer.length > 5000 ||
        topic.length > 80 || citations.isEmpty || citations.length > 10 ||
        citations.any((item) => !citationPattern.hasMatch(item)) ||
        citations.toSet().length != citations.length) {
      setState(() => _trainingCreateError =
          'Câu hỏi cần 10–1.000 ký tự, đáp án 20–5.000 ký tự, chủ đề tối đa 80 ký tự; cần 1–10 mã nguồn kb:document_id:chunk_index hợp lệ và không trùng.');
      return;
    }

    final payload = <String, dynamic>{
      'question': question,
      'expected_answer': answer,
      'topic': topic.isEmpty ? 'general' : topic,
      'citation_ids': List<String>.unmodifiable(citations),
    };
    var postDispatched = false;
    setState(() {
      _savingExample = true;
      _createOutcome = _TrainingCreateOutcome.submitting;
      _pendingCreatePayload = Map<String, dynamic>.unmodifiable(payload);
      _baselineCreateIds = <int>{};
      _createMatches = <Map<String, dynamic>>[];
      _createCandidates = <Map<String, dynamic>>[];
      _createOutcomeMessage = null;
      _lastCreatedExampleId = null;
      _trainingCreateError = null;
      _error = null;
    });

    try {
      final baseline = await _fetchTrainingExamplesSnapshot();
      if (!mounted || _sessionExpired) return;
      setState(() => _baselineCreateIds = Set<int>.from(baseline.ids));

      postDispatched = true;
      final response = await _httpClient.post(
        _uri('/api/v1/training/examples'),
        headers: {
          'Content-Type': 'application/json',
          ...apiAuthHeaders(widget.apiToken),
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 20));
      _checkResponse(response, expectedStatus: 201);
      int? createdExampleId;
      try {
        final createdPayload = jsonDecode(response.body);
        if (createdPayload is Map<String, dynamic> &&
            createdPayload['id'] is int) {
          createdExampleId = createdPayload['id'] as int;
        }
      } catch (_) {
        // HTTP 201 confirms creation even if an optional response field cannot
        // be decoded; never turn a confirmed success into an ambiguous retry.
      }

      if (!mounted || _sessionExpired) return;
      _lastCreatedExampleId = createdExampleId;
      _trainingQuestionController.clear();
      _trainingAnswerController.clear();
      _trainingCitationsController.clear();
      setState(() {
        _createOutcome = _TrainingCreateOutcome.idle;
        _pendingCreatePayload = null;
        _baselineCreateIds = <int>{};
        _createOutcomeMessage = null;
      });
      await _loadTrainingData();
      if (!mounted || _sessionExpired) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_lastCreatedExampleId == null
              ? 'Đã lưu ví dụ ở trạng thái chờ duyệt.'
              : 'Đã lưu ví dụ ở trạng thái chờ duyệt (ID $_lastCreatedExampleId).'),
        ),
      );
    } catch (error) {
      if (!mounted || _sessionExpired) return;
      if (!postDispatched) {
        setState(() {
          _createOutcome = _TrainingCreateOutcome.idle;
          _pendingCreatePayload = null;
          _baselineCreateIds = <int>{};
          _trainingCreateError =
              'Chưa gửi Create vì không thể đọc đầy đủ danh sách trước khi gửi: ${_safeError(error, 'Không thể xác minh danh sách hiện tại. Vui lòng thử lại.')}';
        });
      } else if (error is ApiRequestException &&
          error.statusCode >= 400 &&
          error.statusCode < 500 &&
          error.statusCode != 409) {
        setState(() {
          _createOutcome = _TrainingCreateOutcome.idle;
          _pendingCreatePayload = null;
          _baselineCreateIds = <int>{};
          _trainingCreateError =
              'Không lưu được ví dụ: ${_safeError(error, 'Dữ liệu bị từ chối.')}';
        });
      } else {
        setState(() {
          _createOutcome = _TrainingCreateOutcome.unknownOutcome;
          _createOutcomeMessage = error is ApiRequestException &&
                  error.statusCode == 409
              ? 'Máy chủ trả về xung đột. Cần đối soát danh sách trước khi quyết định; không tự gửi lại.'
              : 'Máy chủ chưa xác nhận kết quả lần gửi. Giữ nguyên nội dung; không tự gửi lại vì yêu cầu cũ có thể đã được lưu.';
        });
        if (error is ApiRequestException && error.statusCode == 409) {
          await _reconcileUnknownCreate();
        }
      }
    } finally {
      if (mounted) setState(() => _savingExample = false);
    }
  }

  Future<void> _approveTrainingExample(int id) async {
    if (!mounted || _sessionExpired) return;
    if (_trainingActionIds.contains(id)) return;
    setState(() {
      _trainingActionIds.add(id);
      _error = null;
    });
    try {
      final response = await _httpClient.post(
        _uri('/api/v1/training/examples/$id/approve'),
        headers: apiAuthHeaders(widget.apiToken),
      ).timeout(const Duration(seconds: 20));
      _checkResponse(response, expectedStatus: 200);
      if (!mounted || _sessionExpired) return;
      await _loadTrainingData();
      if (!mounted || _sessionExpired) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã duyệt ví dụ huấn luyện.')),
      );
    } on ApiRequestException catch (error) {
      if (error.statusCode == 409 && mounted && !_sessionExpired) {
        // Another reviewer may have changed this draft. Reconcile from the
        // authoritative list; never retry the approve mutation automatically.
        await _loadTrainingData();
        if (mounted && !_sessionExpired && _error == null) {
          setState(() => _error =
              'Ví dụ đã được xử lý ở nơi khác. Danh sách đã được đồng bộ; không tự gửi lại thao tác.');
        }
      } else if (mounted && !_sessionExpired) {
        setState(() => _error =
            'Không duyệt được ví dụ: ${_safeError(error, 'Đã xảy ra lỗi khi duyệt ví dụ.')}');
      }
    } catch (error) {
      if (mounted && !_sessionExpired) {
        setState(() => _error = 'Không duyệt được ví dụ: ${_safeError(error, 'Đã xảy ra lỗi khi duyệt ví dụ.')}');
      }
    } finally {
      if (mounted) setState(() => _trainingActionIds.remove(id));
    }
  }

  Future<void> _deleteTrainingExample(int id) async {
    if (!mounted || _sessionExpired) return;
    if (_trainingActionIds.contains(id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa ví dụ huấn luyện?'),
        content: const Text('Thao tác này sẽ xóa ví dụ khỏi bộ dữ liệu cục bộ.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _sessionExpired) return;
    setState(() {
      _trainingActionIds.add(id);
      _error = null;
    });
    try {
      final response = await _httpClient.delete(
        _uri('/api/v1/training/examples/$id'),
        headers: apiAuthHeaders(widget.apiToken),
      ).timeout(const Duration(seconds: 20));
      _checkResponse(response, expectedStatus: 200);
      if (!mounted || _sessionExpired) return;
      await _loadTrainingData();
      if (!mounted || _sessionExpired) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã xóa ví dụ huấn luyện.')),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Không xóa được ví dụ: ${_safeError(error, 'Đã xảy ra lỗi khi xóa ví dụ.')}');
      }
    } finally {
      if (mounted) setState(() => _trainingActionIds.remove(id));
    }
  }

  Map<String, dynamic> _parseTrainingExport(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic> || decoded['format'] != 'jsonl') {
      throw const SafeApiException('Định dạng dữ liệu xuất không hợp lệ.');
    }
    final count = decoded['count'];
    final content = decoded['content'];
    if (count is! int || count < 0 || content is! String) {
      throw const SafeApiException('Dữ liệu JSONL trả về không đầy đủ.');
    }
    final lines = content.isEmpty ? <String>[] : content.split('\n');
    if (lines.length != count || lines.any((line) => line.trim().isEmpty)) {
      throw const SafeApiException('Số dòng JSONL không khớp số lượng ví dụ.');
    }
    for (final line in lines) {
      final item = jsonDecode(line);
      if (item is! Map<String, dynamic>) {
        throw const SafeApiException('Một dòng JSONL không đúng cấu trúc.');
      }
    }
    return {'count': count, 'content': content};
  }

  Future<Map<String, dynamic>> _fetchTrainingExport() async {
    final response = await _httpClient.get(
      _uri('/api/v1/training/export'),
      headers: apiAuthHeaders(widget.apiToken),
    ).timeout(const Duration(seconds: 20));
    _checkResponse(response, expectedStatus: 200);
    if (!mounted || _sessionExpired) {
      throw const SafeApiException('Phiên làm việc không còn hoạt động.');
    }
    return _parseTrainingExport(response.body);
  }

  String _trainingExportFileName() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'smartstock-training-${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}.jsonl';
  }

  Future<Uri?> _saveTrainingFile(String fileName, Uint8List bytes) {
    final callback = widget.fileSaveCallback;
    if (callback != null) {
      return callback(fileName: fileName, bytes: bytes);
    }
    return FilePicker.saveFile(fileName: fileName, bytes: bytes);
  }

  Future<void> _saveTrainingExport() async {
    if (!mounted || _sessionExpired || _exportingTraining) return;
    setState(() {
      _exportingTraining = true;
      _error = null;
    });
    try {
      final payload = await _fetchTrainingExport();
      if (!mounted || _sessionExpired) return;
      final count = payload['count'] as int;
      if (count == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chưa có ví dụ đã duyệt hợp lệ để lưu JSONL.')),
        );
        return;
      }
      final bytes = Uint8List.fromList(utf8.encode(payload['content'] as String));
      final saved = await _saveTrainingFile(_trainingExportFileName(), bytes);
      if (!mounted || _sessionExpired) return;
      if (saved == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã hủy lưu tệp JSONL.')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã lưu $count ví dụ JSONL vào tệp đã chọn.')),
      );
    } catch (error) {
      if (mounted && !_sessionExpired) {
        setState(() => _error = 'Không xuất được dữ liệu: ${_safeError(error, 'Đã xảy ra lỗi khi lưu tệp JSONL.')}');
      }
    } finally {
      if (mounted) setState(() => _exportingTraining = false);
    }
  }

  Future<void> _copyTrainingExport() async {
    if (!mounted || _sessionExpired || _exportingTraining) return;
    setState(() {
      _exportingTraining = true;
      _error = null;
    });
    try {
      final payload = await _fetchTrainingExport();
      if (!mounted || _sessionExpired) return;
      final count = payload['count'] as int;
      if (count == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chưa có ví dụ đã duyệt hợp lệ để sao chép.')),
        );
        return;
      }
      await Clipboard.setData(ClipboardData(text: payload['content'] as String));
      if (!mounted || _sessionExpired) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã sao chép $count ví dụ đã duyệt dạng JSONL.')),
      );
    } catch (error) {
      if (mounted && !_sessionExpired) {
        setState(() => _error = 'Không xuất được dữ liệu: ${_safeError(error, 'Đã xảy ra lỗi khi sao chép JSONL.')}');
      }
    } finally {
      if (mounted) setState(() => _exportingTraining = false);
    }
  }

  Future<void> _openCitationDetail(String citation) async {
    if (!mounted || _sessionExpired || _citationLoadingIds.contains(citation)) return;
    final match = RegExp(r'^kb:(\d+):(\d+)$').firstMatch(citation);
    if (match == null) {
      setState(() => _error = 'Mã trích dẫn không đúng định dạng.');
      return;
    }
    final documentId = int.tryParse(match.group(1)!);
    final chunkIndex = int.tryParse(match.group(2)!);
    if (documentId == null || chunkIndex == null) {
      setState(() => _error = 'Mã trích dẫn không đúng định dạng.');
      return;
    }
    setState(() {
      _citationLoadingIds.add(citation);
      _error = null;
    });
    try {
      final response = await _httpClient.get(
        _uri('/api/v1/knowledge/citations/$documentId/$chunkIndex'),
        headers: apiAuthHeaders(widget.apiToken),
      ).timeout(const Duration(seconds: 20));
      _checkResponse(response, expectedStatus: 200);
      if (!mounted || _sessionExpired) return;
      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic> ||
          payload['citation_id'] != citation ||
          payload['document_id'] != documentId ||
          payload['chunk_index'] != chunkIndex ||
          payload['content'] is! String ||
          (payload['title'] is! String && payload['filename'] is! String) ||
          (payload['title'] != null && payload['title'] is! String) ||
          (payload['filename'] != null && payload['filename'] is! String)) {
        throw const SafeApiException('Dữ liệu đoạn nguồn trả về không hợp lệ.');
      }
      // The loading indicator belongs to the fetch, not the open dialog.
      setState(() => _citationLoadingIds.remove(citation));
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          final title = (payload['title'] as String?)?.trim();
          final filename = payload['filename']?.toString() ?? 'Tài liệu';
          final sourceTitle = title == null || title.isEmpty ? filename : title;
          final charStart = payload['char_start'];
          final charEnd = payload['char_end'];
          final locator = charStart is int && charEnd is int
              ? 'Ký tự $charStart–$charEnd'
              : 'Chưa có tọa độ ký tự';
          return AlertDialog(
            title: const Text('Đoạn nguồn'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(sourceTitle, style: Theme.of(dialogContext).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text('Nguồn: ${payload['source'] ?? '—'} • Nhóm: ${_categoryLabel(payload['category']?.toString())}'),
                    Text('Citation: $citation'),
                    Text('Đoạn $chunkIndex • $locator'),
                    if (payload['content_sha256'] is String)
                      SelectableText('SHA-256: ${payload['content_sha256']}'),
                    const Divider(height: 20),
                    SelectableText(payload['content'] as String),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Đóng'),
              ),
            ],
          );
        },
      );
    } catch (error) {
      if (mounted && !_sessionExpired) {
        setState(() => _error = 'Không mở được đoạn nguồn: ${_safeError(error, 'Đã xảy ra lỗi khi tải đoạn nguồn.')}');
      }
    } finally {
      if (mounted) setState(() => _citationLoadingIds.remove(citation));
    }
  }
  Future<void> _loadDocuments() async {
    if (!mounted || _sessionExpired) return;
    final requestVersion = ++_documentsRequestVersion;
    final category = _categoryFilter;
    setState(() {
      _documentsLoading = true;
      _error = null;
    });
    try {
      final response = await _httpClient.get(_uri('/api/v1/knowledge/documents', {
        'limit': '100',
        'offset': '0',
        if (category != 'all') 'category': category,
      }), headers: apiAuthHeaders(widget.apiToken)).timeout(const Duration(seconds: 20));
      _checkResponse(response, expectedStatus: 200);
      if (!mounted || _sessionExpired) return;
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (requestVersion != _documentsRequestVersion) return;
      setState(() => _documents = payload['items'] as List<dynamic>? ?? []);
    } catch (error) {
      if (mounted && requestVersion == _documentsRequestVersion) {
        setState(() => _error = 'Không tải được danh sách tài liệu: ${_safeError(error, 'Đã xảy ra lỗi khi tải danh sách tài liệu.')}');
      }
    } finally {
      if (mounted && requestVersion == _documentsRequestVersion) {
        setState(() => _documentsLoading = false);
      }
    }
  }

  Future<void> _pickAndUpload() async {
    if (!mounted || _sessionExpired) return;
    if (_uploading) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['txt', 'md', 'csv', 'pdf'],
      );
      if (!mounted || _sessionExpired || file == null) return;
      final fileLength = file.lengthSync() ?? await file.length();
      if (fileLength == null || fileLength <= 0) {
        throw const SafeApiException('Không đọc được kích thước tệp trên thiết bị.');
      }
      if (fileLength > 10 * 1024 * 1024) {
        throw const SafeApiException('Tệp vượt quá giới hạn 10 MB.');
      }
      final bytes = await file.readAsBytes();
      if (!mounted || _sessionExpired) return;
      if (bytes.isEmpty) {
        throw const SafeApiException('Không đọc được nội dung tệp trên thiết bị.');
      }

      final request = http.MultipartRequest(
        'POST',
        _uri('/api/v1/knowledge/documents', {
          'source': 'android_upload',
          'title': file.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
          'category': _uploadCategory,
        }),
      );
      request.headers.addAll(apiAuthHeaders(widget.apiToken));
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: file.name,
      ));
      final streamed = await _httpClient.send(request).timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 409) {
        throw const SafeApiException('Tài liệu này đã được nhập trước đó (trùng nội dung).');
      }
      _checkResponse(response, expectedStatus: 201);
      if (!mounted || _sessionExpired) return;
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã nhập "${payload['title'] ?? file.name}" vào kho tri thức.')),
      );
      if (!mounted || _sessionExpired) return;
      await _loadDocuments();
    } catch (error) {
      if (mounted) setState(() => _error = 'Không nhập được tài liệu: ${_safeError(error, 'Đã xảy ra lỗi khi nhập tài liệu.')}');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _deleteDocument(Map<String, dynamic> document) async {
    if (!mounted || _sessionExpired) return;
    final id = document['id'];
    if (id is! int || _documentActionIds.contains(id)) return;
    setState(() {
      _documentActionIds.add(id);
      _error = null;
    });
    final title = document['title']?.toString() ?? document['filename']?.toString() ?? 'tài liệu';
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Xóa tài liệu?'),
          content: Text('Xóa "$title" khỏi kho tri thức? Các đoạn trích và chỉ mục liên quan cũng sẽ bị xóa.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Xóa'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || _sessionExpired) return;
      final response = await _httpClient.delete(
        _uri('/api/v1/knowledge/documents/$id'),
        headers: apiAuthHeaders(widget.apiToken),
      ).timeout(const Duration(seconds: 20));
      _checkResponse(response, expectedStatus: 200);
      if (!mounted || _sessionExpired) return;
      // Invalidate reads that may have started before this deletion completed.
      _documentsRequestVersion++;
      _searchRequestVersion++;
      setState(() {
        _documentsLoading = false;
        _loading = false;
        _documents.removeWhere((item) => item is Map && item['id'] == id);
        _results.removeWhere((item) => item is Map && item['document_id'] == id);
        _context = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã xóa tài liệu khỏi kho tri thức.')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = 'Không xóa được tài liệu: ${_safeError(error, 'Đã xảy ra lỗi khi xóa tài liệu.')}');
    } finally {
      if (mounted) setState(() => _documentActionIds.remove(id));
    }
  }

  Future<void> _search() async {
    if (!mounted || _sessionExpired) return;
    final requestVersion = ++_searchRequestVersion;
    final query = _queryController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Nhập nội dung cần tìm trong kho tri thức.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
    });
    try {
      final response = await _httpClient.get(
        _uri('/api/v1/knowledge/search', {
          'q': query,
          'top_k': '8',
          if (_categoryFilter != 'all') 'category': _categoryFilter,
        }),
        headers: apiAuthHeaders(widget.apiToken),
      ).timeout(const Duration(seconds: 20));
      _checkResponse(response, expectedStatus: 200);
      if (!mounted || _sessionExpired) return;
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (requestVersion != _searchRequestVersion) return;
      setState(() {
        _results = payload['results'] as List<dynamic>? ?? [];
        _context = payload['retrieval_context'] as Map<String, dynamic>?;
      });
    } catch (error) {
      if (mounted && requestVersion == _searchRequestVersion) {
        setState(() => _error = 'Không tìm kiếm được: ${_safeError(error, 'Đã xảy ra lỗi khi tìm kiếm.')}');
      }
    } finally {
      if (mounted && requestVersion == _searchRequestVersion) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadDocuments();
    _loadTrainingData();
  }

  @override
  void dispose() {
    if (_ownsHttpClient) _httpClient.close();
    _queryController.dispose();
    _trainingQuestionController.dispose();
    _trainingAnswerController.dispose();
    _trainingTopicController.dispose();
    _trainingCitationsController.dispose();
    super.dispose();
  }

  Widget _resultCard(Map<String, dynamic> item) {
    final title = item['title']?.toString().trim();
    final filename = item['filename']?.toString() ?? 'Tài liệu';
    final citation = item['citation_id']?.toString() ?? 'Không có mã trích dẫn';
    final source = item['source']?.toString() ?? 'Nguồn chưa khai báo';
    final text = item['text']?.toString() ?? '';
    final score = item['score'];
    final chunkIndex = item['chunk_index'];
    final charStart = item['char_start'];
    final charEnd = item['char_end'];
    final sourceLocator = chunkIndex is int && charStart is int && charEnd is int
        ? 'Đoạn $chunkIndex • Ký tự $charStart–$charEnd'
        : 'Chưa có tọa độ đoạn nguồn';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title == null || title.isEmpty ? filename : title,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 5),
            Text('Nhóm: ${_categoryLabel(item['category']?.toString())} • Nguồn: $source • Điểm khớp: ${score is num ? score.toStringAsFixed(3) : '—'}'),
            const SizedBox(height: 4),
            Text(
              sourceLocator,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.secondary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            SelectableText(text),
            const Divider(height: 18),
            Row(
              children: [
                const Icon(Icons.link, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: SelectableText(citation, style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  )),
                ),
                IconButton(
                  tooltip: 'Sao chép mã trích dẫn',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: citation));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Đã sao chép mã trích dẫn')),
                    );
                  },
                  icon: const Icon(Icons.content_copy, size: 18),
                ),
                IconButton(
                  tooltip: 'Đưa mã trích dẫn vào biểu mẫu huấn luyện',
                  onPressed: RegExp(r'^kb:\d+:\d+$').hasMatch(citation)
                      ? () {
                          final existing = _trainingCitationsController.text
                              .split(',')
                              .map((value) => value.trim())
                              .where((value) => value.isNotEmpty)
                              .toList();
                          if (existing.contains(citation)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Mã trích dẫn đã có trong biểu mẫu.')),
                            );
                            return;
                          }
                          setState(() {
                            _trainingCitationsController.text =
                                [...existing, citation].join(', ');
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Đã thêm mã trích dẫn vào biểu mẫu.')),
                          );
                        }
                      : null,
                  icon: const Icon(Icons.playlist_add, size: 20),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _documentCard(Map<String, dynamic> item) {
    final title = item['title']?.toString() ?? item['filename']?.toString() ?? 'Tài liệu';
    final size = item['size_bytes'];
    final chunks = item['chunk_count'] ?? 0;
    final created = item['created_at']?.toString();
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.description_outlined)),
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${_categoryLabel(item['category']?.toString())} • ${item['filename'] ?? ''} • $chunks đoạn • ${size is num ? (size / 1024).toStringAsFixed(1) : '—'} KB'
          '${created == null ? '' : '\n$created'}',
        ),
        isThreeLine: true,
        trailing: IconButton(
          tooltip: _documentActionIds.contains(item['id']) ? 'Đang xóa tài liệu' : 'Xóa tài liệu',
          icon: _documentActionIds.contains(item['id'])
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.delete_outline),
          onPressed: item['id'] is int && _documentActionIds.contains(item['id'])
              ? null
              : () => _deleteDocument(item),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _context?['status']?.toString();
    return Scaffold(
      appBar: AppBar(title: const Text('Hybrid AI Training Room')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Quản lý tài liệu', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  const Text('Nhập tài liệu TXT, Markdown, CSV hoặc PDF có văn bản chọn được. Giới hạn 10 MB/tệp; PDF scan cần OCR nên chưa hỗ trợ.'),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _uploadCategory,
                    decoration: const InputDecoration(
                      labelText: 'Phân loại tài liệu nhập vào',
                      border: OutlineInputBorder(),
                    ),
                    items: _categories.entries
                        .where((entry) => entry.key != 'all')
                        .map((entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ))
                        .toList(),
                    onChanged: _uploading ? null : (value) {
                      if (value != null) setState(() => _uploadCategory = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _uploading ? null : _pickAndUpload,
                      icon: _uploading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.upload_file),
                      label: Text(_uploading ? 'Đang chọn hoặc nhập tài liệu...' : 'Chọn tài liệu từ điện thoại'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: Text('Đã lưu: ${_documents.length} tài liệu')),
                      IconButton(
                        tooltip: 'Làm mới danh sách',
                        onPressed: _documentsLoading ? null : _loadDocuments,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  if (_documentsLoading) const LinearProgressIndicator(),
                ],
              ),
            ),
          ),
          if (_documents.isEmpty && !_documentsLoading)
            const Card(child: Padding(
              padding: EdgeInsets.all(14),
              child: Text('Kho tri thức chưa có tài liệu. Hãy chọn tệp để bắt đầu.'),
            ))
          else
            ..._documents.whereType<Map<String, dynamic>>().map(_documentCard),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bộ ví dụ huấn luyện có kiểm duyệt', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  const Text('Tạo cặp câu hỏi–đáp án chuẩn dựa trên tài liệu đã nạp. Mỗi ví dụ phải gắn mã trích dẫn nguồn; ví dụ mới chờ duyệt và chỉ ví dụ đã duyệt mới được xuất.'),
                  const SizedBox(height: 12),
                  TextField(key: const ValueKey('training-create-question'), controller: _trainingQuestionController, enabled: !_savingExample && _createOutcome == _TrainingCreateOutcome.idle && !_sessionExpired, maxLength: 1000, minLines: 2, maxLines: 3, decoration: const InputDecoration(labelText: 'Câu hỏi mẫu', helperText: 'Tối thiểu 10 ký tự', border: OutlineInputBorder())),
                  const SizedBox(height: 8),
                  TextField(key: const ValueKey('training-create-answer'), controller: _trainingAnswerController, enabled: !_savingExample && _createOutcome == _TrainingCreateOutcome.idle && !_sessionExpired, maxLength: 5000, minLines: 3, maxLines: 5, decoration: const InputDecoration(labelText: 'Đáp án chuẩn đã kiểm chứng', helperText: 'Tối thiểu 20 ký tự', border: OutlineInputBorder())),
                  const SizedBox(height: 8),
                  TextField(key: const ValueKey('training-create-topic'), controller: _trainingTopicController, enabled: !_savingExample && _createOutcome == _TrainingCreateOutcome.idle && !_sessionExpired, maxLength: 80, decoration: const InputDecoration(labelText: 'Chủ đề', border: OutlineInputBorder())),
                  const SizedBox(height: 8),
                  TextField(key: const ValueKey('training-create-citations'), controller: _trainingCitationsController, enabled: !_savingExample && _createOutcome == _TrainingCreateOutcome.idle && !_sessionExpired, maxLength: 1000, decoration: const InputDecoration(labelText: 'Mã nguồn (kb:document:chunk)', helperText: 'Lấy citation_id từ kết quả tra cứu kho tri thức; phân tách nhiều mã bằng dấu phẩy.', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  SizedBox(width: double.infinity, child: FilledButton.icon(key: const ValueKey('training-create-submit'), onPressed: _savingExample || _sessionExpired || _createOutcome != _TrainingCreateOutcome.idle ? null : _saveTrainingExample, icon: const Icon(Icons.playlist_add), label: Text(_savingExample ? 'Đang lưu...' : _createOutcome == _TrainingCreateOutcome.submitting ? 'Đang gửi...' : 'Lưu ví dụ chờ duyệt'))),
                  if (_trainingCreateError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _trainingCreateError!,
                      key: const ValueKey('training-create-error'),
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  if (_createOutcome != _TrainingCreateOutcome.idle)
                    _buildCreateOutcomePanel(),
                  const Divider(height: 24),
                  if (_trainingDataLoading) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    const Text('Đang tải dữ liệu huấn luyện...'),
                  ],
                  if (_evaluation == null && !_trainingDataLoading)
                    OutlinedButton.icon(
                      key: const ValueKey('training-data-retry'),
                      onPressed: _sessionExpired ? null : _loadTrainingData,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Thử tải lại dữ liệu huấn luyện'),
                    ),
                  if (_evaluation != null) ...[
                    Text('Tổng: ${_evaluation!['total_examples'] ?? 0} • Đã duyệt: ${_evaluation!['approved_examples'] ?? 0} • Chờ duyệt: ${_evaluation!['draft_examples'] ?? 0}'),
                    Text('Câu hỏi trùng: ${_evaluation!['duplicate_question_groups'] ?? 0} • Trạng thái: ${_evaluation!['readiness'] ?? '—'}'),
                    Wrap(spacing: 8, children: [
                      OutlinedButton.icon(
                        onPressed: _trainingDataLoading ? null : _loadTrainingData,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Cập nhật'),
                      ),
                      OutlinedButton.icon(
                        onPressed: !_trainingDataLoading && !_exportingTraining
                            ? _saveTrainingExport
                            : null,
                        icon: _exportingTraining
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.save_alt),
                        label: Text(_exportingTraining ? 'Đang xuất...' : 'Lưu JSONL đã duyệt'),
                      ),
                      OutlinedButton.icon(
                        onPressed: !_trainingDataLoading && !_exportingTraining
                            ? _copyTrainingExport
                            : null,
                        icon: const Icon(Icons.copy),
                        label: const Text('Sao chép JSONL'),
                      ),
                    ]),
                  ],
                  if (!_trainingDataLoading && _examples.isEmpty)
                    const Text('Chưa có ví dụ huấn luyện. Hãy nạp tài liệu, tra cứu nguồn rồi tạo ví dụ đầu tiên.'),
                  ..._examples.whereType<Map<String, dynamic>>().map((item) {
                    final id = item['id'];
                    final statusValue = item['status']?.toString() ?? 'draft';
                    final statusLabel = switch (statusValue) {
                      'approved' => 'Đã duyệt',
                      'rejected' => 'Đã từ chối',
                      _ => 'Chờ duyệt',
                    };
                    final citations = (item['citation_ids'] as List<dynamic>? ?? const []).join(', ');
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [Expanded(child: Text(item['topic']?.toString() ?? 'general')), Chip(label: Text(statusLabel))]),
                          Text(item['question']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(item['expected_answer']?.toString() ?? ''),
                          Text('Nguồn đã gắn: $citations', style: Theme.of(context).textTheme.bodySmall),
                          if (item['citation_ids'] is List) ...[
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: (item['citation_ids'] as List<dynamic>)
                                  .whereType<String>()
                                  .map((citation) => OutlinedButton.icon(
                                        key: ValueKey('citation-open-$citation'),
                                        onPressed: _citationLoadingIds.contains(citation)
                                            ? null
                                            : () => _openCitationDetail(citation),
                                        icon: _citationLoadingIds.contains(citation)
                                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                            : const Icon(Icons.menu_book_outlined, size: 16),
                                        label: Text('Xem nguồn $citation'),
                                      ))
                                  .toList(),
                            ),
                          ],
                          if (id is int) ...[
                            const SizedBox(height: 6),
                            Text('Revision ${item['revision'] ?? 1}', style: Theme.of(context).textTheme.bodySmall),
                            TrainingReviewControls(
                              key: ValueKey('training-review-$id'),
                              baseUrl: widget.baseUrl,
                              apiToken: widget.apiToken,
                              httpClient: _httpClient,
                              example: item,
                              onSessionExpired: widget.onSessionExpired,
                              onRefresh: _loadTrainingData,
                              onApprove: () => _approveTrainingExample(id),
                              onDelete: () => _deleteTrainingExample(id),
                            ),
                          ],
                        ]),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tra cứu kho tri thức', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _categoryFilter,
                    decoration: const InputDecoration(
                      labelText: 'Lọc theo nhóm tài liệu',
                      border: OutlineInputBorder(),
                    ),
                    items: _categories.entries
                        .map((entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _categoryFilter = value);
                      _loadDocuments();
                      if (_searched && _queryController.text.trim().isNotEmpty) {
                        _search();
                      }
                    },
                  ),
                  const SizedBox(height: 6),
                  const Text('Tìm kiếm cục bộ trong tài liệu đã nhập. Kết quả là đoạn trích có nguồn, chưa phải câu trả lời do AI tổng hợp.'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _queryController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _loading ? null : _search(),
                    decoration: const InputDecoration(
                      labelText: 'Ví dụ: Fibonacci, Elliott Wave, quản trị rủi ro',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _search,
                      icon: const Icon(Icons.manage_search),
                      label: Text(_loading ? 'Đang tìm...' : 'Tìm trong tài liệu'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Card(child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            )),
          if (_searched && !_loading && _error == null) ...[
            const SizedBox(height: 12),
            Text(
              status == 'ready' ? 'Tìm thấy ${_results.length} đoạn tài liệu' : 'Chưa tìm thấy bằng chứng phù hợp',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_results.isEmpty)
              const Card(child: Padding(
                padding: EdgeInsets.all(14),
                child: Text('Không có đoạn phù hợp với từ khóa.'),
              ))
            else
              ..._results.whereType<Map<String, dynamic>>().map(_resultCard),
            if (_context != null)
              Card(child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Kiểm soát ngữ cảnh', style: TextStyle(fontWeight: FontWeight.w600)),
                    Text('Phương pháp: ${_context!['retrieval_method'] ?? '—'}'),
                    Text('Ký tự đưa vào ngữ cảnh: ${_context!['characters_used'] ?? 0}'),
                    Text('Trích dẫn hợp lệ: ${(_context!['citations'] as List<dynamic>? ?? const []).length}'),
                    const SizedBox(height: 6),
                    const Text('Nội dung tài liệu được xem là bằng chứng không đáng tin cậy, không được phép ghi đè quy tắc hệ thống.'),
                  ],
                ),
              )),
          ],
          const SizedBox(height: 12),
          const Text('Tìm kiếm hiện dùng BM25-style lexical retrieval miễn phí trên backend. Chưa bật embedding, mô hình sinh câu trả lời hay API AI trả phí.'),
        ],
      ),
    );
  }
}
