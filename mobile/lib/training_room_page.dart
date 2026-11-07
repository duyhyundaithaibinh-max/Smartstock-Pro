import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Local knowledge retrieval UI. This screen displays source passages only;
/// it does not pretend that lexical retrieval is an AI-generated answer.
class TrainingRoomPage extends StatefulWidget {
  const TrainingRoomPage({super.key, required this.baseUrl});

  final String baseUrl;

  @override
  State<TrainingRoomPage> createState() => _TrainingRoomPageState();
}

class _TrainingRoomPageState extends State<TrainingRoomPage> {
  final TextEditingController _queryController = TextEditingController();
  List<dynamic> _results = [];
  Map<String, dynamic>? _context;
  String? _error;
  bool _loading = false;
  bool _searched = false;

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
      final uri = Uri.parse(
        '${widget.baseUrl}/api/v1/knowledge/search',
      ).replace(queryParameters: {'q': query, 'top_k': '8'});
      final response = await http.get(uri).timeout(const Duration(seconds: 20));
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
  void dispose() {
    _queryController.dispose();
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
            Text(
              title == null || title.isEmpty ? filename : title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
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
                  child: SelectableText(
                    citation,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Sao chép mã trích dẫn',
                  onPressed: () {
                    // Citation remains selectable; clipboard is intentionally
                    // not required for this first MVP screen.
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
                  Text('Tra cứu kho tri thức', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  const Text(
                    'Tìm kiếm cục bộ trong tài liệu đã nhập. Kết quả là đoạn trích có nguồn, chưa phải câu trả lời do AI tổng hợp.',
                  ),
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
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            ),
          if (_searched && !_loading && _error == null) ...[
            const SizedBox(height: 12),
            Text(
              status == 'ready'
                  ? 'Tìm thấy ${_results.length} đoạn tài liệu'
                  : 'Chưa tìm thấy bằng chứng phù hợp',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_results.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('Kho tri thức chưa có đoạn phù hợp. Hãy kiểm tra tài liệu đã được nhập vào backend.'),
                ),
              )
            else
              ..._results.whereType<Map<String, dynamic>>().map(_resultCard),
            if (_context != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Kiểm soát ngữ cảnh', style: TextStyle(fontWeight: FontWeight.w600)),
                      Text('Phương pháp: ${_context!['retrieval_method'] ?? '—'}'),
                      Text('Ký tự đưa vào ngữ cảnh: ${_context!['characters_used'] ?? 0}'),
                      Text('Trích dẫn hợp lệ: ${(_context!['citations'] as List<dynamic>? ?? const []).length}'),
                      const SizedBox(height: 6),
                      const Text(
                        'Nội dung tài liệu được xem là bằng chứng không đáng tin cậy, không được phép ghi đè quy tắc hệ thống.',
                      ),
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: 12),
          const Text(
            'Giai đoạn hiện tại dùng BM25-style lexical retrieval miễn phí, chạy cục bộ trên backend. Chưa bật embedding, mô hình sinh câu trả lời hay API AI trả phí.',
          ),
        ],
      ),
    );
  }
}
