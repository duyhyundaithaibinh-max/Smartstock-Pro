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
    this.onSessionExpired,
  });

  final String baseUrl;
  final String symbol;
  final String apiToken;
  final SessionExpiredCallback? onSessionExpired;

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
      if (response.statusCode == 401) {
        widget.onSessionExpired?.call(widget.apiToken);
        return;
      }
      if (response.statusCode != 200) {
        throw ApiRequestException(response.statusCode);
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final report = payload['report'] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _report = report);
    } catch (error) {
      if (mounted) setState(() => _error = 'Chưa tạo được báo cáo: ${safeApiErrorMessage(error, fallback: 'Đã xảy ra lỗi khi tạo báo cáo.')}');
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


  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  List<dynamic> _items(dynamic value) => value is List ? value : const [];

  String _fmt(dynamic value) =>
      value is num ? value.toStringAsFixed(2) : '—';

  Widget _fibCard(Map<String, dynamic> fib) {
    final swing = _map(fib['swing']);
    final start = _map(swing['start']);
    final end = _map(swing['end']);
    final price = _map(fib['price']);
    final time = _map(fib['time']);
    final status = fib['status']?.toString() ?? 'unknown';
    Widget rows(String title, dynamic raw, {bool timeRows = false}) {
      final values = _items(raw).whereType<Map>().toList();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        if (values.isEmpty) const Text('Chưa có dữ liệu.'),
        ...values.map((rawValue) {
          final value = _map(rawValue);
          final ratio = value['ratio'] is num ? (value['ratio'] as num) * 100 : null;
          final detail = timeRows
              ? '${value['bars_from_latest'] ?? '—'} nến • ${value['position'] ?? '—'}'
              : _fmt(value['price']);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              SizedBox(width: 72, child: Text(ratio == null ? '—' : '${ratio.toStringAsFixed(1)}%')),
              Expanded(child: Text(detail)),
            ]),
          );
        }),
      ]);
    }
    return Card(child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Fibonacci giá và thời gian', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (status != 'ok')
          Text(fib['message']?.toString() ?? 'Chưa đủ pivot xác nhận ($status).')
        else ...[
          Text('Swing: ${start['type'] ?? '—'} ${_fmt(start['price'])} → ${end['type'] ?? '—'} ${_fmt(end['price'])}'),
          Text('Độ dài: ${swing['duration_bars'] ?? '—'} nến'),
          const Divider(),
          rows('Thoái lui', price['retracements']),
          const SizedBox(height: 6),
          rows('Mở rộng', price['extensions']),
          const SizedBox(height: 6),
          rows('Dự phóng thời gian (nến giao dịch)', time['projections'], timeRows: true),
        ],
      ]),
    ));
  }

  Widget _elliottCard(Map<String, dynamic> elliott) {
    final candidate = _map(elliott['candidate']);
    final status = elliott['status']?.toString() ?? 'unknown';
    final pivots = _items(candidate['pivots']).whereType<Map>().toList();
    final waves = _items(candidate['waves']).whereType<Map>().toList();
    final checks = _items(candidate['rule_checks']).whereType<Map>().toList();
    final confirmed = _items(elliott['confirmed_pivots']).whereType<Map>().toList();
    return Card(child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Cấu trúc sóng Elliott', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (candidate.isEmpty) ...[
          Text(elliott['message']?.toString() ?? 'Chưa có impulse 5 sóng đủ điều kiện ($status).'),
          ...confirmed.map((raw) {
            final p = _map(raw);
            return Text('Pivot ${p['type'] ?? '—'}: ${_fmt(p['price'])} • ${p['timestamp'] ?? '—'}');
          }),
        ] else ...[
          Row(children: [
            Expanded(child: Text(candidate['direction'] == 'bullish' ? 'Impulse tăng' : 'Impulse giảm')),
            Chip(label: Text(status)),
          ]),
          Text('Điểm quy tắc: ${candidate['rule_score'] ?? '—'} / 100, không phải xác suất.'),
          const SizedBox(height: 6),
          const Text('Pivot P0–P5:', style: TextStyle(fontWeight: FontWeight.w600)),
          ...pivots.map((raw) {
            final p = _map(raw);
            return Text('${p['label'] ?? ''}: ${_fmt(p['price'])} • ${p['timestamp'] ?? '—'}');
          }),
          const Divider(),
          const Text('Độ dài sóng:', style: TextStyle(fontWeight: FontWeight.w600)),
          ...waves.map((raw) {
            final w = _map(raw);
            return Text('${w['wave'] ?? 'Wave'}: ${_fmt(w['length'])}');
          }),
          const Divider(),
          const Text('Kiểm tra quy tắc:', style: TextStyle(fontWeight: FontWeight.w600)),
          ...checks.map((raw) {
            final c = _map(raw);
            final ok = c['passed'] == true;
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(ok ? Icons.check_circle_outline : Icons.cancel_outlined,
                size: 18, color: ok ? Colors.green : Theme.of(context).colorScheme.error),
              const SizedBox(width: 6),
              Expanded(child: Text(c['explanation']?.toString() ?? '')),
            ]);
          }),
          const SizedBox(height: 6),
          Text('Xác nhận: ${candidate['confirmation_condition'] ?? '—'}'),
          Text('Vô hiệu: ${candidate['invalidation_condition'] ?? '—'}'),
        ],
        const SizedBox(height: 6),
        const Text('Elliott là giả thuyết cấu trúc; cách đếm có thể thay đổi theo pivot và cửa sổ dữ liệu.'),
      ]),
    ));
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

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hỗ trợ và kháng cự', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text('Hỗ trợ: ${_items(_map(_map(report['trend_and_price_action'])['price_zones'])['supports']).map((v) => _fmt(_map(v)['price'])).join(' • ')}'),
                      Text('Kháng cự: ${_items(_map(_map(report['trend_and_price_action'])['price_zones'])['resistances']).map((v) => _fmt(_map(v)['price'])).join(' • ')}'),
                      const SizedBox(height: 8),
                      Text('Breakout: ${_map(_map(report['trend_and_price_action'])['breakout'])['state'] ?? 'Chưa xác định'}'),
                      Text('Biên trên: ${_fmt(_map(_map(report['trend_and_price_action'])['breakout'])['prior_range_high'])}'),
                      Text('Biên dưới: ${_fmt(_map(_map(report['trend_and_price_action'])['breakout'])['prior_range_low'])}'),
                      Text('Tỷ lệ volume: ${_fmt(_map(_map(report['trend_and_price_action'])['breakout'])['volume_ratio'])}'),
                      Text(_map(_map(report['trend_and_price_action'])['breakout'])['confirmation_condition']?.toString() ?? 'Chưa có điều kiện xác nhận.'),
                    ],
                  ),
                ),
              ),
              _fibCard(_map(report['fibonacci'])),
              _elliottCard(_map(report['elliott'])),
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
