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
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _bootstrapSecretController = TextEditingController();
  final TextEditingController _symbolController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  Map<String, dynamic>? _health;
  List<dynamic> _watchlist = [];
  String _exchange = 'HOSE';
  String? _error;
  bool _loading = false;
  bool _addingSymbol = false;
  String? _accessToken;
  bool _ownerInitialized = true;
  bool _authStatusLoaded = false;
  bool _authLoading = false;

  String get _baseUrl =>
      _urlController.text.trim().replaceAll(RegExp(r'/$'), '');

  Map<String, String> get _authHeaders => {
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      };

  @override
  void initState() {
    super.initState();
    _loadAuthStatus();
  }

  Future<void> _loadAuthStatus() async {
    setState(() {
      _authStatusLoaded = false;
      _error = null;
    });
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/v1/auth/status'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw Exception('Backend trả về HTTP ${response.statusCode}');
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _ownerInitialized = payload['owner_initialized'] == true;
        _authStatusLoaded = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _authStatusLoaded = true;
        _error = 'Không kiểm tra được backend: $error';
      });
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
      if (username.isEmpty || password.isEmpty) {
        throw Exception('Nhập tên đăng nhập và mật khẩu.');
      }
      final bootstrapSecret = _bootstrapSecretController.text.trim();
      if (register && password.length < 12) {
        throw Exception('Mật khẩu cần tối thiểu 12 ký tự.');
      }
      if (register && (bootstrapSecret.length < 32 || bootstrapSecret.length > 256)) {
        throw Exception('Bootstrap secret cần từ 32 đến 256 ký tự.');
      }
      if (register) {
        final setup = await http
            .post(
              Uri.parse('$_baseUrl/api/v1/auth/register-first-owner'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'username': username,
                'password': password,
                'bootstrap_secret': bootstrapSecret,
              }),
            )
            .timeout(const Duration(seconds: 15));
        if (setup.statusCode != 201) {
          if (setup.statusCode == 403) {
            throw Exception('Bootstrap secret không đúng hoặc đã được sử dụng. Hãy kiểm tra secret mới trên máy chủ.');
          }
          if (setup.statusCode == 422) {
            throw Exception('Bootstrap secret chưa hợp lệ. Hãy nhập secret từ 32 đến 256 ký tự.');
          }
          throw Exception('Không khởi tạo được tài khoản (HTTP ${setup.statusCode}).');
        }
        _bootstrapSecretController.clear();
      }
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/v1/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 20));
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
        await http
            .post(
              Uri.parse('$_baseUrl/api/v1/auth/logout'),
              headers: {'Authorization': 'Bearer $token'},
            )
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        // Always clear the in-memory token locally.
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
          .get(
            Uri.parse('$_baseUrl/api/v1/watchlist'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 8));
      if (watchlistResponse.statusCode != 200) {
        throw Exception('Không tải được danh sách theo dõi: HTTP ${watchlistResponse.statusCode}');
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
    if (!RegExp(r'^[A-Z0-9.]{3,12}$').hasMatch(symbol) || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nhập mã 3–12 ký tự và tên doanh nghiệp.')),
      );
      return;
    }

    setState(() => _addingSymbol = true);
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        ..._authHeaders,
      };
      final createResponse = await http
          .post(
            Uri.parse('$_baseUrl/api/v1/symbols'),
            headers: headers,
            body: jsonEncode({
              'symbol': symbol,
              'name': name,
              'exchange': _exchange,
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (createResponse.statusCode != 201 &&
          createResponse.statusCode != 409) {
        throw Exception(
          'Không tạo được mã: HTTP ${createResponse.statusCode} ${createResponse.body}',
        );
      }

      final watchlistResponse = await http
          .post(
            Uri.parse('$_baseUrl/api/v1/watchlist').replace(
              queryParameters: {'symbol': symbol},
            ),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 12));
      if (watchlistResponse.statusCode != 201 &&
          watchlistResponse.statusCode != 409) {
        throw Exception(
          'Không thêm được vào watchlist: HTTP ${watchlistResponse.statusCode} ${watchlistResponse.body}',
        );
      }

      _symbolController.clear();
      _nameController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã thêm $symbol vào danh sách theo dõi. Hãy nhập OHLCV hợp pháp để phân tích.',
          ),
        ),
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
        builder: (_) => ChartPage(
          baseUrl: _baseUrl,
          symbol: symbol,
          apiToken: _accessToken ?? '',
        ),
      ),
    );
  }

  void _openTrainingRoom() {
    final token = _accessToken;
    if (token == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TrainingRoomPage(
          baseUrl: _baseUrl,
          accessToken: token,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _bootstrapSecretController.dispose();
    _symbolController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Widget _loginView(ThemeData theme) {
    final canRegister = _authStatusLoaded && !_ownerInitialized;
    return Scaffold(
      appBar: AppBar(title: const Text('SmartStock Pro • Đăng nhập')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.lock_outline, size: 52),
          const SizedBox(height: 12),
          Text(
            !_authStatusLoaded
                ? 'Kết nối backend'
                : (canRegister
                    ? 'Khởi tạo tài khoản chủ sở hữu'
                    : 'Đăng nhập chủ sở hữu'),
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'Backend URL',
              border: OutlineInputBorder(),
              helperText: 'Android Emulator: http://10.0.2.2:8000',
            ),
            keyboardType: TextInputType.url,
            onSubmitted: (_) => _loadAuthStatus(),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _authLoading ? null : _loadAuthStatus,
              icon: const Icon(Icons.refresh),
              label: const Text('Kiểm tra backend'),
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: 'Tên đăng nhập',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          if (canRegister) ...[
            TextField(
              controller: _bootstrapSecretController,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Bootstrap secret khởi tạo',
                helperText: 'Lấy trên máy chủ tin cậy bằng lệnh show_bootstrap_secret. Không gửi secret qua chat hoặc log.',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Mật khẩu',
              helperText: 'Tối thiểu 12 ký tự. Phiên chỉ lưu trong bộ nhớ ứng dụng.',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) {
              if (_authStatusLoaded) _authenticate(register: canRegister);
            },
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: (!_authStatusLoaded || _authLoading)
                  ? null
                  : () => _authenticate(register: canRegister),
              child: Text(
                _authLoading
                    ? 'Đang xử lý...'
                    : (canRegister
                        ? 'Khởi tạo chủ sở hữu'
                        : 'Đăng nhập'),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_accessToken == null) return _loginView(theme);
    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartStock Pro'),
        backgroundColor: theme.colorScheme.surfaceContainer,
        actions: [
          IconButton(tooltip: 'Đăng xuất', onPressed: _logout, icon: const Icon(Icons.logout)),
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
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Thêm mã vào danh sách',
                        style: theme.textTheme.titleMedium),
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
                      onChanged: _addingSymbol
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _exchange = value);
                              }
                            },
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed:
                            _addingSymbol ? null : _createAndAddSymbol,
                        icon: const Icon(Icons.add),
                        label: Text(
                          _addingSymbol
                              ? 'Đang thêm mã...'
                              : 'Tạo mã và thêm vào watchlist',
                        ),
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
                    'Chưa có mã trong watchlist. Hãy thêm mã sau khi kết nối backend.',
                  ),
                ),
              )
            else
              ..._watchlist.map((item) {
                final symbol = item['symbol'] as String;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(symbol.isEmpty ? '?' : symbol[0]),
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
                leading:
                    const CircleAvatar(child: Icon(Icons.school_outlined)),
                title: const Text('Hybrid AI Training Room'),
                subtitle: const Text(
                  'Tra cứu tài liệu và bằng chứng trong kho tri thức cục bộ',
                ),
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
