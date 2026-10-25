import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

typedef Json = Map<String, dynamic>;

class ApiException implements Exception {
  final String message;
  final int status;
  const ApiException(this.message, [this.status = 0]);
  @override
  String toString() => message;
}

String errorMessage(Object error) {
  if (error is ApiException) return error.message;
  return '$error';
}

abstract class TokenStore {
  Future<Json?> read();
  Future<void> write(Json pair);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  final FlutterSecureStorage storage;
  SecureTokenStore([this.storage = const FlutterSecureStorage()]);
  static const key = 'lango.credentials.v1';
  @override
  Future<Json?> read() async {
    final raw = await storage.read(key: key);
    return raw == null ? null : Map<String, dynamic>.from(jsonDecode(raw));
  }

  @override
  Future<void> write(Json pair) => storage.write(key: key, value: jsonEncode(pair));
  @override
  Future<void> clear() => storage.delete(key: key);
}

String normalizeServer(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    throw const ApiException('请输入完整服务地址，例如 https://lango.example.com（不带路径）。');
  }
  return uri.replace(path: '').toString().replaceFirst(RegExp(r'/$'), '');
}

bool isCleartextUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri != null && uri.scheme == 'http';
}

class ApiClient {
  final http.Client client;
  final TokenStore store;
  String server = '';
  Json? tokens;
  int generation = 0;
  Future<void>? _refreshing;
  VoidCallback? onUnauthorized;

  ApiClient({http.Client? client, TokenStore? store})
      : client = client ?? http.Client(),
        store = store ?? SecureTokenStore();

  Future<void> restore(String url) async {
    server = url;
    final saved = await store.read();
    if (saved?['server'] == url) {
      tokens = saved;
    } else {
      await store.clear();
    }
  }

  Future<void> clear() async {
    generation++;
    tokens = null;
    _refreshing = null;
    await store.clear();
  }

  Future<void> authenticate(bool register, Json body) async {
    final epoch = generation;
    final pair = await request('POST', register ? '/auth/register' : '/auth/login',
        body: body, auth: false);
    if (epoch != generation) throw const ApiException('连接已改变，请重新登录。');
    tokens = Map<String, dynamic>.from(pair)..['server'] = server;
    await store.write(tokens!);
  }

  Future<void> refresh() {
    if (_refreshing != null) return _refreshing!;
    final job = _rotate();
    _refreshing = job;
    job.whenComplete(() {
      if (identical(_refreshing, job)) _refreshing = null;
    }).ignore();
    return job;
  }

  Future<void> _rotate() async {
    final epoch = generation;
    final refreshToken = tokens?['refresh_token'];
    if (refreshToken == null) throw const ApiException('请先登录。', 401);
    try {
      final pair = await request('POST', '/auth/refresh',
          body: {'refresh_token': refreshToken}, auth: false);
      if (epoch != generation) throw const ApiException('账户已切换。');
      tokens = Map<String, dynamic>.from(pair)..['server'] = server;
      await store.write(tokens!);
    } on ApiException catch (e) {
      if (epoch == generation && [400, 401, 403].contains(e.status)) {
        await clear();
        onUnauthorized?.call();
      }
      rethrow;
    }
  }

  Future<dynamic> request(String method, String path,
      {Json? body, bool auth = true, bool retry = true}) async {
    final epoch = generation;
    final usedToken = tokens?['access_token'];
    if (auth && usedToken == null) {
      throw const ApiException('登录已过期，请重新登录。', 401);
    }
    final req = http.Request(method, Uri.parse('$server/api/v1$path'));
    req.headers['Content-Type'] = 'application/json';
    if (auth) req.headers['Authorization'] = 'Bearer $usedToken';
    if (body != null) req.body = jsonEncode(body);
    http.Response response;
    try {
      response = await http.Response.fromStream(
        await client.send(req).timeout(const Duration(seconds: 20)),
      ).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const ApiException('连接超时。请检查网络和服务地址后重试。');
    } catch (_) {
      throw const ApiException('无法连接服务。请检查网络、HTTPS 证书与服务地址。');
    }
    if (epoch != generation) throw const ApiException('账户或服务已改变，已丢弃旧请求。');
    if (response.statusCode == 401 && auth && retry) {
      if (usedToken == tokens?['access_token']) await refresh();
      return request(method, path, body: body, auth: true, retry: false);
    }
    dynamic decoded;
    try {
      decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    } catch (_) {
      throw const ApiException('服务返回了无效数据，请检查服务版本。');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401 && auth) {
        await clear();
        onUnauthorized?.call();
      }
      final detail = decoded is Map ? decoded['detail'] : null;
      throw ApiException(
        detail is String ? detail : '请求失败（${response.statusCode}），请重试。',
        response.statusCode,
      );
    }
    return decoded;
  }
}

class AppState extends ChangeNotifier {
  final ApiClient api;
  SharedPreferences? preferences;
  bool booting = true;
  bool loading = false;
  String? error;
  Json? profile;
  Json config = {};
  Json usage = {};
  List<Json> scenarios = [];
  List<Json> sessions = [];
  List<Json> memories = [];
  bool memoryEnabled = true;
  String theme = 'system';
  bool reduceMotion = false;
  String? engine;
  int accountEpoch = 0;

  AppState({ApiClient? api}) : api = api ?? ApiClient() {
    this.api.onUnauthorized = () {
      clearAccount();
      error = '登录已过期，请重新登录。';
      notifyListeners();
    };
  }

  bool get signedIn => profile != null;
  bool get hasStoredSession => api.tokens != null;
  bool get isAdmin => profile?['is_admin'] == true;
  String get server => api.server;
  bool get serverUsesCleartext => isCleartextUrl(api.server);
  List<Json> get voices => (config['voices'] as List? ?? []).map((e) => Json.from(e)).toList();
  List<Json> get engines => (config['engines'] as List? ?? []).map((e) => Json.from(e)).toList();
  String get displayName =>
      (profile?['display_name'] as String?)?.trim().isNotEmpty == true
          ? profile!['display_name'] as String
          : '同学';
  String get currentEngine => engine ?? (config['default_engine'] as String?) ?? '';
  bool get onboardingCompleted => profile?['onboarding_completed'] == true;

  int get todaySeconds => (usage['today_seconds'] as num?)?.toInt() ?? 0;
  int get dailyLimitSeconds => (usage['daily_limit_seconds'] as num?)?.toInt() ?? 0;
  int get memoryCount => memories.length;

  Future<void> initialize() async {
    try {
      preferences = await SharedPreferences.getInstance();
      theme = preferences!.getString('theme') ?? 'system';
      reduceMotion = preferences!.getBool('reduce_motion') ?? false;
      engine = preferences!.getString('engine');
      final server = preferences!.getString('server') ?? '';
      if (server.isNotEmpty) {
        await api.restore(server);
        if (api.tokens != null) await load();
      }
    } catch (e) {
      error = errorMessage(e);
    }
    booting = false;
    notifyListeners();
  }

  void clearAccount() {
    accountEpoch++;
    profile = null;
    config = {};
    usage = {};
    scenarios = [];
    sessions = [];
    memories = [];
    memoryEnabled = true;
    loading = false;
    error = null;
  }

  Future<void> _checkHealth(String url) async {
    final client = http.Client();
    try {
      final response = await client
          .get(Uri.parse('$url/healthz'))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw const ApiException('服务有响应，但健康检查未通过。请确认是 Lango 服务地址。');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['status'] != 'ok') {
        throw const ApiException('该地址不是可用的 Lango 服务。');
      }
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('连接超时。请确认服务已启动且网络可访问。');
    } catch (_) {
      throw const ApiException('无法连接该地址。请检查网络、HTTPS 证书与端口。');
    } finally {
      client.close();
    }
  }

  Future<void> connectToServer(String value, {bool skipHealth = false}) async {
    final url = normalizeServer(value);
    error = null;
    if (!skipHealth) await _checkHealth(url);
    if (url == api.server && api.tokens != null) {
      await load();
      return;
    }
    if (api.server.isNotEmpty && url != api.server) {
      await logout();
    }
    api.server = url;
    await api.clear();
    await preferences?.setString('server', url);
    notifyListeners();
  }

  Future<void> changeServer(String value, {bool skipHealth = false}) async {
    final url = normalizeServer(value);
    if (!skipHealth) await _checkHealth(url);
    await logout();
    api.server = url;
    await api.clear();
    await preferences?.setString('server', url);
    notifyListeners();
  }

  Future<void> login(bool register, Json values) async {
    error = null;
    await api.authenticate(register, values);
    await load();
  }

  Future<void> load() async {
    final epoch = accountEpoch;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final me = await api.request('GET', '/me');
      if (epoch != accountEpoch) return;
      profile = Json.from(me);
      final result = await Future.wait([
        api.request('GET', '/config'),
        api.request('GET', '/scenarios'),
        api.request('GET', '/sessions'),
        api.request('GET', '/memories'),
        api.request('GET', '/usage'),
      ]);
      if (epoch != accountEpoch) return;
      config = Json.from(result[0]);
      scenarios = (result[1] as List).map((e) => Json.from(e)).toList();
      sessions = (result[2] as List).map((e) => Json.from(e)).toList();
      final memoriesPayload = Json.from(result[3]);
      memories = (memoriesPayload['items'] as List? ?? []).map((e) => Json.from(e)).toList();
      memoryEnabled = memoriesPayload['enabled'] as bool? ?? true;
      usage = Json.from(result[4]);
      final availableEngines = engines.map((e) => e['id']).toList();
      if (!availableEngines.contains(engine)) engine = config['default_engine'] as String?;
    } catch (e) {
      if (epoch == accountEpoch) error = errorMessage(e);
    } finally {
      if (epoch == accountEpoch) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshUsage() async {
    try {
      final value = await api.request('GET', '/usage');
      usage = Json.from(value);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> updateProfile(Json changes) async {
    final epoch = accountEpoch;
    final value = await api.request('PATCH', '/me', body: changes);
    if (epoch != accountEpoch) return;
    profile = Json.from(value);
    if (profile!.containsKey('memory_enabled')) {
      memoryEnabled = profile!['memory_enabled'] as bool? ?? memoryEnabled;
    }
    notifyListeners();
  }

  Future<Json> session(String id) async {
    final value = await api.request('GET', '/sessions/${Uri.encodeComponent(id)}');
    return Json.from(value);
  }

  Future<void> forget([String? id]) async {
    final epoch = accountEpoch;
    await api.request('DELETE', id == null ? '/memories' : '/memories/${Uri.encodeComponent(id)}');
    if (epoch != accountEpoch) return;
    if (id == null) {
      memories.clear();
    } else {
      memories.removeWhere((m) => m['id'] == id);
    }
    notifyListeners();
  }

  Future<void> setMemoryEnabled(bool enabled) async {
    memoryEnabled = enabled;
    notifyListeners();
    try {
      await updateProfile({'memory_enabled': enabled});
    } catch (e) {
      memoryEnabled = !enabled;
      notifyListeners();
      rethrow;
    }
  }

  Future<Json> issueInvite(int maxUses) async {
    final value = await api.request('POST', '/admin/invites', body: {'max_uses': maxUses});
    return Json.from(value);
  }

  Future<void> setAppearance({String? theme, bool? motion, String? engine}) async {
    if (theme != null) {
      this.theme = theme;
      await preferences?.setString('theme', theme);
    }
    if (motion != null) {
      reduceMotion = motion;
      await preferences?.setBool('reduce_motion', motion);
    }
    if (engine != null) {
      this.engine = engine;
      await preferences?.setString('engine', engine);
    }
    notifyListeners();
  }

  void clearError() {
    if (error == null) return;
    error = null;
    notifyListeners();
  }

  Future<void> reloadAfterSession() async {
    await load();
  }

  Future<void> logout() async {
    final refreshToken = api.tokens?['refresh_token'];
    final oldServer = api.server;
    clearAccount();
    await api.clear();
    notifyListeners();
    if (refreshToken != null && oldServer.isNotEmpty) {
      try {
        final request = http.Request('POST', Uri.parse('$oldServer/api/v1/auth/logout'));
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode({'refresh_token': refreshToken});
        await api.client.send(request).timeout(const Duration(seconds: 5));
      } catch (_) {
        // Local credentials are already removed, even offline.
      }
    }
  }
}
