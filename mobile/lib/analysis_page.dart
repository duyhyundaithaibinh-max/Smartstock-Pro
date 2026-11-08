import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_auth.dart';

class AnalysisPage extends StatefulWidget {
  const AnalysisPage({
    super.key,
    required this.baseUrl,
    required this.symbol,
    this.apiToken = '',
  });

  final String baseUrl;
  final String symbol;
  final String apiToken;

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  Map<String, dynamic>? _report;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/api/v1/analysis/report',
      ).replace(queryParameters: {'symbol': widget.symbol, 'timeframe': '1d', 'limit': '500'});
      final response = await http.get(uri, headers: apiAuthHeaders(widget.apiToken)).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception('Backend trả về HTTP ${response.statusCode}: ${response.body}');
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final report = payload['report'] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _report = report);
    } catch (error) {
      if (mounted) setState(() => _error = 'Chưa tạo được báo cáo: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _scenario(Map<String, dynamic> item) {
    final evidence = (item['evidence'] as List<dynamic>? ?? const [])
        .map((value) => value.toString())
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item['label']?.toString() ?? item['name']?.toString() ?? 'Kịch bản',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(label: Text(item['status']?.toString() ?? 'conditional')),
              ],
            ),
            if (evidence.isEmpty)
              const Text('Chưa có bằng chứng quy tắc đủ điều kiện.')
            else
              ...evidence.map((line) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('•  '),
                        Expanded(child: Text(line)),
                      ],
                    ),
                  )),
            const SizedBox(height: 8),
            const Text('Điều kiện xác nhận', style: TextStyle(fontWeight: FontWeight.w600)),
            Text(item['confirmation']?.toString() ?? 'Chưa xác định'),
            const SizedBox(height: 8),
            const Text('Điều kiện vô hiệu', style: TextStyle(fontWeight: FontWeight.w600)),
            Text(item['invalidation']?.toString() ?? 'Chưa xác định'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = _report ?? {};
    final trend = report['trend_and_price_action'] as Map<String, dynamic>? ?? {};
    final trendInfo = trend['trend'] as Map<String, dynamic>? ?? {};
    final breakout = trend['breakout'] as Map<String, dynamic>? ?? {};
    final quality = report['data_quality'] as Map<String, dynamic>? ?? {};
    final scenarios = (report['scenarios'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final sources = (quality['sources'] as List<dynamic>? ?? const []).join(', ');

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.symbol} • Kịch bản'),
        actions: [
          IconButton(
            tooltip: 'Tải lại báo cáo',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              ),
            if (_report != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bức tranh kỹ thuật', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text('Giá đóng cửa: ${report['latest_close'] ?? '—'}'),
                      Text('Xu hướng: ${trendInfo['classification'] ?? 'Chưa xác định'}'),
                      Text('Breakout: ${breakout['state'] ?? 'Chưa xác định'}'),
                      Text('RSI ${report['indicators']?['rsi_period'] ?? 14}: ${report['indicators']?['rsi'] ?? '—'}'),
                      Text('Ngày dữ liệu: ${report['as_of'] ?? 'Chưa rõ'}'),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                child: Text('Ba kịch bản thị trường', style: Theme.of(context).textTheme.titleLarge),
              ),
              ...scenarios.map(_scenario),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Nguồn và giới hạn', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text('Nguồn OHLCV: ${sources.isEmpty ? 'Chưa xác định' : sources}'),
                      Text('Điều chỉnh giá: ${quality['price_adjustment'] ?? 'unknown'}'),
                      const SizedBox(height: 8),
                      const Text(
                        'Đây là báo cáo quy tắc kỹ thuật xác định, chưa phải kết luận do mô hình AI tạo ra hay khuyến nghị mua bán. Trạng thái “supported” không phải xác suất thành công.',
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (!_loading && _error == null)
              const Center(child: Text('Đang chờ báo cáo...')),
          ],
        ),
      ),
    );
  }
}
