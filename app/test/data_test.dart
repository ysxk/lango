import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lango/data.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryTokenStore implements TokenStore {
  Json? value;
  @override
  Future<Json?> read() async => value;
  @override
  Future<void> write(Json pair) async => value = Json.from(pair);
  @override
  Future<void> clear() async => value = null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const server = 'https://lango.example.com';
  const pair = {'access_token': 'old-access', 'refresh_token': 'old-refresh'};

  test('Server address accepts HTTPS and explicit LAN HTTP', () {
    expect(normalizeServer(' $server/ '), server);
    expect(
      normalizeServer('http://192.168.1.20:8000'),
      'http://192.168.1.20:8000',
    );
    expect(isCleartextUrl(server), isFalse);
    expect(isCleartextUrl('http://127.0.0.1:8000'), isTrue);
  });

  test('Server address rejects credentials, paths, query and fragments', () {
    for (final url in [
      '',
      'lango.example.com',
      'ftp://host',
      'https://user:secret@host',
      '$server/api/v1',
      '$server?key=value',
      '$server#part',
    ]) {
      expect(() => normalizeServer(url), throwsA(isA<ApiException>()));
    }
  });

  test('Credentials are never restored for another server', () async {
    final store = MemoryTokenStore()..value = {...pair, 'server': server};
    final api = ApiClient(store: store);
    addTearDown(api.client.close);
    await api.restore('https://another.example.com');
    expect(api.tokens, isNull);
    expect(store.value, isNull);
  });

  test('Concurrent expired requests share one token rotation', () async {
    var rotations = 0;
    final store = MemoryTokenStore();
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/refresh')) {
        rotations++;
        expect(jsonDecode(request.body)['refresh_token'], 'old-refresh');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return http.Response(
          jsonEncode({
            'access_token': 'new-access',
            'refresh_token': 'new-refresh',
          }),
          200,
        );
      }
      if (request.headers['Authorization'] == 'Bearer old-access') {
        return http.Response('{"detail":"expired"}', 401);
      }
      expect(request.headers['Authorization'], 'Bearer new-access');
      return http.Response('{"ok":true}', 200);
    });
    final api = ApiClient(client: client, store: store)
      ..server = server
      ..tokens = {...pair};
    final results = await Future.wait([
      api.request('GET', '/me'),
      api.request('GET', '/config'),
    ]);
    expect(rotations, 1);
    expect(results.every((result) => result['ok'] == true), isTrue);
    expect(store.value?['refresh_token'], 'new-refresh');
    expect(store.value?['server'], server);
  });

  test('Rejected refresh removes credentials and signals logout', () async {
    final store = MemoryTokenStore()..value = {...pair};
    final api =
        ApiClient(
            store: store,
            client: MockClient(
              (_) async => http.Response('{"detail":"expired"}', 401),
            ),
          )
          ..server = server
          ..tokens = {...pair};
    var unauthorized = 0;
    api.onUnauthorized = () => unauthorized++;
    await expectLater(api.request('GET', '/me'), throwsA(isA<ApiException>()));
    expect(api.tokens, isNull);
    expect(store.value, isNull);
    expect(unauthorized, 1);
  });

  test(
    'An in-flight login cannot restore credentials after account change',
    () async {
      final reply = Completer<http.Response>();
      final store = MemoryTokenStore();
      final api = ApiClient(
        store: store,
        client: MockClient((_) => reply.future),
      )..server = server;
      final login = api.authenticate(false, {
        'email': 'test@example.com',
        'password': 'test-password',
      });
      final rejected = expectLater(login, throwsA(isA<ApiException>()));
      await api.clear();
      reply.complete(http.Response(jsonEncode(pair), 200));
      await rejected;
      expect(api.tokens, isNull);
      expect(store.value, isNull);
    },
  );

  test('Changing server clears all account-scoped data', () async {
    SharedPreferences.setMockInitialValues({});
    final store = MemoryTokenStore()..value = {...pair};
    final api =
        ApiClient(
            store: store,
            client: MockClient((request) async {
              expect(request.url.toString(), '$server/api/v1/auth/logout');
              return http.Response('{"ok":true}', 200);
            }),
          )
          ..server = server
          ..tokens = {...pair};
    final state = AppState(api: api)
      ..preferences = await SharedPreferences.getInstance()
      ..profile = {'display_name': 'Old account'}
      ..memories = [
        {'id': 'old-memory'},
      ]
      ..sessions = [
        {'id': 'old-session'},
      ]
      ..config = {'voices': []};
    addTearDown(state.dispose);
    await state.changeServer('https://new.example.com', skipHealth: true);
    expect(state.server, 'https://new.example.com');
    expect(state.profile, isNull);
    expect(state.memories, isEmpty);
    expect(state.sessions, isEmpty);
    expect(state.config, isEmpty);
    expect(api.tokens, isNull);
    expect(store.value, isNull);
    expect(state.preferences!.getString('server'), state.server);
  });

  test('Pausing memory preserves visible facts', () async {
    final api =
        ApiClient(
            store: MemoryTokenStore(),
            client: MockClient((request) async {
              expect(request.method, 'PATCH');
              expect(jsonDecode(request.body), {'memory_enabled': false});
              return http.Response('{"memory_enabled":false}', 200);
            }),
          )
          ..server = server
          ..tokens = {...pair};
    final state = AppState(api: api)
      ..memories = [
        {'id': 'retained', 'memory': 'A saved fact'},
      ];
    addTearDown(state.dispose);
    await state.setMemoryEnabled(false);
    expect(state.memoryEnabled, isFalse);
    expect(state.memories.single['id'], 'retained');
  });
}
