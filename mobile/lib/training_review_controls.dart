// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_auth.dart';

class TrainingReviewControls extends StatefulWidget {
  const TrainingReviewControls({
    super.key,
    required this.baseUrl,
    required this.apiToken,
    required this.httpClient,
    required this.example,
    required this.onRefresh,
    required this.onApprove,
    required this.onDelete,
    this.onSessionExpired,
  });

  final String baseUrl;
  final String apiToken;
  final http.Client httpClient;
  final Map<String, dynamic> example;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onApprove;
  final Future<void> Function() onDelete;
  final SessionExpiredCallback? onSessionExpired;

  @override
  State<TrainingReviewControls> createState() => _TrainingReviewControlsState();
}

class _TrainingReviewControlsState extends State<TrainingReviewControls> {
  bool _busy = false;
  bool _sessionExpired = false;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse(widget.baseUrl + path).replace(queryParameters: query);

  void _check(http.Response response, int expected) {
    if (response.statusCode == 401) {
      if (!_sessionExpired) {
        _sessionExpired = true;
        if (mounted) setState(() {});
        widget.onSessionExpired?.call(widget.apiToken);
      }
      throw const ApiRequestException(401);
    }
    if (response.statusCode != expected) {
      throw ApiRequestException(response.statusCode);
    }
  }

  String _error(Object error) => safeApiErrorMessage(
    error, fallback: 'Không thể hoàn thành thao tác. Vui lòng thử lại.');

  bool _validReviewEvent(dynamic value) {
    if (value is! Map<String, dynamic>) return false;
    final fields = value['changed_fields'];
    return value['id'] is int &&
        value['example_id'] is int &&
        value['action'] is String &&
        (value['reason'] == null || value['reason'] is String) &&
        value['revision_from'] is int &&
        value['revision_to'] is int &&
        fields is List && fields.every((field) => field is String) &&
        (value['reviewer_user_id'] == null || value['reviewer_user_id'] is int) &&
        value['reviewer_label'] is String &&
        value['created_at'] is String;
  }

  bool _validQualityReview(dynamic value) {
    if (value is! Map<String, dynamic>) return false;
    final score = value['score'];
    return value['id'] is int &&
        value['example_id'] is int &&
        value['example_revision'] is int &&
        score is int && score >= 0 && score <= 100 &&
        value['rubric_version'] is String &&
        value['rationale'] is String &&
        (value['reviewer_user_id'] == null || value['reviewer_user_id'] is int) &&
        value['reviewed_at'] is String;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (!mounted || _busy || _sessionExpired) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted && !_sessionExpired) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_error(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final id = widget.example['id'];
    if (id is! int || widget.example['status'] != 'draft' || _sessionExpired) return;
    var reasonText = '';
    String? validation;
    final reason = await showDialog<String>(context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, refresh) =>
        AlertDialog(
          title: const Text('Từ chối ví dụ nháp'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Nhập lý do từ 1 đến 1.000 ký tự. Ví dụ sẽ không bị xóa.'),
            TextFormField(key: const ValueKey('reject-reason'), initialValue: '',
              onChanged: (value) => reasonText = value,
              maxLength: 1000, minLines: 2, maxLines: 4,
              decoration: InputDecoration(labelText: 'Lý do', errorText: validation,
                border: const OutlineInputBorder())),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Hủy')),
            FilledButton(key: const ValueKey('reject-confirm'), onPressed: () {
              final value = reasonText.trim();
              if (value.isEmpty || value.length > 1000) {
                refresh(() => validation = 'Lý do phải có 1–1.000 ký tự.');
                return;
              }
              Navigator.pop(dialogContext, value);
            }, child: const Text('Từ chối')),
          ],
        )));
    if (reason == null || !mounted || _sessionExpired) return;
    await _run(() async {
      final response = await widget.httpClient.post(
        _uri('/api/v1/training/examples/' + id.toString() + '/reject'),
        headers: {'Content-Type': 'application/json', ...apiAuthHeaders(widget.apiToken)},
        body: jsonEncode({'reason': reason}),
      ).timeout(const Duration(seconds: 20));
      _check(response, 200);
      await widget.onRefresh();
      if (mounted && !_sessionExpired) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã từ chối ví dụ. Lý do được lưu trong lịch sử.')));
      }
    });
  }

  Future<Map<String, dynamic>?> _fetchLatest(int id) async {
    final response = await widget.httpClient.get(
      _uri('/api/v1/training/examples', {'limit': '100', 'offset': '0'}),
      headers: apiAuthHeaders(widget.apiToken),
    ).timeout(const Duration(seconds: 20));
    _check(response, 200);
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic> || data['items'] is! List) {
      throw const SafeApiException('Danh sách ví dụ không hợp lệ.');
    }
    for (final row in data['items'] as List) {
      if (row is Map<String, dynamic> && row['id'] == id) return row;
    }
    return null;
  }

  bool _validCitationList(List<String> values) {
    if (values.isEmpty || values.length > 10 || values.toSet().length != values.length) {
      return false;
    }
    for (final value in values) {
      final parts = value.split(':');
      if (parts.length != 3 || parts[0] != 'kb' ||
          int.tryParse(parts[1]) == null || int.tryParse(parts[2]) == null) {
        return false;
      }
    }
    return true;
  }

  Future<void> _edit() async {
    final id = widget.example['id'];
    if (id is! int || widget.example['status'] != 'draft' ||
        _sessionExpired || _busy) {
      return;
    }
    // Keep the card's actions disabled from dialog open through the PATCH,
    // including the stale-revision comparison loop.
    setState(() => _busy = true);
    var questionText = widget.example['question']?.toString() ?? '';
    var answerText = widget.example['expected_answer']?.toString() ?? '';
    var topicText = widget.example['topic']?.toString() ?? '';
    var citationText = (widget.example['citation_ids'] as List<dynamic>? ?? const []).join(', ');
    var current = Map<String, dynamic>.from(widget.example);
    var revision = current['revision'] is int ? current['revision'] as int : 1;
    var finished = false;
    try {
      while (!finished && mounted && !_sessionExpired) {
        if (!mounted || _sessionExpired) break;
        final draft = await showDialog<Map<String, dynamic>>(context: context,
          barrierDismissible: false, builder: (dialogContext) => AlertDialog(
            title: Text('Sửa ví dụ #' + id.toString() + ' • revision ' + revision.toString()),
            content: SizedBox(width: 560, child: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min, children: [
                TextFormField(key: const ValueKey('edit-question'), initialValue: questionText,
                  onChanged: (value) => questionText = value,
                  maxLength: 1000, minLines: 2, maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Câu hỏi', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextFormField(key: const ValueKey('edit-answer'), initialValue: answerText,
                  onChanged: (value) => answerText = value,
                  maxLength: 5000, minLines: 3, maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Đáp án chuẩn', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextFormField(key: const ValueKey('edit-topic'), initialValue: topicText,
                  onChanged: (value) => topicText = value, maxLength: 80,
                  decoration: const InputDecoration(labelText: 'Chủ đề', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextFormField(key: const ValueKey('edit-citations'), initialValue: citationText,
                  onChanged: (value) => citationText = value, maxLength: 1000,
                  decoration: const InputDecoration(labelText: 'Citation IDs (phân tách bằng dấu phẩy)',
                    border: OutlineInputBorder())),
              ]))),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Hủy')),
              FilledButton(key: const ValueKey('edit-save'), onPressed: () {
                final values = citationText.split(',').map((v) => v.trim())
                  .where((v) => v.isNotEmpty).toList();
                if (questionText.trim().length < 10 || questionText.trim().length > 1000 ||
                    answerText.trim().length < 20 || answerText.trim().length > 5000 ||
                    topicText.trim().isEmpty || topicText.trim().length > 80 ||
                    !_validCitationList(values)) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Kiểm tra giới hạn nội dung và 1–10 citation hợp lệ.')));
                  return;
                }
                Navigator.pop(dialogContext, {
                  'question': questionText.trim(),
                  'expected_answer': answerText.trim(),
                  'topic': topicText.trim(),
                  'citation_ids': values,
                });
              }, child: const Text('Lưu thay đổi')),
            ],
          ));
        if (draft == null || !mounted || _sessionExpired) break;
        final body = <String, dynamic>{'expected_revision': revision};
        if (draft['question'] != current['question']) body['question'] = draft['question'];
        if (draft['expected_answer'] != current['expected_answer']) body['expected_answer'] = draft['expected_answer'];
        if (draft['topic'] != current['topic']) body['topic'] = draft['topic'];
        final oldCitations = (current['citation_ids'] as List<dynamic>? ?? const []).cast<String>();
        if (jsonEncode(draft['citation_ids']) != jsonEncode(oldCitations)) {
          body['citation_ids'] = draft['citation_ids'];
        }
        if (body.length == 1) break;
        try {
          final response = await widget.httpClient.patch(
            _uri('/api/v1/training/examples/' + id.toString()),
            headers: {'Content-Type': 'application/json', ...apiAuthHeaders(widget.apiToken)},
            body: jsonEncode(body),
          ).timeout(const Duration(seconds: 20));
          _check(response, 200);
          finished = true;
          await widget.onRefresh();
          if (mounted && !_sessionExpired) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Đã lưu phiên bản mới của ví dụ.')));
          }
        } on ApiRequestException catch (error) {
          if (error.statusCode != 409) rethrow;
          final latest = await _fetchLatest(id);
          if (!mounted || _sessionExpired) return;
          if (latest == null) throw const SafeApiException('Ví dụ không còn tồn tại.');
          final keep = await showDialog<bool>(context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Revision đã thay đổi'),
              content: SizedBox(width: 540, child: SingleChildScrollView(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Bản đang sửa được giữ nguyên. Hãy đối chiếu với dữ liệu mới trước khi tiếp tục.'),
                  const Text('BẢN ĐANG SỬA', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('Câu hỏi: ' + draft['question'].toString()),
                  Text('Đáp án: ' + draft['expected_answer'].toString()),
                  Text('Chủ đề: ' + draft['topic'].toString()),
                  Text('Citation: ' + (draft['citation_ids'] as List).join(', ')),
                  const Divider(),
                  const Text('BẢN TRÊN MÁY CHỦ', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('Câu hỏi: ' + latest['question'].toString()),
                  Text('Đáp án: ' + latest['expected_answer'].toString()),
                  Text('Chủ đề: ' + latest['topic'].toString()),
                  Text('Citation: ' + (latest['citation_ids'] as List? ?? const []).join(', ')),
                  Text('Revision: ' + latest['revision'].toString()),
                ]))),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Đóng')),
                FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Tiếp tục trên revision mới')),
              ]));
          if (keep == true) {
            current = latest;
            revision = latest['revision'] is int ? latest['revision'] as int : revision;
          } else {
            break;
          }
        }
      }
    } catch (error) {
      if (mounted && !_sessionExpired) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_error(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _qualityReview() async {
    final id = widget.example['id'];
    if (id is! int || _sessionExpired) return;
    var scoreText = '';
    var rationaleText = '';
    String rubric = 'qa-quality-v1';
    String? validation;
    final payload = await showDialog<Map<String, dynamic>>(context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, refresh) =>
        AlertDialog(
          title: Text('Human Quality Review • #' + id.toString()),
          content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Điểm do con người nhập; không lấy từ prediction metrics và không tự chấm bằng AI.'),
              TextFormField(key: const ValueKey('quality-score'), initialValue: '',
                onChanged: (value) => scoreText = value,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Điểm nguyên 0–100', errorText: validation,
                  border: const OutlineInputBorder())),
              DropdownButtonFormField<String>(initialValue: rubric,
                decoration: const InputDecoration(labelText: 'Rubric', border: OutlineInputBorder()),
                items: const [DropdownMenuItem(value: 'qa-quality-v1', child: Text('qa-quality-v1'))],
                onChanged: (value) { if (value != null) refresh(() => rubric = value); }),
              TextFormField(key: const ValueKey('quality-rationale'), initialValue: '',
                onChanged: (value) => rationaleText = value,
                maxLength: 2000, minLines: 3, maxLines: 5,
                decoration: const InputDecoration(labelText: 'Nhận xét (10–2.000 ký tự)',
                  border: OutlineInputBorder())),
            ]))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Hủy')),
            FilledButton(key: const ValueKey('quality-submit'), onPressed: () {
              final raw = scoreText.trim();
              final value = int.tryParse(raw);
              if (value == null || value < 0 || value > 100 ||
                  rationaleText.trim().length < 10 || rationaleText.trim().length > 2000) {
                refresh(() => validation = 'Điểm nguyên 0–100 và nhận xét 10–2.000 ký tự là bắt buộc.');
                return;
              }
              Navigator.pop(dialogContext, {
                'score': value, 'rubric_version': rubric,
                'rationale': rationaleText.trim(),
              });
            }, child: const Text('Gửi đánh giá')),
          ],
        )));
    if (payload == null || !mounted || _sessionExpired) return;
    await _run(() async {
      final response = await widget.httpClient.post(
        _uri('/api/v1/training/examples/' + id.toString() + '/quality-reviews'),
        headers: {'Content-Type': 'application/json', ...apiAuthHeaders(widget.apiToken)},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 20));
      _check(response, 201);
      if (mounted && !_sessionExpired) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu đánh giá thủ công. Trạng thái ví dụ không thay đổi.')));
      }
    });
  }

  Future<void> _history() async {
    final id = widget.example['id'];
    if (id is! int || _sessionExpired) return;
    await _run(() async {
      final headers = apiAuthHeaders(widget.apiToken);
      final responses = await Future.wait([
        widget.httpClient.get(_uri('/api/v1/training/examples/' + id.toString() + '/review-events',
          {'limit': '50', 'offset': '0'}), headers: headers).timeout(const Duration(seconds: 20)),
        widget.httpClient.get(_uri('/api/v1/training/examples/' + id.toString() + '/quality-reviews'),
          headers: headers).timeout(const Duration(seconds: 20)),
      ]);
      // A concurrent protected 401 must take precedence over a sibling 403/5xx,
      // so session expiry cannot be masked by response ordering.
      final unauthorized = responses.where((response) => response.statusCode == 401);
      if (unauthorized.isNotEmpty) {
        _check(unauthorized.first, 200);
      }
      for (final response in responses) { _check(response, 200); }
      final page = jsonDecode(responses[0].body);
      final qualityPage = jsonDecode(responses[1].body);
      if (page is! Map<String, dynamic> || page['items'] is! List ||
          page['example_id'] != id || page['count'] is! int ||
          page['total'] is! int || page['limit'] is! int ||
          page['offset'] is! int ||
          qualityPage is! Map<String, dynamic> || qualityPage['items'] is! List ||
          qualityPage['example_id'] != id || qualityPage['count'] is! int) {
        throw const SafeApiException('Dữ liệu lịch sử review không hợp lệ.');
      }
      final rawEvents = page['items'] as List;
      final rawQuality = qualityPage['items'] as List;
      if (page['count'] != rawEvents.length ||
          page['limit'] < 1 || page['limit'] > 100 || page['offset'] < 0 ||
          !rawEvents.every(_validReviewEvent) ||
          qualityPage['count'] != rawQuality.length ||
          !rawQuality.every(_validQualityReview)) {
        throw const SafeApiException('Dữ liệu lịch sử review không hợp lệ.');
      }
      if (!mounted || _sessionExpired) return;
      final events = List<dynamic>.from(rawEvents);
      final quality = rawQuality;
      var total = page['total'] as int;
      final limit = page['limit'] as int;
      var loadingMore = false;
      var historyError = '';
      if (!mounted || _sessionExpired) return;
      await showDialog<void>(context: context, builder: (dialogContext) =>
        StatefulBuilder(builder: (context, refresh) => AlertDialog(
          title: Text('Lịch sử review • ví dụ #' + id.toString()),
          content: SizedBox(width: 620, height: 520, child: ListView(children: [
            Text('Review events (' + total.toString() + ')',
              style: Theme.of(context).textTheme.titleMedium),
            if (events.isEmpty) const Text('Chưa có approve/reject/edit event.'),
            ...events.whereType<Map<String, dynamic>>().map((event) {
              final action = switch (event['action']) {
                'approved' => 'Đã duyệt', 'rejected' => 'Đã từ chối',
                'edited' => 'Đã chỉnh sửa', _ => 'Sự kiện review',
              };
              return ListTile(
                title: Text(action + ' • revision ' + event['revision_from'].toString() +
                  ' → ' + event['revision_to'].toString()),
                subtitle: Text([
                  if (event['reason'] is String && (event['reason'] as String).isNotEmpty)
                    'Lý do: ' + event['reason'].toString(),
                  'Người thực hiện: ' + (event['reviewer_label'] ?? '—').toString() +
                    (event['reviewer_user_id'] == null ? '' : ' (#' + event['reviewer_user_id'].toString() + ')'),
                  'Thời gian máy chủ: ' + (event['created_at'] ?? '—').toString(),
                  if (event['changed_fields'] is List && (event['changed_fields'] as List).isNotEmpty)
                    'Trường đã sửa: ' + (event['changed_fields'] as List).join(', '),
                ].join('\n')),
              );
            }),
            if (events.length < total)
              Center(child: OutlinedButton(
                onPressed: loadingMore ? null : () async {
                  refresh(() { loadingMore = true; historyError = ''; });
                  try {
                    final nextOffset = events.length;
                    final response = await widget.httpClient.get(
                      _uri('/api/v1/training/examples/' + id.toString() + '/review-events',
                        {'limit': limit.toString(), 'offset': nextOffset.toString()}),
                      headers: headers,
                    ).timeout(const Duration(seconds: 20));
                    _check(response, 200);
                    final next = jsonDecode(response.body);
                    if (next is! Map<String, dynamic> || next['items'] is! List ||
                        next['example_id'] != id || next['count'] is! int ||
                        next['total'] is! int || next['limit'] != limit ||
                        next['offset'] != nextOffset) {
                      throw const SafeApiException('Trang lịch sử review không hợp lệ.');
                    }
                    final nextItems = next['items'] as List;
                    if (next['count'] != nextItems.length ||
                        !nextItems.every(_validReviewEvent)) {
                      throw const SafeApiException('Trang lịch sử review không hợp lệ.');
                    }
                    if (dialogContext.mounted) {
                      refresh(() {
                        events.addAll(next['items'] as List);
                        total = next['total'] as int;
                      });
                    }
                  } catch (error) {
                    if (dialogContext.mounted) refresh(() => historyError = _error(error));
                  } finally {
                    if (dialogContext.mounted) refresh(() => loadingMore = false);
                  }
                },
                child: Text(loadingMore ? 'Đang tải...' : 'Tải thêm lịch sử'),
              )),
            if (historyError.isNotEmpty)
              Text(historyError, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const Divider(height: 28),
            Text('Human Quality Review (' + quality.length.toString() + ')',
              style: Theme.of(context).textTheme.titleMedium),
            if (quality.isEmpty) const Text('Chưa có đánh giá chất lượng thủ công.'),
            ...quality.whereType<Map<String, dynamic>>().map((review) => ListTile(
              title: Text('Điểm ' + review['score'].toString() + '/100 • ' + review['rubric_version'].toString()),
              subtitle: Text([
                'Revision được đánh giá: ' + (review['example_revision'] ?? '—').toString(),
                'Nhận xét: ' + (review['rationale'] ?? '—').toString(),
                'Reviewer ID: ' + (review['reviewer_user_id'] ?? '—').toString(),
                'Thời gian máy chủ: ' + (review['reviewed_at'] ?? '—').toString(),
              ].join('\n')),
            )),
          ])),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Đóng'))],
        )));
    });
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.example['id'];
    final isDraft = widget.example['status'] == 'draft';
    if (id is! int) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 4, children: [
      if (isDraft) ...[
        TextButton.icon(
          onPressed: (_busy || _sessionExpired) ? null : () => _run(widget.onApprove),
          icon: const Icon(Icons.verified_outlined), label: const Text('Duyệt')),
        TextButton.icon(
          onPressed: (_busy || _sessionExpired) ? null : _edit,
          icon: const Icon(Icons.edit_outlined), label: const Text('Sửa')),
        TextButton.icon(
          onPressed: (_busy || _sessionExpired) ? null : _reject,
          icon: const Icon(Icons.block_outlined), label: const Text('Từ chối')),
      ],
      TextButton.icon(
        onPressed: (_busy || _sessionExpired) ? null : _qualityReview,
        icon: const Icon(Icons.fact_check_outlined), label: const Text('Human Quality Review')),
      TextButton.icon(
        onPressed: (_busy || _sessionExpired) ? null : _history,
        icon: const Icon(Icons.history), label: const Text('Lịch sử')),
      TextButton.icon(
        onPressed: (_busy || _sessionExpired) ? null : () => _run(widget.onDelete),
        icon: const Icon(Icons.delete_outline), label: const Text('Xóa')),
    ]);
  }
}
