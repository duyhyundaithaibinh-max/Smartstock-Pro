import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'api_auth.dart';

/// Local knowledge retrieval and document management.
/// Search results are source passages, not AI-generated answers.
class TrainingRoomPage extends StatefulWidget {
  const TrainingRoomPage({super.key, required this.baseUrl, required this.accessToken});

  final String baseUrl;
  final String accessToken;

  @override
  State<TrainingRoomPage> createState() => _TrainingRoomPageState();
}

class _TrainingRoomPageState extends State<TrainingRoomPage> {
  Map<String, String> get _authHeaders => apiAuthHeaders(widget.accessToken);

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

  Future<void> _loadTrainingData() async {
    final requestVersion = ++_trainingDataRequestVersion;
    if (mounted) {
      setState(() {
        _trainingDataLoading = true;
      });
    }
    try {
      final responses = await Future.wait([
        http.get(
          _uri('/api/v1/training/examples', {'limit': '100', 'offset': '0'}),
          headers: _authHeaders,
        ).timeout(const Duration(seconds: 20)),
        http.get(
          _uri('/api/v1/training/evaluation'),
          headers: _authHeaders,
        ).timeout(const Duration(seconds: 20)),
      ]);
      if (responses.any((response) => response.statusCode != 200)) {
        throw Exception('Backend chưa hỗ trợ đầy đủ API Training Room.');
      }
      final examples = jsonDecode(responses[0].body) as Map<String, dynamic>;
      final evaluation = jsonDecode(responses[1].body) as Map<String, dynamic>;
      if (!mounted || requestVersion != _trainingDataRequestVersion) return;
      setState(() {
        _examples = examples['items'] as List<dynamic>? ?? [];
        _evaluation = evaluation;
      });
    } catch (error) {
      if (mounted && requestVersion == _trainingDataRequestVersion) {
        setState(() => _error = 'Không tải được bộ dữ liệu huấn luyện: $error');
      }
    } finally {
      if (mounted && requestVersion == _trainingDataRequestVersion) {
        setState(() => _trainingDataLoading = false);
      }
    }
  }

  Future<void> _saveTrainingExample() async {
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
      final response = await http.post(
        _uri('/api/v1/training/examples'),
        headers: {'Content-Type': 'application/json', ..._authHeaders},
        body: jsonEncode({
          'question': question, 'expected_answer': answer,
          'topic': topic.isEmpty ? 'general' : topic, 'citation_ids': citations,
        }),
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 201) throw Exception('HTTP ${response.statusCode}: ${response.body}');
      if (!mounted) return;
      _trainingQuestionController.clear();
      _trainingAnswerController.clear();
      _trainingCitationsController.clear();
      await _loadTrainingData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã lưu ví dụ ở trạng thái chờ duyệt.')));
    } catch (error) {
      if (mounted) setState(() => _error = 'Không lưu được ví dụ: $error');
    } finally {
      if (mounted) setState(() => _savingExample = false);
    }
  }

  Future<void> _approveTrainingExample(int id) async {
    if (_trainingActionIds.contains(id)) return;
    setState(() {
      _trainingActionIds.add(id);
      _error = null;
    });
    try {
      final response = await http.post(
        _uri('/api/v1/training/examples/$id/approve'),
        headers: _authHeaders,
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
      await _loadTrainingData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã duyệt ví dụ huấn luyện.')),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Không duyệt được ví dụ: $error');
      }
    } finally {
      if (mounted) setState(() => _trainingActionIds.remove(id));
    }
  }

  Future<void> _deleteTrainingExample(int id) async {
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
    if (confirmed != true || !mounted) return;
    setState(() {
      _trainingActionIds.add(id);
      _error = null;
    });
    try {
      final response = await http.delete(
        _uri('/api/v1/training/examples/$id'),
        headers: _authHeaders,
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
      await _loadTrainingData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã xóa ví dụ huấn luyện.')),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Không xóa được ví dụ: $error');
      }
    } finally {
      if (mounted) setState(() => _trainingActionIds.remove(id));
    }
  }

  Future<void> _copyTrainingExport() async {
    if (_exportingTraining) return;
    setState(() {
      _exportingTraining = true;
      _error = null;
    });
    try {
      final response = await http.get(_uri('/api/v1/training/export'),
          headers: _authHeaders).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}: ${response.body}');
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      await Clipboard.setData(ClipboardData(text: payload['content']?.toString() ?? ''));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã sao chép ${payload['count'] ?? 0} ví dụ đã duyệt dạng JSONL.')));
    } catch (error) {
      if (mounted) setState(() => _error = 'Không xuất được dữ liệu: $error');
    } finally {
      if (mounted) setState(() => _exportingTraining = false);
    }
  }
  Future<void> _loadDocuments() async {
    final requestVersion = ++_documentsRequestVersion;
    final category = _categoryFilter;
    setState(() {
      _documentsLoading = true;
      _error = null;
    });
    try {
      final response = await http.get(_uri('/api/v1/knowledge/documents', {
        'limit': '100',
        'offset': '0',
        if (category != 'all') 'category': category,
      }), headers: _authHeaders).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('Backend trả về HTTP ${response.statusCode}');
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted || requestVersion != _documentsRequestVersion) return;
      setState(() => _documents = payload['items'] as List<dynamic>? ?? []);
    } catch (error) {
      if (mounted && requestVersion == _documentsRequestVersion) {
        setState(() => _error = 'Không tải được danh sách tài liệu: $error');
      }
    } finally {
      if (mounted && requestVersion == _documentsRequestVersion) {
        setState(() => _documentsLoading = false);
      }
    }
  }

  Future<void> _pickAndUpload() async {
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
      if (!mounted || file == null) return;
      final fileLength = file.lengthSync() ?? await file.length();
      if (fileLength == null || fileLength <= 0) {
        throw Exception('Không đọc được kích thước tệp trên thiết bị.');
      }
      if (fileLength > 10 * 1024 * 1024) {
        throw Exception('Tệp vượt quá giới hạn 10 MB.');
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.isEmpty) {
        throw Exception('Không đọc được nội dung tệp trên thiết bị.');
      }

      final request = http.MultipartRequest(
        'POST',
        _uri('/api/v1/knowledge/documents', {
          'source': 'android_upload',
          'title': file.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
          'category': _uploadCategory,
        }),
      );
      request.headers.addAll(_authHeaders);
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: file.name,
      ));
      final streamed = await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 409) {
        throw Exception('Tài liệu này đã được nhập trước đó (trùng nội dung).');
      }
      if (response.statusCode != 201) {
        var detail = response.body;
        try {
          final payload = jsonDecode(response.body);
          detail = payload is Map ? (payload['detail'] ?? payload).toString() : detail;
        } catch (_) {
          // Keep the raw backend response when it is not JSON.
        }
        throw Exception('HTTP ${response.statusCode}: $detail');
      }
      if (!mounted) return;
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã nhập "${payload['title'] ?? file.name}" vào kho tri thức.')),
      );
      await _loadDocuments();
    } catch (error) {
      if (mounted) setState(() => _error = 'Không nhập được tài liệu: $error');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _deleteDocument(Map<String, dynamic> document) async {
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
      if (confirmed != true || !mounted) return;
      final response = await http.delete(
        _uri('/api/v1/knowledge/documents/$id'),
        headers: _authHeaders,
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('Backend trả về HTTP ${response.statusCode}');
      }
      if (!mounted) return;
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
      if (mounted) setState(() => _error = 'Không xóa được tài liệu: $error');
    } finally {
      if (mounted) setState(() => _documentActionIds.remove(id));
    }
  }

  Future<void> _search() async {
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
      final response = await http.get(
        _uri('/api/v1/knowledge/search', {
          'q': query,
          'top_k': '8',
          if (_categoryFilter != 'all') 'category': _categoryFilter,
        }),
        headers: _authHeaders,
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('Backend trả về HTTP ${response.statusCode}: ${response.body}');
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted || requestVersion != _searchRequestVersion) return;
      setState(() {
        _results = payload['results'] as List<dynamic>? ?? [];
        _context = payload['retrieval_context'] as Map<String, dynamic>?;
      });
    } catch (error) {
      if (mounted && requestVersion == _searchRequestVersion) {
        setState(() => _error = 'Không tìm kiếm được: $error');
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
                        onPressed: !_trainingDataLoading && !_exportingTraining &&
                                (_evaluation!['approved_examples'] as num? ?? 0) > 0
                            ? _copyTrainingExport
                            : null,
                        icon: _exportingTraining
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.copy),
                        label: Text(_exportingTraining ? 'Đang xuất...' : 'Sao chép JSONL đã duyệt'),
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
                          Text('Nguồn: $citations', style: Theme.of(context).textTheme.bodySmall),
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
