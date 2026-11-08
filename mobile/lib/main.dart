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
  const DashboardPage({
    super.key,
    this.httpClient,
    this.chartPageBuilder,
    this.trainingRoomPageBuilder,
  });

  /// Injectable transport and route builders keep auth/session behavior testable.
  /// Production uses the default HTTP client and real feature pages.
  final http.Client? httpClient;
  final Widget Function(String baseUrl, String symbol, String apiToken,
      SessionExpiredCallback onSessionExpired)? chartPageBuilder;
  final Widget Function(String baseUrl, String apiToken,
      SessionExpiredCallback onSessionExpired)? trainingRoomPageBuilder;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final http.Client _httpClient = widget.httpClient ?? http.Client();
  bool get _ownsHttpClient => widget.httpClient == null;
  final TextEditingController _urlController =
      TextEditingController(text: 'http://10.0.2.2:8000');
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _bootstrapSecretController = TextEditingController();
  String? _accessToken;
  bool _sessionExpired = false;
  bool _ownerInitialized = true;
  bool _authStatusLoaded = false;
  bool _authLoading = false;
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

  Map<String, String> get _authHeaders => apiAuthHeaders(_accessToken ?? '');

  void _expireSession(String token) {
    if (!mounted || token.isEmpty || token != _accessToken || _sessionExpired) return;
    _sessionExpired = true;
    setState(() {
      _accessToken = null;
      _health = null;
      _watchlist = [];
      _error = null;
      _loading = false;
      _addingSymbol = false;
    });
    Navigator.of(context).popUntil((route) => route.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(
        'Phiên đăng nhập đã hết hạn hoặc bị thu hồi. Vui lòng đăng nhập lại.',
      )),
    );
  }

  bool _handleProtectedStatus(int statusCode, String token) {
    if (statusCode != 401) return false;
    _expireSession(token);
    return true;
  }

  @override
  void initState() { super.initState(); _loadAuthStatus(); }

  Future<void> _loadAuthStatus() async {
    setState(() { _authStatusLoaded = false; _error = null; });
    try {
      final response = await _httpClient.get(Uri.parse('$_baseUrl/api/v1/auth/status')).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) throw Exception('Backend trả về HTTP ${response.statusCode}');
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() { _ownerInitialized = payload['owner_initialized'] == true; _authStatusLoaded = true; });
    } catch (error) {
      if (!mounted) return;
      setState(() { _authStatusLoaded = true; _error = 'Không kiểm tra được backend: $error'; });
    }
  }

  Future<void> _authenticate({required bool register}) async {
    if (_authLoading) return;
    setState(() { _authLoading = true; _error = null; });
    try {
      final username = _usernameController.text.trim();
      final password = _passwordController.text;
      if (username.isEmpty || password.isEmpty) throw Exception('Nhập tên đăng nhập và mật khẩu.');
      final secret = _bootstrapSecretController.text.trim();
      if (register && password.length < 12) throw Exception('Mật khẩu cần tối thiểu 12 ký tự.');
      if (register && (secret.length < 32 || secret.length > 256)) throw Exception('Bootstrap secret cần từ 32 đến 256 ký tự.');
      if (register) {
        final setup = await _httpClient.post(Uri.parse('$_baseUrl/api/v1/auth/register-first-owner'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'username': username, 'password': password, 'bootstrap_secret': secret})).timeout(const Duration(seconds: 15));
        if (setup.statusCode != 201) {
          if (setup.statusCode == 403) {
            throw Exception('Bootstrap secret không đúng hoặc đã được sử dụng.');
          }
          if (setup.statusCode == 409) {
            _bootstrapSecretController.clear();
            if (mounted) setState(() => _ownerInitialized = true);
            throw Exception(
              'Tài khoản chủ sở hữu đã được khởi tạo. Hãy đăng nhập hoặc kiểm tra trạng thái backend.',
            );
          }
          if (setup.statusCode == 422) {
            throw Exception('Thông tin khởi tạo chưa hợp lệ.');
          }
          throw Exception('Không khởi tạo được tài khoản (HTTP ${setup.statusCode}).');
        }
        _bootstrapSecretController.clear();
      }
      final response = await _httpClient.post(Uri.parse('$_baseUrl/api/v1/auth/login'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'username': username, 'password': password})).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw Exception('Đăng nhập thất bại (HTTP ${response.statusCode}).');
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final token = payload['access_token']?.toString();
      if (token == null || token.isEmpty) throw Exception('Backend không trả access token hợp lệ.');
      if (!mounted) return;
      setState(() { _accessToken = token; _sessionExpired = false; _ownerInitialized = true; });
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
    if (token != null) { try { await _httpClient.post(Uri.parse('$_baseUrl/api/v1/auth/logout'), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 8)); } catch (_) { /* Clear local session even if logout request fails. */ } }
    if (!mounted) return;
    setState(() { _accessToken = null; _health = null; _watchlist = []; });
  }

  Future<void> _connect() async {
    final token = _accessToken;
    if (token == null || token.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final healthResponse = await _httpClient
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 8));
      if (healthResponse.statusCode != 200) {
        throw Exception('API trả về HTTP ${healthResponse.statusCode}');
      }

      final watchlistResponse = await _httpClient
          .get(
            Uri.parse('$_baseUrl/api/v1/watchlist'),
            headers: _authHeaders
          )
          .timeout(const Duration(seconds: 8));
      if (_handleProtectedStatus(watchlistResponse.statusCode, token)) return;
      if (watchlistResponse.statusCode != 200) {
        throw ApiRequestException(watchlistResponse.statusCode);
      }

      final health = jsonDecode(healthResponse.body) as Map<String, dynamic>;
      final payload = jsonDecode(watchlistResponse.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _health = health;
        _watchlist = payload['items'] as List<dynamic>? ?? [];
      });
    } catch (error) {
      if (!mounted || token != _accessToken) return;
      setState(() {
        _health = null;
        _error = 'Không kết nối được backend: ${safeApiErrorMessage(error, fallback: 'Đã xảy ra lỗi khi tải dữ liệu.')}';
      });
    } finally {
      if (mounted && token == _accessToken) setState(() => _loading = false);
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

    final token = _accessToken;
    if (token == null || token.isEmpty) return;
    setState(() => _addingSymbol = true);
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        ...apiAuthHeaders(token)
      };
      final createResponse = await _httpClient
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
      if (_handleProtectedStatus(createResponse.statusCode, token)) return;
      if (createResponse.statusCode != 201 &&
          createResponse.statusCode != 409) {
        throw ApiRequestException(createResponse.statusCode);
      }

      final watchlistResponse = await _httpClient
          .post(
            Uri.parse('$_baseUrl/api/v1/watchlist').replace(
              queryParameters: {'symbol': symbol},
            ),
            headers: apiAuthHeaders(token)
          )
          .timeout(const Duration(seconds: 12));
      if (_handleProtectedStatus(watchlistResponse.statusCode, token)) return;
      if (watchlistResponse.statusCode != 201 &&
          watchlistResponse.statusCode != 409) {
        throw ApiRequestException(watchlistResponse.statusCode);
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
      if (mounted && token == _accessToken) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thêm được mã: ${safeApiErrorMessage(error, fallback: 'Đã xảy ra lỗi khi thêm mã.')}')),
        );
      }
    } finally {
      if (mounted && token == _accessToken) setState(() => _addingSymbol = false);
    }
  }

  void _openChart(String symbol) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => widget.chartPageBuilder?.call(
          _baseUrl, symbol, _accessToken ?? '', _expireSession,
        ) ?? ChartPage(
          baseUrl: _baseUrl,
          symbol: symbol,
          apiToken: _accessToken ?? '',
          onSessionExpired: _expireSession,
        ),
      ),
    );
  }

  void _openTrainingRoom() {
    final token = _accessToken;
    if (token == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => widget.trainingRoomPageBuilder?.call(
            _baseUrl, token, _expireSession) ??
          TrainingRoomPage(
            baseUrl: _baseUrl, apiToken: token,
            onSessionExpired: _expireSession,
          ),
    ));
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _bootstrapSecretController.dispose();
    _symbolController.dispose();
    _nameController.dispose();
    if (_ownsHttpClient) _httpClient.close();
    super.dispose();
  }

  Widget _loginView(ThemeData theme) {
    final canRegister = _authStatusLoaded && !_ownerInitialized;
    return Scaffold(appBar: AppBar(title: const Text('SmartStock Pro • Đăng nhập')), body: ListView(padding: const EdgeInsets.all(20), children: [
      const Icon(Icons.lock_outline, size: 52),
      Text(!_authStatusLoaded ? 'Kết nối backend' : (canRegister ? 'Khởi tạo tài khoản chủ sở hữu' : 'Đăng nhập chủ sở hữu'), style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
      TextField(key: const ValueKey('backend-url'), controller: _urlController, decoration: const InputDecoration(labelText: 'Backend URL', border: OutlineInputBorder()), keyboardType: TextInputType.url, onSubmitted: (_) => _loadAuthStatus()),
      TextButton.icon(onPressed: _authLoading ? null : _loadAuthStatus, icon: const Icon(Icons.refresh), label: const Text('Kiểm tra backend')),
      TextField(key: const ValueKey('username'), controller: _usernameController, decoration: const InputDecoration(labelText: 'Tên đăng nhập', border: OutlineInputBorder())),
      if (canRegister) TextField(key: const ValueKey('bootstrap-secret'), controller: _bootstrapSecretController, obscureText: true, enableSuggestions: false, autocorrect: false, decoration: const InputDecoration(labelText: 'Bootstrap secret khởi tạo', helperText: 'Lấy trên máy chủ tin cậy bằng lệnh show_bootstrap_secret. Không gửi secret qua chat hoặc log.', border: OutlineInputBorder())),
      TextField(key: const ValueKey('password'), controller: _passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Mật khẩu', helperText: 'Tối thiểu 12 ký tự. Phiên chỉ lưu trong bộ nhớ ứng dụng.')),
      FilledButton(key: const ValueKey('auth-submit'), onPressed: (!_authStatusLoaded || _authLoading) ? null : () => _authenticate(register: canRegister), child: Text(_authLoading ? 'Đang xử lý...' : (canRegister ? 'Khởi tạo chủ sở hữu' : 'Đăng nhập'))),
      if (_error != null) Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_accessToken == null) return _loginView(theme);
    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartStock Pro'),
        backgroundColor: theme.colorScheme.surfaceContainer,
        actions: [IconButton(key: const ValueKey('logout'), tooltip: 'Đăng xuất', onPressed: _logout, icon: const Icon(Icons.logout))],
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
