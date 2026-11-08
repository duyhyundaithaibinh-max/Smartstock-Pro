import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Local knowledge retrieval and document management.
/// Search results are source passages, not AI-generated answers.
class TrainingRoomPage extends StatefulWidget {
  const TrainingRoomPage({super.key, required this.baseUrl});

  final String baseUrl;

  @override
  State<TrainingRoomPage> createState() => _TrainingRoomPageState();
}

class _TrainingRoomPageState extends State<TrainingRoomPage> {
  final TextEditingController _queryController = TextEditingController();
  final TextEditingController _trainingQuestionController = TextEditingController();
  final TextEditingController _trainingAnswerController = TextEditingController();
  final TextEditingController _trainingTopicController = TextEditingController(text: 'technical_analysis');
  final TextEditingController _trainingCitationsController = TextEditingController();
  List<dynamic> _results = [];
  List<dynamic> _examples = [];
  Map<String, dynamic>? _evaluation;
  bool _savingExample = false;
  List<dynamic> _documents = [];
  Map<String, dynamic>? _context;
  String? _error;
  bool _loading = false;
  bool _uploading = false;
  bool _documentsLoading = false;
  bool _searched = false;

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('${widget.baseUrl}$path').replace(queryParameters: query);
  }

  Future<void> _loadTrainingData() async {
    try {
      final responses = await Future.wait([
        http.get(_uri('/api/v1/training/examples', {'limit': '100', 'offset': '0'}))
            .timeout(const Duration(seconds: 20)),
        http.get(_uri('/api/v1/training/evaluation'))
            .timeout(const Duration(seconds: 20)),
      ]);
      if (responses.any((response) => response.statusCode != 200)) {
        throw Exception('Backend chưa hỗ trợ đầy đủ API Training Room.');
      }
      final examples = jsonDecode(responses[0].body) as Map<String, dynamic>;
      final evaluation = jsonDecode(responses[1].body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _examples = examples['items'] as List<dynamic>? ?? [];
        _evaluation = evaluation;
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Không tải được bộ dữ liệu huấn luyện: $error');
    }
  }

  Future<void> _saveTrainingExample() async {
    if (_savingExample) return;
    final question = _trainingQuestionController.text.trim();
    final answer = _trainingAnswerController.text.trim();
    final topic = _trainingTopicController.text.trim();
    final citations = _trainingCitationsController.text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (question.length < 10 || answer.length < 20 || citations.isEmpty) {
      setState(() => _error = 'Câu hỏi tối thiểu 10 ký tự, đáp án 20 ký tự và cần ít nhất một mã nguồn kb:document:chunk.');
      return;
    }
    setState(() {
      _savingExample = true;
      _error = null;
    });
    try {
      final response = await http.post(
        _uri('/api/v1/training/examples'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'question': question,
          'expected_answer': answer,
          'topic': topic.isEmpty ? 'general' : topic,
          'citation_ids': citations,
        }),
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 201) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
      _trainingQuestionController.clear();
      _trainingAnswerController.clear();
      _trainingCitationsController.clear();
      await _loadTrainingData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu ví dụ ở trạng thái chờ duyệt.')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = 'Không lưu được ví dụ: $error');
    } finally {
      if (mounted) setState(() => _savingExample = false);
    }
  }

  Future<void> _approveTrainingExample(int id) async {
    try {
      final response = await http.post(
        _uri('/api/v1/training/examples/$id/approve'),
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
      await _loadTrainingData();
    } catch (error) {
      if (mounted) setState(() => _error = 'Không duyệt được ví dụ: $error');
    }
  }

  Future<void> _deleteTrainingExample(int id) async {
    try {
      final response = await http.delete(
        _uri('/api/v1/training/examples/$id'),
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
      await _loadTrainingData();
    } catch (error) {
      if (mounted) setState(() => _error = 'Không xóa được ví dụ: $error');
    }
  }

  Future<void> _copyTrainingExport() async {
    try {
      final response = await http.get(
        _uri('/api/v1/training/export'),
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final content = payload['content']?.toString() ?? '';
      await Clipboard.setData(ClipboardData(text: content));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã sao chép ${payload['count'] ?? 0} ví dụ đã duyệt dạng JSONL.')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = 'Không xuất được dữ liệu: $error');
    }
  }

  Future<void> _loadDocuments() async {
    setState(() {
      _documentsLoading = true;
      _error = null;
    });
    try {
      final response = await http.get(_uri('/api/v1/knowledge/documents', {
        'limit': '100',
        'offset': '0',
      })).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('Backend trả về HTTP ${response.statusCode}');
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _documents = payload['items'] as List<dynamic>? ?? []);
    } catch (error) {
      if (mounted) setState(() => _error = 'Không tải được danh sách tài liệu: $error');
    } finally {
      if (mounted) setState(() => _documentsLoading = false);
    }
  }

  Future<void> _pickAndUpload() async {
    if (_uploading) return;
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['txt', 'md', 'csv', 'pdf'],
      );
      if (file == null) return;
      final fileLength = file.lengthSync() ?? await file.length();
      if (fileLength == null || fileLength <= 0) {
        throw Exception('Không đọc được kích thước tệp trên thiết bị.');
      }
      if (fileLength > 10 * 1024 * 1024) {
        throw Exception('Tệp vượt quá giới hạn 10 MB.');
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        throw Exception('Không đọc được nội dung tệp trên thiết bị.');
      }

      setState(() {
        _uploading = true;
        _error = null;
      });
      final request = http.MultipartRequest(
        'POST',
        _uri('/api/v1/knowledge/documents', {
          'source': 'android_upload',
          'title': file.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
        }),
      );
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
    final title = document['title']?.toString() ?? document['filename']?.toString() ?? 'tài liệu';
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
    if (confirmed != true || id is! int) return;
    try {
      final response = await http.delete(
        _uri('/api/v1/knowledge/documents/$id'),
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('Backend trả về HTTP ${response.statusCode}');
      }
      if (!mounted) return;
      setState(() {
        _documents.removeWhere((item) => item is Map && item['id'] == id);
        _results.removeWhere((item) => item is Map && item['document_id'] == id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã xóa tài liệu khỏi kho tri thức.')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = 'Không xóa được tài liệu: $error');
    }
  }

  Future<void> _search() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) {
      setState(() => _error = 'Nhập nội dung cần tìm trong kho tri thức.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
    });
    try {
      final response = await http.get(
        _uri('/api/v1/knowledge/search', {'q': query, 'top_k': '8'}),
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('Backend trả về HTTP ${response.statusCode}: ${response.body}');
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _results = payload['results'] as List<dynamic>? ?? [];
        _context = payload['retrieval_context'] as Map<String, dynamic>?;
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Không tìm kiếm được: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title == null || title.isEmpty ? filename : title,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 5),
            Text('Nguồn: $source • Điểm khớp: ${score is num ? score.toStringAsFixed(3) : '—'}'),
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
          '${item['filename'] ?? ''} • $chunks đoạn • ${size is num ? (size / 1024).toStringAsFixed(1) : '—'} KB'
          '${created == null ? '' : '\n$created'}',
        ),
        isThreeLine: true,
        trailing: IconButton(
          tooltip: 'Xóa tài liệu',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _deleteDocument(item),
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
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _uploading ? null : _pickAndUpload,
                      icon: _uploading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.upload_file),
                      label: Text(_uploading ? 'Đang nhập tài liệu...' : 'Chọn tài liệu từ điện thoại'),
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
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bộ ví dụ huấn luyện có kiểm duyệt',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  const Text('Tạo cặp câu hỏi–đáp án chuẩn dựa trên tài liệu đã nạp. Mỗi ví dụ phải gắn mã trích dẫn nguồn; ví dụ mới ở trạng thái chờ duyệt và chỉ dữ liệu đã duyệt mới được xuất.'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _trainingQuestionController,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Câu hỏi mẫu',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _trainingAnswerController,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Đáp án chuẩn đã kiểm chứng',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _trainingTopicController,
                    decoration: const InputDecoration(
                      labelText: 'Chủ đề (ví dụ: Elliott, Fibonacci, quản trị rủi ro)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _trainingCitationsController,
                    decoration: const InputDecoration(
                      labelText: 'Mã nguồn (ví dụ: kb:1:0, kb:1:1)',
                      helperText: 'Lấy citation_id trong kết quả tra cứu kho tri thức.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _savingExample ? null : _saveTrainingExample,
                      icon: _savingExample
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.playlist_add),
                      label: Text(_savingExample ? 'Đang lưu...' : 'Lưu ví dụ chờ duyệt'),
                    ),
                  ),
                  const Divider(height: 24),
                  if (_evaluation != null) ...[
                    Text('Đánh giá bộ dữ liệu', style: Theme.of(context).textTheme.titleMedium),
                    Text('Tổng: ${_evaluation!['total_examples'] ?? 0} • Đã duyệt: ${_evaluation!['approved_examples'] ?? 0} • Chờ duyệt: ${_evaluation!['draft_examples'] ?? 0}'),
                    Text('Nhóm câu hỏi trùng: ${_evaluation!['duplicate_question_groups'] ?? 0} • Tài liệu nguồn: ${_evaluation!['source_documents'] ?? 0}'),
                    Text('Trạng thái: ${_evaluation!['readiness'] ?? '—'}'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _loadTrainingData,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Cập nhật'),
                        ),
                        OutlinedButton.icon(
                          onPressed: (_evaluation!['approved_examples'] as num? ?? 0) > 0
                              ? _copyTrainingExport
                              : null,
                          icon: const Icon(Icons.copy),
                          label: const Text('Sao chép JSONL đã duyệt'),
                        ),
                      ],
                    ),
                  ],
                  if (_examples.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Chưa có ví dụ huấn luyện. Hãy nạp tài liệu, tra cứu nguồn rồi tạo ví dụ đầu tiên.'),
                    )
                  else
                    ..._examples.whereType<Map<String, dynamic>>().map((item) {
                      final id = item['id'];
                      final status = item['status']?.toString() ?? 'draft';
                      final citations = (item['citation_ids'] as List<dynamic>? ?? const []).join(', ');
                      return Card(
                        color: Theme.of(context).colorScheme.surfaceContainerLow,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(item['topic']?.toString() ?? 'general',
                                      style: const TextStyle(fontWeight: FontWeight.w600))),
                                  Chip(label: Text(status == 'approved' ? 'Đã duyệt' : 'Chờ duyệt')),
                                ],
                              ),
                              Text('Hỏi: ${item['question'] ?? ''}'),
                              const SizedBox(height: 5),
                              Text('Đáp án: ${item['expected_answer'] ?? ''}'),
                              const SizedBox(height: 5),
                              SelectableText('Nguồn: $citations'),
                              if (id is int)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Wrap(
                                    spacing: 4,
                                    children: [
                                      if (status == 'draft')
                                        TextButton.icon(
                                          onPressed: () => _approveTrainingExample(id),
                                          icon: const Icon(Icons.verified_outlined),
                                          label: const Text('Duyệt'),
                                        ),
                                      IconButton(
                                        tooltip: 'Xóa ví dụ',
                                        onPressed: () => _deleteTrainingExample(id),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
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
