import 'dart:convert';


import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'api_auth.dart';

typedef TrainingFileSaveCallback = Future<Uri?> Function({
  required String fileName,
  required Uint8List bytes,
});

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

  Future<void> _loadTrainingData() async {
    if (!mounted || _sessionExpired) return;
    final requestVersion = ++_trainingDataRequestVersion;
    if (mounted) {
      setState(() {
        _trainingDataLoading = true;
      });
    }
    try {
      final responses = await Future.wait([
        _httpClient.get(
          _uri('/api/v1/training/examples', {'limit': '100', 'offset': '0'}),
          headers: apiAuthHeaders(widget.apiToken),
        ).timeout(const Duration(seconds: 20)),
        _httpClient.get(
          _uri('/api/v1/training/evaluation'),
          headers: apiAuthHeaders(widget.apiToken),
        ).timeout(const Duration(seconds: 20)),
      ]);
      if (responses.any((response) => response.statusCode == 401)) {
        if (!_sessionExpired) {
          _sessionExpired = true;
          widget.onSessionExpired?.call(widget.apiToken);
        }
        throw const ApiRequestException(401);
      }
      for (final response in responses) {
        _checkResponse(response, expectedStatus: 200);
      }
      if (!mounted || _sessionExpired) return;
      final examples = jsonDecode(responses[0].body) as Map<String, dynamic>;
      final evaluation = jsonDecode(responses[1].body) as Map<String, dynamic>;
      if (!mounted || requestVersion != _trainingDataRequestVersion) return;
      setState(() {
        _examples = examples['items'] as List<dynamic>? ?? [];
        _evaluation = evaluation;
      });
    } catch (error) {
      if (mounted && requestVersion == _trainingDataRequestVersion) {
        setState(() => _error = 'Không tải được bộ dữ liệu huấn luyện: ${_safeError(error, 'Đã xảy ra lỗi khi tải dữ liệu huấn luyện.')}');
      }
    } finally {
      if (mounted && requestVersion == _trainingDataRequestVersion) {
        setState(() => _trainingDataLoading = false);
      }
    }
  }

  Future<void> _saveTrainingExample() async {
    if (!mounted || _sessionExpired) return;
    if (_savingExample) return;
    final question = _trainingQuestionController.text.trim();
    final answer = _trainingAnswerController.text.trim();
    final topic = _trainingTopicController.text.trim();
    final citations = _trainingCitationsController.text
        .split(',').map((item) => item.trim()).where((item) => item.isNotEmpty).toList();
    final citationPattern = RegExp(r'^kb:\d+:\d+$');
    if (question.length < 10 || question.length > 1000 ||
        answer.length < 20 || answer.length > 5000 ||
        topic.length > 80 || citations.isEmpty || citations.length > 10 ||
        citations.any((item) => !citationPattern.hasMatch(item)) ||
        citations.toSet().length != citations.length) {
      setState(() => _error = 'Câu hỏi cần 10–1.000 ký tự, đáp án 20–5.000 ký tự, chủ đề tối đa 80 ký tự; cần 1–10 mã nguồn kb:document_id:chunk_index hợp lệ và không trùng.');
      return;
    }
    setState(() { _savingExample = true; _error = null; });
    try {
      final response = await _httpClient.post(
        _uri('/api/v1/training/examples'),
        headers: {'Content-Type': 'application/json', ...apiAuthHeaders(widget.apiToken)},
        body: jsonEncode({
          'question': question, 'expected_answer': answer,
          'topic': topic.isEmpty ? 'general' : topic, 'citation_ids': citations,
        }),
      ).timeout(const Duration(seconds: 20));
      _checkResponse(response, expectedStatus: 201);
      if (!mounted || _sessionExpired) return;
      _trainingQuestionController.clear();
      _trainingAnswerController.clear();
      _trainingCitationsController.clear();
      await _loadTrainingData();
      if (!mounted || _sessionExpired) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã lưu ví dụ ở trạng thái chờ duyệt.')));
    } catch (error) {
      if (mounted) setState(() => _error = 'Không lưu được ví dụ: ${_safeError(error, 'Đã xảy ra lỗi khi lưu ví dụ.')}');
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
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Không duyệt được ví dụ: ${_safeError(error, 'Đã xảy ra lỗi khi duyệt ví dụ.')}');
      }
    } finally {
      if (mounted) setState(() => _trainingActionIds.remove(id));
    }
  }


  Future<void> _rejectTrainingExample(int id) async {
    if (!mounted || _sessionExpired || _trainingActionIds.contains(id)) return;
    final reasonController = TextEditingController();
    String? validation;
    final reason = await showDialog<String>(context: context, builder: (dialogContext) =>
      StatefulBuilder(builder: (context, refresh) => AlertDialog(
        title: const Text('Từ chối ví dụ nháp'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Nhập lý do từ 1 đến 1.000 ký tự. Ví dụ sẽ không bị xóa.'),
          TextField(key: const ValueKey('reject-reason'), controller: reasonController,
            maxLength: 1000, minLines: 2, maxLines: 4,
            decoration: InputDecoration(labelText: 'Lý do', errorText: validation,
              border: const OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Hủy')),
          FilledButton(key: const ValueKey('reject-confirm'), onPressed: () {
            final value = reasonController.text.trim();
            if (value.isEmpty || value.length > 1000) {
              refresh(() => validation = 'Lý do phải có 1–1.000 ký tự.'); return;
            }
            Navigator.pop(dialogContext, value);
          }, child: const Text('Từ chối')),
        ],
      )));
    reasonController.dispose();
    if (reason == null || !mounted || _sessionExpired) return;
    setState(() { _trainingActionIds.add(id); _error = null; });
    try {
      final response = await _httpClient.post(_uri('/api/v1/training/examples/$id/reject'),
        headers: {'Content-Type': 'application/json', ...apiAuthHeaders(widget.apiToken)},
        body: jsonEncode({'reason': reason})).timeout(const Duration(seconds: 20));
      _checkResponse(response, expectedStatus: 200);
      if (!mounted || _sessionExpired) return;
      await _loadTrainingData();
      if (mounted && !_sessionExpired) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã từ chối ví dụ. Lý do được lưu trong lịch sử.')));
    } catch (error) {
      if (mounted && !_sessionExpired) setState(() =>
        _error = 'Không từ chối được ví dụ: ${_safeError(error, 'Đã xảy ra lỗi khi từ chối.')}');
    } finally {
      if (mounted) setState(() => _trainingActionIds.remove(id));
    }
  }

  Future<Map<String, dynamic>?> _fetchExampleById(int id) async {
    final response = await _httpClient.get(_uri('/api/v1/training/examples',
      {'limit': '100', 'offset': '0'}), headers: apiAuthHeaders(widget.apiToken))
      .timeout(const Duration(seconds: 20));
    _checkResponse(response, expectedStatus: 200);
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic> || data['items'] is! List) {
      throw const SafeApiException('Danh sách ví dụ không hợp lệ.');
    }
    for (final value in data['items'] as List) {
      if (value is Map<String, dynamic> && value['id'] == id) return value;
    }
    return null;
  }

  Future<void> _editTrainingExample(Map<String, dynamic> item) async {
    final id = item['id'];
    if (id is! int || item['status'] != 'draft' || !mounted ||
        _sessionExpired || _trainingActionIds.contains(id)) return;
    final question = TextEditingController(text: item['question']?.toString() ?? '');
    final answer = TextEditingController(text: item['expected_answer']?.toString() ?? '');
    final topic = TextEditingController(text: item['topic']?.toString() ?? '');
    final citations = TextEditingController(
      text: (item['citation_ids'] as List<dynamic>? ?? const []).join(', '));
    var revision = item['revision'] is int ? item['revision'] as int : 1;
    var finished = false;
    setState(() { _trainingActionIds.add(id); _error = null; });
    try {
      while (!finished && mounted && !_sessionExpired) {
        final draft = await showDialog<Map<String, dynamic>>(context: context,
          barrierDismissible: false, builder: (dialogContext) => AlertDialog(
            title: Text('Sửa ví dụ #$id • revision $revision'),
            content: SizedBox(width: 560, child: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min, children: [
                TextField(key: const ValueKey('edit-question'), controller: question,
                  maxLength: 1000, minLines: 2, maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Câu hỏi', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(key: const ValueKey('edit-answer'), controller: answer,
                  maxLength: 5000, minLines: 3, maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Đáp án chuẩn', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(key: const ValueKey('edit-topic'), controller: topic, maxLength: 80,
                  decoration: const InputDecoration(labelText: 'Chủ đề', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(key: const ValueKey('edit-citations'), controller: citations, maxLength: 1000,
                  decoration: const InputDecoration(labelText: 'Citation IDs (phân tách bằng dấu phẩy)',
                    border: OutlineInputBorder())),
              ]))),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Hủy')),
              FilledButton(key: const ValueKey('edit-save'), onPressed: () {
                final c = citations.text.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
                if (question.text.trim().length < 10 || question.text.trim().length > 1000 ||
                    answer.text.trim().length < 20 || answer.text.trim().length > 5000 ||
                    topic.text.trim().isEmpty || topic.text.trim().length > 80 ||
                    c.isEmpty || c.length > 10 || c.toSet().length != c.length ||
                    c.any((v) => !RegExp(r'^kb:\d+:\d+
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
                  TextField(controller: _trainingQuestionController, enabled: !_savingExample, maxLength: 1000, minLines: 2, maxLines: 3, decoration: const InputDecoration(labelText: 'Câu hỏi mẫu', helperText: 'Tối thiểu 10 ký tự', border: OutlineInputBorder())),
                  const SizedBox(height: 8),
                  TextField(controller: _trainingAnswerController, enabled: !_savingExample, maxLength: 5000, minLines: 3, maxLines: 5, decoration: const InputDecoration(labelText: 'Đáp án chuẩn đã kiểm chứng', helperText: 'Tối thiểu 20 ký tự', border: OutlineInputBorder())),
                  const SizedBox(height: 8),
                  TextField(controller: _trainingTopicController, enabled: !_savingExample, maxLength: 80, decoration: const InputDecoration(labelText: 'Chủ đề', border: OutlineInputBorder())),
                  const SizedBox(height: 8),
                  TextField(controller: _trainingCitationsController, enabled: !_savingExample, maxLength: 1000, decoration: const InputDecoration(labelText: 'Mã nguồn (kb:document:chunk)', helperText: 'Lấy citation_id từ kết quả tra cứu kho tri thức; phân tách nhiều mã bằng dấu phẩy.', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _savingExample ? null : _saveTrainingExample, icon: const Icon(Icons.playlist_add), label: Text(_savingExample ? 'Đang lưu...' : 'Lưu ví dụ chờ duyệt'))),
                  const Divider(height: 24),
                  if (_trainingDataLoading) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    const Text('Đang tải dữ liệu huấn luyện...'),
                  ],
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
                    final isDraft = statusValue == 'draft';
                    final statusLabel = switch (statusValue) {
                      'approved' => 'Đã duyệt', 'rejected' => 'Đã từ chối', _ => 'Chờ duyệt',
                    };
                    final revision = item['revision'] ?? 1;
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
                            Wrap(spacing: 8, children: [
                              Text('Revision $revision', style: Theme.of(context).textTheme.bodySmall),
                              if (isDraft) ...[
                                TextButton.icon(onPressed: _trainingActionIds.contains(id) ? null : () => _approveTrainingExample(id),
                                  icon: const Icon(Icons.verified_outlined), label: const Text('Duyệt')),
                                TextButton.icon(onPressed: _trainingActionIds.contains(id) ? null : () => _editTrainingExample(item),
                                  icon: const Icon(Icons.edit_outlined), label: const Text('Sửa')),
                                TextButton.icon(onPressed: _trainingActionIds.contains(id) ? null : () => _rejectTrainingExample(id),
                                  icon: const Icon(Icons.block_outlined), label: const Text('Từ chối')),
                              ],
                              TextButton.icon(onPressed: _trainingActionIds.contains(id) ? null : () => _createQualityReview(id),
                                icon: const Icon(Icons.fact_check_outlined), label: const Text('Human Quality Review')),
                              TextButton.icon(onPressed: _trainingActionIds.contains(id) ? null : () => _openReviewHistory(id),
                                icon: const Icon(Icons.history), label: const Text('Lịch sử')),
                              TextButton.icon(onPressed: _trainingActionIds.contains(id) ? null : () => _deleteTrainingExample(id),
                                icon: const Icon(Icons.delete_outline), label: const Text('Xóa')),
                            ]),
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
).hasMatch(v))) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Kiểm tra giới hạn nội dung và 1–10 citation hợp lệ.')));
                  return;
                }
                Navigator.pop(dialogContext, {'question': question.text.trim(),
                  'expected_answer': answer.text.trim(), 'topic': topic.text.trim(),
                  'citation_ids': c});
              }, child: const Text('Lưu thay đổi')),
            ],
          ));
        if (draft == null || !mounted || _sessionExpired) break;
        final body = <String, dynamic>{'expected_revision': revision};
        if (draft['question'] != item['question']) body['question'] = draft['question'];
        if (draft['expected_answer'] != item['expected_answer']) body['expected_answer'] = draft['expected_answer'];
        if (draft['topic'] != item['topic']) body['topic'] = draft['topic'];
        final oldCitations = (item['citation_ids'] as List<dynamic>? ?? const []).cast<String>();
        if (jsonEncode(draft['citation_ids']) != jsonEncode(oldCitations)) body['citation_ids'] = draft['citation_ids'];
        if (body.length == 1) break;
        try {
          final response = await _httpClient.patch(_uri('/api/v1/training/examples/$id'),
            headers: {'Content-Type': 'application/json', ...apiAuthHeaders(widget.apiToken)},
            body: jsonEncode(body)).timeout(const Duration(seconds: 20));
          _checkResponse(response, expectedStatus: 200);
          finished = true;
          if (!mounted || _sessionExpired) return;
          await _loadTrainingData();
          if (mounted && !_sessionExpired) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã lưu phiên bản mới của ví dụ.')));
        } on ApiRequestException catch (error) {
          if (error.statusCode != 409) rethrow;
          final latest = await _fetchExampleById(id);
          if (!mounted || _sessionExpired) return;
          if (latest == null) throw const SafeApiException('Ví dụ không còn tồn tại.');
          final keep = await showDialog<bool>(context: context, builder: (dialogContext) =>
            AlertDialog(title: const Text('Revision đã thay đổi'),
              content: SizedBox(width: 540, child: SingleChildScrollView(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Bản đang sửa được giữ nguyên. Hãy đối chiếu với dữ liệu mới trước khi tiếp tục.'),
                  const Text('BẢN ĐANG SỬA', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('Câu hỏi: ${draft['question']}'), Text('Đáp án: ${draft['expected_answer']}'),
                  Text('Chủ đề: ${draft['topic']}'), Text('Citation: ${(draft['citation_ids'] as List).join(', ')}'),
                  const Divider(),
                  const Text('BẢN TRÊN MÁY CHỦ', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('Câu hỏi: ${latest['question']}'), Text('Đáp án: ${latest['expected_answer']}'),
                  Text('Chủ đề: ${latest['topic']}'),
                  Text('Citation: ${(latest['citation_ids'] as List? ?? const []).join(', ')}'),
                  Text('Revision: ${latest['revision']}'),
                ]))),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Đóng')),
                FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Tiếp tục trên revision mới')),
              ]));
          if (keep == true) {
            item = latest;
            revision = latest['revision'] is int ? latest['revision'] as int : revision;
          } else { break; }
        }
      }
    } catch (error) {
      if (mounted && !_sessionExpired) setState(() =>
        _error = 'Không sửa được ví dụ: ${_safeError(error, 'Đã xảy ra lỗi khi sửa ví dụ.')}');
    } finally {
      question.dispose(); answer.dispose(); topic.dispose(); citations.dispose();
      if (mounted) setState(() => _trainingActionIds.remove(id));
    }
  }

  Future<void> _createQualityReview(int id) async {
    if (!mounted || _sessionExpired || _trainingActionIds.contains(id)) return;
    final score = TextEditingController();
    final rationale = TextEditingController();
    String rubric = 'qa-quality-v1';
    String? validation;
    final payload = await showDialog<Map<String, dynamic>>(context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, refresh) =>
        AlertDialog(title: Text('Human Quality Review • #$id'),
          content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Điểm do con người nhập; không lấy từ prediction metrics và không tự chấm bằng AI.'),
              TextField(key: const ValueKey('quality-score'), controller: score,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Điểm nguyên 0–100', errorText: validation,
                  border: const OutlineInputBorder())),
              DropdownButtonFormField<String>(value: rubric,
                decoration: const InputDecoration(labelText: 'Rubric', border: OutlineInputBorder()),
                items: const [DropdownMenuItem(value: 'qa-quality-v1', child: Text('qa-quality-v1'))],
                onChanged: (value) { if (value != null) refresh(() => rubric = value); }),
              TextField(key: const ValueKey('quality-rationale'), controller: rationale,
                maxLength: 2000, minLines: 3, maxLines: 5,
                decoration: const InputDecoration(labelText: 'Nhận xét (10–2.000 ký tự)',
                  border: OutlineInputBorder())),
            ]))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Hủy')),
            FilledButton(key: const ValueKey('quality-submit'), onPressed: () {
              final raw = score.text.trim(); final value = int.tryParse(raw);
              if (value == null || value < 0 || value > 100 ||
                  rationale.text.trim().length < 10 || rationale.text.trim().length > 2000) {
                refresh(() => validation = 'Điểm nguyên 0–100 và nhận xét 10–2.000 ký tự là bắt buộc.');
                return;
              }
              Navigator.pop(dialogContext, {'score': value, 'rubric_version': rubric,
                'rationale': rationale.text.trim()});
            }, child: const Text('Gửi đánh giá')),
          ])));
    score.dispose(); rationale.dispose();
    if (payload == null || !mounted || _sessionExpired) return;
    setState(() { _trainingActionIds.add(id); _error = null; });
    try {
      final response = await _httpClient.post(_uri('/api/v1/training/examples/$id/quality-reviews'),
        headers: {'Content-Type': 'application/json', ...apiAuthHeaders(widget.apiToken)},
        body: jsonEncode(payload)).timeout(const Duration(seconds: 20));
      _checkResponse(response, expectedStatus: 201);
      if (mounted && !_sessionExpired) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu đánh giá thủ công. Trạng thái ví dụ không thay đổi.')));
    } catch (error) {
      if (mounted && !_sessionExpired) setState(() =>
        _error = 'Không lưu được đánh giá: ${_safeError(error, 'Đã xảy ra lỗi khi đánh giá.')}');
    } finally {
      if (mounted) setState(() => _trainingActionIds.remove(id));
    }
  }

  Future<void> _openReviewHistory(int id) async {
    if (!mounted || _sessionExpired || _trainingActionIds.contains(id)) return;
    setState(() => _trainingActionIds.add(id));
    try {
      final headers = apiAuthHeaders(widget.apiToken);
      final responses = await Future.wait([
        _httpClient.get(_uri('/api/v1/training/examples/$id/review-events',
          {'limit': '50', 'offset': '0'}), headers: headers).timeout(const Duration(seconds: 20)),
        _httpClient.get(_uri('/api/v1/training/examples/$id/quality-reviews'),
          headers: headers).timeout(const Duration(seconds: 20)),
      ]);
      for (final response in responses) { _checkResponse(response, expectedStatus: 200); }
      if (!mounted || _sessionExpired) return;
      final eventsPage = jsonDecode(responses[0].body);
      final qualityPage = jsonDecode(responses[1].body);
      if (eventsPage is! Map<String, dynamic> || eventsPage['items'] is! List ||
          eventsPage['total'] is! int || eventsPage['limit'] is! int ||
          eventsPage['offset'] is! int ||
          qualityPage is! Map<String, dynamic> || qualityPage['items'] is! List) {
        throw const SafeApiException('Dữ liệu lịch sử review không hợp lệ.');
      }
      final events = List<dynamic>.from(eventsPage['items'] as List);
      final quality = qualityPage['items'] as List;
      var total = eventsPage['total'] as int;
      var offset = eventsPage['offset'] as int;
      final limit = eventsPage['limit'] as int;
      var loadingMore = false;
      var historyError = '';
      await showDialog<void>(context: context, builder: (dialogContext) =>
        StatefulBuilder(builder: (context, refresh) => AlertDialog(
          title: Text('Lịch sử review • ví dụ #$id'),
          content: SizedBox(width: 620, height: 520, child: ListView(children: [
            Text('Review events (${total})', style: Theme.of(context).textTheme.titleMedium),
            if (events.isEmpty) const Text('Chưa có approve/reject/edit event.'),
            ...events.whereType<Map<String, dynamic>>().map((event) {
              final action = switch (event['action']) {
                'approved' => 'Đã duyệt', 'rejected' => 'Đã từ chối',
                'edited' => 'Đã chỉnh sửa', _ => 'Sự kiện review',
              };
              return ListTile(title: Text('$action • revision ${event['revision_from']} → ${event['revision_to']}'),
                subtitle: Text([
                  if (event['reason'] is String && (event['reason'] as String).isNotEmpty)
                    'Lý do: ${event['reason']}',
                  'Người thực hiện: ${event['reviewer_label'] ?? '—'}'
                    '${event['reviewer_user_id'] == null ? '' : ' (#${event['reviewer_user_id']})'}',
                  'Thời gian máy chủ: ${event['created_at'] ?? '—'}',
                  if (event['changed_fields'] is List && (event['changed_fields'] as List).isNotEmpty)
                    'Trường đã sửa: ${(event['changed_fields'] as List).join(', ')}',
                ].join('\n')));
            }),
            if (offset + events.length < total)
              Center(child: OutlinedButton(
                onPressed: loadingMore ? null : () async {
                  refresh(() { loadingMore = true; historyError = ''; });
                  try {
                    final nextOffset = offset + events.length;
                    final response = await _httpClient.get(
                      _uri('/api/v1/training/examples/$id/review-events',
                        {'limit': '$limit', 'offset': '$nextOffset'}),
                      headers: headers,
                    ).timeout(const Duration(seconds: 20));
                    _checkResponse(response, expectedStatus: 200);
                    final page = jsonDecode(response.body);
                    if (page is! Map<String, dynamic> || page['items'] is! List ||
                        page['total'] is! int || page['limit'] != limit ||
                        page['offset'] != nextOffset) {
                      throw const SafeApiException('Trang lịch sử review không hợp lệ.');
                    }
                    if (dialogContext.mounted) {
                      refresh(() {
                        events.addAll(page['items'] as List);
                        total = page['total'] as int;
                        offset = nextOffset;
                      });
                    }
                  } catch (error) {
                    if (dialogContext.mounted) {
                      refresh(() => historyError = _safeError(error, 'Không tải thêm được lịch sử.'));
                    }
                  } finally {
                    if (dialogContext.mounted) refresh(() => loadingMore = false);
                  }
                },
                child: Text(loadingMore ? 'Đang tải...' : 'Tải thêm lịch sử'),
              )),
            if (historyError.isNotEmpty)
              Text(historyError, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const Divider(height: 28),
            Text('Human Quality Review (${quality.length})',
              style: Theme.of(context).textTheme.titleMedium),
            if (quality.isEmpty) const Text('Chưa có đánh giá chất lượng thủ công.'),
            ...quality.whereType<Map<String, dynamic>>().map((review) => ListTile(
              title: Text('Điểm ${review['score']}/100 • ${review['rubric_version']}'),
              subtitle: Text([
                'Revision được đánh giá: ${review['example_revision'] ?? '—'}',
                'Nhận xét: ${review['rationale'] ?? '—'}',
                'Reviewer ID: ${review['reviewer_user_id'] ?? '—'}',
                'Thời gian máy chủ: ${review['reviewed_at'] ?? '—'}',
              ].join('\n')))),
          ])),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Đóng'))],
        )));
    } catch (error) {
      if (mounted && !_sessionExpired) setState(() =>
        _error = 'Không tải được lịch sử: ${_safeError(error, 'Đã xảy ra lỗi khi tải lịch sử.')}');
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
                  TextField(controller: _trainingQuestionController, enabled: !_savingExample, maxLength: 1000, minLines: 2, maxLines: 3, decoration: const InputDecoration(labelText: 'Câu hỏi mẫu', helperText: 'Tối thiểu 10 ký tự', border: OutlineInputBorder())),
                  const SizedBox(height: 8),
                  TextField(controller: _trainingAnswerController, enabled: !_savingExample, maxLength: 5000, minLines: 3, maxLines: 5, decoration: const InputDecoration(labelText: 'Đáp án chuẩn đã kiểm chứng', helperText: 'Tối thiểu 20 ký tự', border: OutlineInputBorder())),
                  const SizedBox(height: 8),
                  TextField(controller: _trainingTopicController, enabled: !_savingExample, maxLength: 80, decoration: const InputDecoration(labelText: 'Chủ đề', border: OutlineInputBorder())),
                  const SizedBox(height: 8),
                  TextField(controller: _trainingCitationsController, enabled: !_savingExample, maxLength: 1000, decoration: const InputDecoration(labelText: 'Mã nguồn (kb:document:chunk)', helperText: 'Lấy citation_id từ kết quả tra cứu kho tri thức; phân tách nhiều mã bằng dấu phẩy.', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _savingExample ? null : _saveTrainingExample, icon: const Icon(Icons.playlist_add), label: Text(_savingExample ? 'Đang lưu...' : 'Lưu ví dụ chờ duyệt'))),
                  const Divider(height: 24),
                  if (_trainingDataLoading) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    const Text('Đang tải dữ liệu huấn luyện...'),
                  ],
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
                    final approved = item['status'] == 'approved';
                    final citations = (item['citation_ids'] as List<dynamic>? ?? const []).join(', ');
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [Expanded(child: Text(item['topic']?.toString() ?? 'general')), Chip(label: Text(approved ? 'Đã duyệt' : 'Chờ duyệt'))]),
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
                            Wrap(spacing: 8, children: [
                              if (!approved)
                                TextButton.icon(
                                  onPressed: _trainingActionIds.contains(id) ? null : () => _approveTrainingExample(id),
                                  icon: _trainingActionIds.contains(id)
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Icon(Icons.verified_outlined),
                                  label: Text(_trainingActionIds.contains(id) ? 'Đang xử lý...' : 'Duyệt'),
                                ),
                              TextButton.icon(
                                onPressed: _trainingActionIds.contains(id) ? null : () => _deleteTrainingExample(id),
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Xóa'),
                              ),
                            ]),
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
