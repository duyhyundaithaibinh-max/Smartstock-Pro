import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'chart_page.dart';

void main() => runApp(const SmartStockApp());

class SmartStockApp extends StatelessWidget {
  const SmartStockApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartStock Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB71C1C)), useMaterial3: true),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final TextEditingController _urlController = TextEditingController(text: 'http://10.0.2.2:8000');
  Map<String, dynamic>? _health;
  List<dynamic> _symbols = [];
  String? _error;
  bool _loading = false;

  Future<void> _connect() async {
    setState(() { _loading = true; _error = null; });
    try {
      final base = _urlController.text.trim().replaceAll(RegExp(r'/$'), '');
      final response = await http.get(Uri.parse('$base/health')).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) throw Exception('API trả về HTTP ${response.statusCode}');
      final health = jsonDecode(response.body) as Map<String, dynamic>;
      final symbolsResponse = await http.get(Uri.parse('$base/api/v1/watchlist')).timeout(const Duration(seconds: 8));
      if (symbolsResponse.statusCode != 200) throw Exception('Không tải được danh sách theo dõi');
      final watchlistPayload = jsonDecode(symbolsResponse.body) as Map<String, dynamic>;
      setState(() { _health = health; _symbols = watchlistPayload['items'] as List<dynamic>? ?? []; });
    } catch (e) {
      setState(() { _health = null; _error = 'Không kết nối được backend: $e'; });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SmartStock Pro'), backgroundColor: Theme.of(context).colorScheme.surfaceContainer),
      body: RefreshIndicator(
        onRefresh: _connect,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Kết nối dữ liệu', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(controller: _urlController, decoration: const InputDecoration(labelText: 'Backend URL', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _loading ? null : _connect,
              icon: const Icon(Icons.sync), label: Text(_loading ? 'Đang kết nối...' : 'Kết nối backend'))),
            if (_health != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('API: ${_health!['status']} • ${_health!['version']}', style: const TextStyle(color: Colors.green))),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
          ]))),
          const SizedBox(height: 12),
          Text('Thị trường Việt Nam', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Wrap(spacing: 8, children: [Chip(label: Text('HOSE')), Chip(label: Text('HNX')), Chip(label: Text('UPCoM'))]),
          const SizedBox(height: 16),
          Text('Danh sách theo dõi', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (_symbols.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('Chưa có mã cổ phiếu. Hãy kết nối API và thêm dữ liệu vào hệ thống.')))
          else ..._symbols.map((item) => Card(child: ListTile(
            leading: CircleAvatar(child: Text((item['symbol'] as String).substring(0, 1))),
            title: Text(item['symbol'] as String),
            subtitle: Text('${item['name']} • ${item['exchange']} • ${item['candle_count']} nến'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              final base = _urlController.text.trim().replaceAll(RegExp(r'/
          const SizedBox(height: 16),
          const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('SmartStock Pro đang ở giai đoạn MVP. Dữ liệu chỉ hiển thị khi được nhập từ nguồn hợp pháp; chưa có dữ liệu thị trường mẫu hoặc tín hiệu mua/bán tự động.'))),
        ]),
      ),
    );
  }
}
), '');
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ChartPage(baseUrl: base, symbol: item['symbol'] as String),
              ));
            },
          ))),
          const SizedBox(height: 16),
          const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('SmartStock Pro đang ở giai đoạn MVP. Dữ liệu chỉ hiển thị khi được nhập từ nguồn hợp pháp; chưa có dữ liệu thị trường mẫu hoặc tín hiệu mua/bán tự động.'))),
        ]),
      ),
    );
  }
}
