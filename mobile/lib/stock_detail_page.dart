import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_auth.dart';

class StockDetailPage extends StatefulWidget {
  const StockDetailPage({
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
  State<StockDetailPage> createState() => _StockDetailPageState();
}

class _StockDetailPageState extends State<StockDetailPage> {
  Map<String, dynamic>? _detail;
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
        '${widget.baseUrl}/api/v1/symbols/${widget.symbol}/detail',
      ).replace(queryParameters: {'timeframe': '1d', 'limit': '500'});
      final response = await http.get(uri, headers: apiAuthHeaders(widget.apiToken)).timeout(const Duration(seconds: 12));
      if (response.statusCode == 401) {
        widget.onSessionExpired?.call(widget.apiToken);
        return;
      }
      if (response.statusCode != 200) {
        throw ApiRequestException(response.statusCode);
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _detail = payload);
    } catch (error) {
      if (mounted) setState(() => _error = 'Không tải được chi tiết mã: ${safeApiErrorMessage(error, fallback: 'Đã xảy ra lỗi khi tải chi tiết mã.')}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _number(dynamic value, {int digits = 2}) {
    if (value is! num) return 'Chưa đủ dữ liệu';
    return value.toStringAsFixed(digits);
  }

  Widget _metric(String label, dynamic value, {String suffix = '', int digits = 2}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 5),
            Text(
              value is num ? '${_number(value, digits: digits)}$suffix' : '—',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, Widget child) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final instrument = _detail?['instrument'] as Map<String, dynamic>? ?? {};
    final latest = _detail?['latest'] as Map<String, dynamic>?;
    final metrics = _detail?['indicators'] as Map<String, dynamic>? ?? {};
    final trend = _detail?['trend_and_zones'] as Map<String, dynamic>? ?? {};
    final zones = trend['price_zones'] as Map<String, dynamic>? ?? {};
    final liquidity = _detail?['liquidity'] as Map<String, dynamic>? ?? {};
    final quality = _detail?['data_quality'] as Map<String, dynamic>? ?? {};
    final sources = (quality['sources'] as List<dynamic>? ?? const [])
        .map((item) => item.toString())
        .join(', ');

    return Scaffold(
      appBar: AppBar(title: Text('${widget.symbol} • Chi tiết')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (_loading)
              const LinearProgressIndicator(),
            if (_error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ),
              ),
            if (_detail != null) ...[
              _section(
                '${instrument['name'] ?? widget.symbol} • ${instrument['exchange'] ?? ''}',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      latest == null ? 'Chưa có dữ liệu giá' : _number(latest['close']),
                      style: theme.textTheme.headlineMedium,
                    ),
                    Text(
                      latest == null ? 'Chưa có phiên gần nhất' : 'Phiên: ${latest['timestamp']}',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (latest != null)
                      Text(
                        'O ${_number(latest['open'])}  H ${_number(latest['high'])}  L ${_number(latest['low'])}  C ${_number(latest['close'])}',
                      ),
                  ],
                ),
              ),
              _section(
                'Chỉ báo kỹ thuật',
                Column(
                  children: [
                    Row(children: [
                      _metric('RSI 14', metrics['rsi14']),
                      _metric('MACD', metrics['macd'], digits: 4),
                    ]),
                    Row(children: [
                      _metric('MACD Signal', metrics['macd_signal'], digits: 4),
                      _metric('Histogram', metrics['macd_histogram'], digits: 4),
                    ]),
                    Row(children: [
                      _metric('EMA 20', metrics['ema20']),
                      _metric('EMA 50', metrics['ema50']),
                    ]),
                    Row(children: [
                      _metric('ATR 14', metrics['atr14']),
                      _metric('ATR %', metrics['atr_percent'], suffix: '%'),
                    ]),
                  ],
                ),
              ),
              _section(
                'Xu hướng và vùng giá',
                trend['status'] == 'ok'
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Xu hướng: ${(trend['trend'] as Map<String, dynamic>?)?['classification'] ?? 'Chưa xác định'}'),
                          const SizedBox(height: 8),
                          Text('Hỗ trợ: ${_levels(zones['supports'])}'),
                          Text('Kháng cự: ${_levels(zones['resistances'])}'),
                          const SizedBox(height: 6),
                          Text(
                            'Breakout: ${(trend['breakout'] as Map<String, dynamic>?)?['state'] ?? 'Chưa xác định'}',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      )
                    : Text(trend['message']?.toString() ?? 'Chưa đủ dữ liệu để phân tích vùng giá.'),
              ),
              _section(
                'Thanh khoản ước tính',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      liquidity['average_traded_value_20_sessions'] is num
                          ? _number(liquidity['average_traded_value_20_sessions'], digits: 0)
                          : 'Chưa đủ 20 phiên',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(liquidity['note']?.toString() ?? ''),
                  ],
                ),
              ),
              _section(
                'Nguồn và chất lượng dữ liệu',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Thời điểm: ${quality['as_of'] ?? 'Chưa có'}'),
                    Text('Nguồn: ${sources.isEmpty ? 'Chưa xác định' : sources}'),
                    Text('Điều chỉnh giá: ${quality['price_adjustment'] ?? 'unknown'}'),
                    const SizedBox(height: 6),
                    const Text(
                      'Giá trị giao dịch là ước tính từ close × volume, không phải thanh khoản chính thức. Cần xác minh điều chỉnh corporate action trước khi so sánh dài hạn.',
                    ),
                  ],
                ),
              ),
            ] else if (!_loading && _error == null)
              const Center(child: Text('Đang chờ dữ liệu chi tiết...')),
          ],
        ),
      ),
    );
  }

  String _levels(dynamic raw) {
    if (raw is! List || raw.isEmpty) return 'Chưa xác định';
    return raw
        .whereType<Map<String, dynamic>>()
        .map((item) => _number(item['price']))
        .join(' • ');
  }
}
