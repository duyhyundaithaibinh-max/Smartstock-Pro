import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  String? _accessToken;
  bool _ownerInitialized = true;
  bool _authLoading = false;
  Map<String, dynamic>? _health;
  List<dynamic> _watchlist = [];
  String? _error;
  bool _loading = false;

  String get _baseUrl =>
      _urlController.text.trim().replaceAll(RegExp(r'/
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
          .get(Uri.parse('$_baseUrl/api/v1/watchlist'), headers: _authHeaders)
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

  void _openChart(String symbol) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChartPage(baseUrl: _baseUrl, symbol: symbol),
      ),
    );
  }

  void _openTrainingRoom() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TrainingRoomPage(baseUrl: _baseUrl, accessToken: _accessToken!),
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_accessToken == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('SmartStock Pro • Đăng nhập')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Icon(Icons.lock_outline, size: 52),
            const SizedBox(height: 12),
            Text(
              _ownerInitialized ? 'Đăng nhập chủ sở hữu' : 'Khởi tạo tài khoản chủ sở hữu',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(labelText: 'Backend URL', border: OutlineInputBorder()),
              keyboardType: TextInputType.url,
              onSubmitted: (_) => _loadAuthStatus(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: 'Tên đăng nhập', border: OutlineInputBorder()),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Mật khẩu',
                helperText: 'Tối thiểu 12 ký tự. Phiên đăng nhập chỉ lưu trong bộ nhớ ứng dụng.',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _authenticate(register: !_ownerInitialized),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _authLoading ? null : () => _authenticate(register: !_ownerInitialized),
                child: Text(_authLoading
                    ? 'Đang xử lý...'
                    : (_ownerInitialized ? 'Đăng nhập' : 'Khởi tạo chủ sở hữu')),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ),
            const SizedBox(height: 8),
            Text(
              'Chỉ cho phép tạo một tài khoản chủ sở hữu đầu tiên. Không có đăng ký công khai hoặc dịch vụ trả phí.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartStock Pro'),
        backgroundColor: theme.colorScheme.surfaceContainer,
        actions: [
          IconButton(
            tooltip: 'Đăng xuất',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
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
), '');

  Map<String, String> get _authHeaders => {
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      };

  @override
  void initState() {
    super.initState();
    _loadAuthStatus();
  }

  Future<void> _loadAuthStatus() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/api/v1/auth/status'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200 && mounted) {
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() => _ownerInitialized = payload['owner_initialized'] == true);
      }
    } catch (_) {
      // Keep the login screen usable while the backend is offline.
    }
  }

  Future<void> _authenticate({required bool register}) async {
    if (_authLoading) return;
    setState(() {
      _authLoading = true;
      _error = null;
    });
    try {
      final username = _usernameController.text.trim();
      final password = _passwordController.text;
      if (register && password.length < 12) {
        throw Exception('Mật khẩu cần tối thiểu 12 ký tự.');
      }
      if (register) {
        final setup = await http.post(
          Uri.parse('$_baseUrl/api/v1/auth/register-first-owner'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username, 'password': password}),
        ).timeout(const Duration(seconds: 15));
        if (setup.statusCode != 201) {
          throw Exception('Không khởi tạo được tài khoản: ${setup.body}');
        }
      }
      final response = await http.post(
        Uri.parse('$_baseUrl/api/v1/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('Đăng nhập thất bại: ${response.body}');
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _accessToken = payload['access_token']?.toString();
        _ownerInitialized = true;
      });
      _passwordController.clear();
      await _connect();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _authLoading = false);
    }
  }

  Future<void> _logout() async {
    final token = _accessToken;
    if (token != null) {
      try {
        await http.post(
          Uri.parse('$_baseUrl/api/v1/auth/logout'),
          headers: {'Authorization': 'Bearer $token'},
        ).timeout(const Duration(seconds: 8));
      } catch (_) {
        // Always clear the local in-memory token.
      }
    }
    if (!mounted) return;
    setState(() {
      _accessToken = null;
      _health = null;
      _watchlist = [];
    });
  }

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
          .get(Uri.parse('$_baseUrl/api/v1/watchlist'))
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

  void _openChart(String symbol) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChartPage(baseUrl: _baseUrl, symbol: symbol),
      ),
    );
  }

  void _openTrainingRoom() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TrainingRoomPage(baseUrl: _baseUrl),
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
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
