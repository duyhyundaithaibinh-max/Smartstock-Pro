import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_auth.dart';
import 'chart_page.dart';
import 'training_room_page.dart';

void main() => runApp(const SmartStockApp());

class SmartStockApp extends StatelessWidget {
  const SmartStockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartStock Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFB71C1C),
        ),
        useMaterial3: true,
      ),
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
  final TextEditingController _urlController =
      TextEditingController(text: 'http://10.0.2.2:8000');
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _symbolController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  Map<String, dynamic>? _health;
  List<dynamic> _watchlist = [];
  String _exchange = 'HOSE';
  String? _error;
  bool _loading = false;
  bool _addingSymbol = false;

  String get _baseUrl =>
      _urlController.text.trim().replaceAll(RegExp(r'/$'), '');

  Future<void> _connect() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final healthResponse = await http
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 8));
      if (healthResponse.statusCode != 200) {
        throw Exception('API trả về HTTP ${healthResponse.statusCode}');
      }

      final watchlistResponse = await http
          .get(Uri.parse('$_baseUrl/api/v1/watchlist'), headers: apiAuthHeaders(_tokenController.text))
          .timeout(const Duration(seconds: 8));
      if (watchlistResponse.statusCode != 200) {
        throw Exception('Không tải được danh sách theo dõi');
      }

      final health = jsonDecode(healthResponse.body) as Map<String, dynamic>;
      final payload = jsonDecode(watchlistResponse.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _health = health;
        _watchlist = payload['items'] as List<dynamic>? ?? [];
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _health = null;
        _error = 'Không kết nối được backend: $error';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  Future<void> _createAndAddSymbol() async {
    final symbol = _symbolController.text.trim().toUpperCase();
    final name = _nameController.text.trim();
    if (!RegExp(r'^[A-Z0-9.]{3,12}    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChartPage(baseUrl: _baseUrl, symbol: symbol, apiToken: _tokenController.text.trim()),
      ),
    );
  }

  void _openTrainingRoom() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TrainingRoomPage(baseUrl: _baseUrl, apiToken: _tokenController.text.trim()),
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    _symbolController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartStock Pro'),
        backgroundColor: theme.colorScheme.surfaceContainer,
      ),
      body: RefreshIndicator(
        onRefresh: _connect,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Kết nối dữ liệu',
                        style: theme.textTheme.titleLarge),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _urlController,
                      decoration: const InputDecoration(
                        labelText: 'Backend URL',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _tokenController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'API Bearer Token (nếu backend bật bảo vệ)',
                        helperText: 'Để trống khi chạy local ở chế độ phát triển.',
                        border: OutlineInputBorder(),
                      ),
                      autocorrect: false,
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _loading ? null : _connect,
                        icon: const Icon(Icons.sync),
                        label: Text(
                          _loading ? 'Đang kết nối...' : 'Kết nối backend',
                        ),
                      ),
                    ),
                    if (_health != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'API: ${_health!['status']} • ${_health!['version']}',
                          style: const TextStyle(color: Colors.green),
                        ),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _error!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('Thị trường Việt Nam',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            const Wrap(
              spacing: 8,
              children: [
                Chip(label: Text('HOSE')),
                Chip(label: Text('HNX')),
                Chip(label: Text('UPCoM')),
              ],
            ),
            const SizedBox(height: 16),
            Text('Danh sách theo dõi',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Thêm mã vào danh sách', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _symbolController,
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Mã cổ phiếu (ví dụ: FPT)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Tên doanh nghiệp',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _exchange,
                      decoration: const InputDecoration(
                        labelText: 'Sàn giao dịch',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'HOSE', child: Text('HOSE')),
                        DropdownMenuItem(value: 'HNX', child: Text('HNX')),
                        DropdownMenuItem(value: 'UPCOM', child: Text('UPCoM')),
                      ],
                      onChanged: _addingSymbol ? null : (value) {
                        if (value != null) setState(() => _exchange = value);
                      },
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _addingSymbol ? null : _createAndAddSymbol,
                        icon: const Icon(Icons.add),
                        label: Text(_addingSymbol ? 'Đang thêm mã...' : 'Tạo mã và thêm vào watchlist'),
                      ),
                    ),
                    const Text(
                      'Thao tác này chỉ tạo thông tin mã, không tạo giá hoặc khối lượng. Cần nhập dữ liệu OHLCV từ nguồn hợp pháp để phân tích.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_watchlist.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'Chưa có mã trong watchlist. Hãy thêm mã qua API sau khi tạo mã và nhập dữ liệu.',
                  ),
                ),
              )
            else
              ..._watchlist.map((item) {
                final symbol = item['symbol'] as String;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(symbol.substring(0, 1)),
                    ),
                    title: Text(symbol),
                    subtitle: Text(
                      '${item['name']} • ${item['exchange']} • ${item['candle_count']} nến',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openChart(symbol),
                  ),
                );
              }),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.school_outlined)),
                title: const Text('Hybrid AI Training Room'),
                subtitle: const Text('Tra cứu tài liệu và bằng chứng trong kho tri thức cục bộ'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openTrainingRoom,
              ),
            ),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'SmartStock Pro đang ở giai đoạn MVP. Chỉ hiển thị dữ liệu đã nhập từ nguồn hợp pháp; không sử dụng giá hoặc khối lượng giả lập.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
).hasMatch(symbol) || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nhập mã 3–12 ký tự và tên doanh nghiệp.')),
      );
      return;
    }
    setState(() => _addingSymbol = true);
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        ...apiAuthHeaders(_tokenController.text),
      };
      final createResponse = await http.post(
        Uri.parse('$_baseUrl/api/v1/symbols'),
        headers: headers,
        body: jsonEncode({'symbol': symbol, 'name': name, 'exchange': _exchange}),
      ).timeout(const Duration(seconds: 12));
      if (createResponse.statusCode != 201 && createResponse.statusCode != 409) {
        throw Exception('Không tạo được mã: HTTP ${createResponse.statusCode}');
      }
      final watchlistResponse = await http.post(
        Uri.parse('$_baseUrl/api/v1/watchlist').replace(
          queryParameters: {'symbol': symbol},
        ),
        headers: apiAuthHeaders(_tokenController.text),
      ).timeout(const Duration(seconds: 12));
      if (watchlistResponse.statusCode != 201 && watchlistResponse.statusCode != 409) {
        throw Exception('Không thêm được vào watchlist: HTTP ${watchlistResponse.statusCode}');
      }
      _symbolController.clear();
      _nameController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã thêm $symbol vào danh sách theo dõi. Cần nhập OHLCV hợp pháp để phân tích.')),
      );
      await _connect();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thêm được mã: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _addingSymbol = false);
    }
  }

  void _openChart(String symbol) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChartPage(baseUrl: _baseUrl, symbol: symbol, apiToken: _tokenController.text.trim()),
      ),
    );
  }

  void _openTrainingRoom() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TrainingRoomPage(baseUrl: _baseUrl, apiToken: _tokenController.text.trim()),
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartStock Pro'),
        backgroundColor: theme.colorScheme.surfaceContainer,
      ),
      body: RefreshIndicator(
        onRefresh: _connect,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Kết nối dữ liệu',
                        style: theme.textTheme.titleLarge),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _urlController,
                      decoration: const InputDecoration(
                        labelText: 'Backend URL',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _tokenController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'API Bearer Token (nếu backend bật bảo vệ)',
                        helperText: 'Để trống khi chạy local ở chế độ phát triển.',
                        border: OutlineInputBorder(),
                      ),
                      autocorrect: false,
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _loading ? null : _connect,
                        icon: const Icon(Icons.sync),
                        label: Text(
                          _loading ? 'Đang kết nối...' : 'Kết nối backend',
                        ),
                      ),
                    ),
                    if (_health != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'API: ${_health!['status']} • ${_health!['version']}',
                          style: const TextStyle(color: Colors.green),
                        ),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _error!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('Thị trường Việt Nam',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            const Wrap(
              spacing: 8,
              children: [
                Chip(label: Text('HOSE')),
                Chip(label: Text('HNX')),
                Chip(label: Text('UPCoM')),
              ],
            ),
            const SizedBox(height: 16),
            Text('Danh sách theo dõi',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            if (_watchlist.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'Chưa có mã trong watchlist. Hãy thêm mã qua API sau khi tạo mã và nhập dữ liệu.',
                  ),
                ),
              )
            else
              ..._watchlist.map((item) {
                final symbol = item['symbol'] as String;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(symbol.substring(0, 1)),
                    ),
                    title: Text(symbol),
                    subtitle: Text(
                      '${item['name']} • ${item['exchange']} • ${item['candle_count']} nến',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openChart(symbol),
                  ),
                );
              }),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.school_outlined)),
                title: const Text('Hybrid AI Training Room'),
                subtitle: const Text('Tra cứu tài liệu và bằng chứng trong kho tri thức cục bộ'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openTrainingRoom,
              ),
            ),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'SmartStock Pro đang ở giai đoạn MVP. Chỉ hiển thị dữ liệu đã nhập từ nguồn hợp pháp; không sử dụng giá hoặc khối lượng giả lập.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
