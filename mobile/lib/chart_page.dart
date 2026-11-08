import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'stock_detail_page.dart';
import 'analysis_page.dart';
import 'api_auth.dart';

class ChartPage extends StatefulWidget {
  const ChartPage({
    super.key, required this.baseUrl, required this.symbol,
    this.apiToken = '', this.onSessionExpired,
  });

  final String baseUrl;
  final String symbol;
  final String apiToken;
  final SessionExpiredCallback? onSessionExpired;

  @override
  State<ChartPage> createState() => _ChartPageState();
}

class _ChartPageState extends State<ChartPage> {
  static const _periods = <String, String>{
    'daily': 'Ngày',
    'weekly': 'Tuần',
    'monthly': 'Tháng',
  };

  String _period = 'daily';
  List<Map<String, dynamic>> _candles = [];
  List<String> _sources = [];
  bool _loading = false;
  String? _error;
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _status = null;
    });
    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/api/v1/candles/chart',
      ).replace(queryParameters: {
        'symbol': widget.symbol,
        'period': _period,
        'limit': '180',
      });
      final response = await http.get(uri, headers: apiAuthHeaders(widget.apiToken)).timeout(const Duration(seconds: 12));
      if (response.statusCode == 401) {
        widget.onSessionExpired?.call(widget.apiToken);
        return;
      }
      if (response.statusCode != 200) {
        throw ApiRequestException(response.statusCode);
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final rows = (payload['candles'] as List<dynamic>? ?? const []);
      if (!mounted) return;
      setState(() {
        _candles = rows.cast<Map<String, dynamic>>();
        _sources = (payload['data_sources'] as List<dynamic>? ?? const [])
            .map((value) => value.toString())
            .toList();
        _status = payload['status']?.toString();
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Không tải được biểu đồ: ${safeApiErrorMessage(error, fallback: 'Đã xảy ra lỗi khi tải biểu đồ.')}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.symbol} • Biểu đồ'),
        actions: [
          IconButton(
            tooltip: 'Chi tiết mã',
            icon: const Icon(Icons.analytics_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => StockDetailPage(
                  baseUrl: widget.baseUrl,
                  symbol: widget.symbol,
                  apiToken: widget.apiToken,
                  onSessionExpired: widget.onSessionExpired,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Kịch bản phân tích',
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AnalysisPage(
                  baseUrl: widget.baseUrl,
                  symbol: widget.symbol,
                  apiToken: widget.apiToken,
                  onSessionExpired: widget.onSessionExpired,
                ),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<String>(
              segments: _periods.entries
                  .map((entry) => ButtonSegment<String>(
                        value: entry.key,
                        label: Text(entry.value),
                      ))
                  .toList(),
              selected: {_period},
              onSelectionChanged: (selection) {
                setState(() => _period = selection.first);
                _load();
              },
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ),
              )
            else if (_candles.isEmpty || _status == 'no_data')
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(Icons.show_chart, size: 42),
                      SizedBox(height: 12),
                      Text('Chưa có dữ liệu OHLCV cho mã này.'),
                      SizedBox(height: 4),
                      Text(
                        'Biểu đồ sẽ xuất hiện sau khi nhập dữ liệu có nguồn hợp pháp.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text('Giá OHLC', style: theme.textTheme.titleMedium),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 250,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _OhlcvPainter(
                            candles: _candles,
                            upColor: const Color(0xFF16865B),
                            downColor: const Color(0xFFD64A4A),
                            gridColor: theme.dividerColor,
                          ),
                        ),
                      ),
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text('Khối lượng', style: theme.textTheme.titleMedium),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 90,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _VolumePainter(
                            candles: _candles,
                            upColor: const Color(0xFF16865B),
                            downColor: const Color(0xFFD64A4A),
                            gridColor: theme.dividerColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Số nến: ${_candles.length} • Nguồn: ${_sources.isEmpty ? 'không rõ' : _sources.join(', ')}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Tuần/tháng được tổng hợp từ các nến ngày hiện có. Phiên thiếu không được tự tạo; trạng thái điều chỉnh giá chưa xác minh.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OhlcvPainter extends CustomPainter {
  _OhlcvPainter({
    required this.candles,
    required this.upColor,
    required this.downColor,
    required this.gridColor,
  });

  final List<Map<String, dynamic>> candles;
  final Color upColor;
  final Color downColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;
    final highs = candles.map((c) => (c['high'] as num).toDouble()).toList();
    final lows = candles.map((c) => (c['low'] as num).toDouble()).toList();
    final minPrice = lows.reduce((a, b) => a < b ? a : b);
    final maxPrice = highs.reduce((a, b) => a > b ? a : b);
    final range = (maxPrice - minPrice).abs();
    final padding = range == 0 ? (maxPrice.abs() * 0.02 + 1) : range * 0.08;
    final floor = minPrice - padding;
    final ceiling = maxPrice + padding;
    const left = 4.0;
    const right = 4.0;
    const top = 8.0;
    const bottom = 8.0;
    final plotWidth = size.width - left - right;
    final plotHeight = size.height - top - bottom;
    final grid = Paint()
      ..color = gridColor.withValues(alpha: 0.65)
      ..strokeWidth = 0.7;
    for (var i = 0; i <= 4; i++) {
      final y = top + plotHeight * i / 4;
      canvas.drawLine(Offset(left, y), Offset(size.width - right, y), grid);
    }
    final slot = plotWidth / candles.length;
    final bodyWidth = (slot * 0.62).clamp(1.0, 12.0).toDouble();
    double yFor(double value) =>
        top + (ceiling - value) / (ceiling - floor) * plotHeight;

    for (var i = 0; i < candles.length; i++) {
      final candle = candles[i];
      final open = (candle['open'] as num).toDouble();
      final close = (candle['close'] as num).toDouble();
      final high = (candle['high'] as num).toDouble();
      final low = (candle['low'] as num).toDouble();
      final x = left + slot * (i + 0.5);
      final color = close >= open ? upColor : downColor;
      final paint = Paint()
        ..color = color
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset(x, yFor(high)), Offset(x, yFor(low)), paint);
      final yOpen = yFor(open);
      final yClose = yFor(close);
      final rect = Rect.fromLTRB(
        x - bodyWidth / 2,
        yOpen < yClose ? yOpen : yClose,
        x + bodyWidth / 2,
        (yOpen - yClose).abs() < 1.5
            ? (yOpen < yClose ? yOpen : yClose) + 1.5
            : (yOpen > yClose ? yOpen : yClose),
      );
      canvas.drawRect(rect, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _OhlcvPainter oldDelegate) =>
      oldDelegate.candles != candles ||
      oldDelegate.gridColor != gridColor;
}

class _VolumePainter extends CustomPainter {
  _VolumePainter({
    required this.candles,
    required this.upColor,
    required this.downColor,
    required this.gridColor,
  });

  final List<Map<String, dynamic>> candles;
  final Color upColor;
  final Color downColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;
    final volumes = candles.map((c) => (c['volume'] as num).toDouble()).toList();
    final maxVolume = volumes.reduce((a, b) => a > b ? a : b);
    if (maxVolume <= 0) return;
    final slot = size.width / candles.length;
    final barWidth = (slot * 0.62).clamp(1.0, 12.0).toDouble();
    final grid = Paint()
      ..color = gridColor.withValues(alpha: 0.65)
      ..strokeWidth = 0.7;
    canvas.drawLine(Offset(0, size.height - 1), Offset(size.width, size.height - 1), grid);
    for (var i = 0; i < candles.length; i++) {
      final candle = candles[i];
      final volume = (candle['volume'] as num).toDouble();
      final open = (candle['open'] as num).toDouble();
      final close = (candle['close'] as num).toDouble();
      final height = volume / maxVolume * (size.height - 5);
      final x = slot * (i + 0.5);
      canvas.drawRect(
        Rect.fromLTRB(x - barWidth / 2, size.height - height, x + barWidth / 2, size.height),
        Paint()..color = close >= open ? upColor.withValues(alpha: 0.75) : downColor.withValues(alpha: 0.75),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VolumePainter oldDelegate) =>
      oldDelegate.candles != candles;
}
