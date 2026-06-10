import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

const _firebaseSignIn =
    'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword';
const _firebaseSignUp =
    'https://identitytoolkit.googleapis.com/v1/accounts:signUp';

int _passes = 0;
int _fails = 0;

void main(List<String> args) async {
  final env = Platform.environment;
  
  // Try reading from gitignored .env or env vars
  final apiKey = env['FIREBASE_API_KEY'] ?? 'AIzaSyAtJLCMoEtw3lFUNa4agcuaKA9kSkXOuaA';
  final email = env['TEST_EMAIL'] ?? 'smoketest@dartstream.test';
  final password = env['TEST_PASSWORD'] ?? 'smoke123';

  final authHost = env['API_AUTH'] ?? 'https://dev-apiauth.dartstream.io';
  final platformHost = env['API_PLATFORM'] ?? 'https://dev-apiplatform.dartstream.io';
  final experienceHost = env['API_EXPERIENCE'] ?? 'https://dev-apiexperience.dartstream.io';
  final reactiveHost = env['API_REACTIVE'] ?? 'https://dev-apireactive.dartstream.io';
  final persistenceHost = env['API_PERSISTENCE'] ?? 'https://dev-apipersistence.dartstream.io';

  print('== FocusStream E2E smoke ==');
  print('  auth        : $authHost');
  print('  platform    : $platformHost');
  print('  experience  : $experienceHost');
  print('  reactive    : $reactiveHost');
  print('  persistence : $persistenceHost');
  print('  user        : $email');
  print('');

  final idToken = await _firebaseAuth(apiKey, email, password);
  if (idToken == null) {
    _summary();
    exit(1);
  }

  String? userId;
  String? tenantId;
  await _step('POST /api/v1/auth/signup', () async {
    return http.post(
      Uri.parse('$authHost/api/v1/auth/signup'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'idToken': idToken}),
    );
  }, allowStatuses: const [200, 201, 409], onBody: (body) {
    final ids = _extractIds(body);
    userId = ids.$1;
    tenantId = ids.$2;
    print('   extracted userId=$userId tenantId=$tenantId');
  });

  if (userId == null || tenantId == null) {
    print('   [FAIL] Could not extract userId/tenantId; aborting downstream calls.');
    _fails++;
    _summary();
    exit(1);
  }

  final authHeaders = {
    'authorization': 'Bearer $idToken',
    'x-tenant-id': tenantId!,
    'x-user-id': userId!,
  };

  await _step('GET  /api/v1/auth/me', () async {
    return http.get(
      Uri.parse('$authHost/api/v1/auth/me'),
      headers: authHeaders,
    );
  });

  await _step('GET  /api/v1/platform/feature-flags', () async {
    return http.get(
      Uri.parse('$platformHost/api/v1/platform/feature-flags'),
      headers: authHeaders,
    );
  });

  final expQuery = 'userId=${Uri.encodeQueryComponent(userId!)}'
      '&tenantId=${Uri.encodeQueryComponent(tenantId!)}'
      '&projectId=focusstream&environmentId=production';

  await _step('GET  /api/v1/experience/profiles/me', () async {
    return http.get(
      Uri.parse('$experienceHost/api/v1/experience/profiles/me?$expQuery'),
      headers: authHeaders,
    );
  });

  await _step('POST /api/v1/experience/cloud-save/snapshot', () async {
    return http.post(
      Uri.parse(
        '$experienceHost/api/v1/experience/cloud-save/snapshot?$expQuery&slotKey=focusstream',
      ),
      headers: {
        ...authHeaders,
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'payload': {
          'tasks': [],
          'completedCount': 5,
          'focusSessions': 10,
          'lifetimeFocusMinutes': 250,
          'themeName': 'Default Blue',
        },
      }),
    );
  }, allowStatuses: const [200, 201]);

  await _step('GET  /api/v1/experience/cloud-save/snapshot', () async {
    return http.get(
      Uri.parse(
        '$experienceHost/api/v1/experience/cloud-save/snapshot?$expQuery&slotKey=focusstream',
      ),
      headers: authHeaders,
    );
  });

  await _step('GET  /api/v1/experience/inventory/items', () async {
    return http.get(
      Uri.parse(
        '$experienceHost/api/v1/experience/inventory/items?$expQuery',
      ),
      headers: authHeaders,
    );
  });

  await _step('POST /api/v1/reactive/events/log', () async {
    return http.post(
      Uri.parse('$reactiveHost/api/v1/reactive/events/log'),
      headers: {
        ...authHeaders,
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'event_type': 'focus.session.completed',
        'payload': {'duration_minutes': 25, 'source': 'e2e-smoke'},
      }),
    );
  }, allowStatuses: const [200, 201]);

  await _step('GET  /api/v1/reactive/streaming/channels', () async {
    return http.get(
      Uri.parse('$reactiveHost/api/v1/reactive/streaming/channels'),
      headers: authHeaders,
    );
  });

  await _step('GET  /api/v1/persistence/database', () async {
    return http.get(
      Uri.parse('$persistenceHost/api/v1/persistence/database/'),
      headers: authHeaders,
    );
  });

  _summary();
  exit(_fails == 0 ? 0 : 1);
}

(String?, String?) _extractIds(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return (null, null);
    final user = (decoded['data'] is Map ? decoded['data']['user'] : null) ??
        decoded['user'] ??
        decoded;
    String? pick(Map m, List<String> keys) {
      for (final k in keys) {
        final v = m[k];
        if (v is String && v.isNotEmpty) return v;
      }
      return null;
    }
    final uid = user is Map
        ? pick(user, ['id', 'user_id', 'userId', 'uid'])
        : null;
    String? tid;
    if (user is Map) {
      tid = pick(user, ['tenant_id', 'tenantId', 'active_tenant_id', 'activeTenantId']);
    }
    tid ??= decoded['active_tenant_id'] as String? ??
        decoded['activeTenantId'] as String? ??
        decoded['tenant_id'] as String? ??
        decoded['tenantId'] as String?;
    return (uid, tid);
  } catch (_) {
    return (null, null);
  }
}

Future<String?> _firebaseAuth(
  String apiKey,
  String email,
  String password,
) async {
  print('-- Firebase sign-in --');
  final body = jsonEncode({
    'email': email,
    'password': password,
    'returnSecureToken': true,
  });

  final signInResp = await http.post(
    Uri.parse('$_firebaseSignIn?key=$apiKey'),
    headers: const {'content-type': 'application/json'},
    body: body,
  );

  if (signInResp.statusCode == 200) {
    final token = (jsonDecode(signInResp.body) as Map)['idToken'] as String?;
    if (token != null) {
      print('   [PASS] Firebase signInWithPassword -> got idToken');
      return token;
    }
  }

  print('   signIn failed — trying signUp');

  final signUpResp = await http.post(
    Uri.parse('$_firebaseSignUp?key=$apiKey'),
    headers: const {'content-type': 'application/json'},
    body: body,
  );
  if (signUpResp.statusCode == 200) {
    final token = (jsonDecode(signUpResp.body) as Map)['idToken'] as String?;
    if (token != null) {
      print('   [PASS] Firebase signUp -> got idToken');
      return token;
    }
  }

  print('   [FAIL] Firebase auth failed.');
  return null;
}

Future<void> _step(
  String label,
  Future<http.Response> Function() send, {
  List<int> allowStatuses = const [200, 201, 204],
  void Function(String body)? onBody,
}) async {
  print('-- $label --');
  try {
    final stopwatch = Stopwatch()..start();
    final resp = await send().timeout(const Duration(seconds: 15));
    stopwatch.stop();
    final excerpt = _excerpt(resp.body);
    if (allowStatuses.contains(resp.statusCode)) {
      _passes++;
      print('   [PASS] $label -> ${resp.statusCode} in ${stopwatch.elapsedMilliseconds}ms');
      if (excerpt.isNotEmpty) print('   body: $excerpt');
      onBody?.call(resp.body);
    } else {
      _fails++;
      print('   [FAIL] $label -> ${resp.statusCode}');
      if (excerpt.isNotEmpty) print('   body: $excerpt');
    }
  } on TimeoutException {
    _fails++;
    print('   [FAIL] $label -> TIMEOUT');
  } catch (e) {
    _fails++;
    print('   [FAIL] $label -> exception: $e');
  }
}

String _excerpt(String body) {
  final trimmed = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (trimmed.isEmpty) return '';
  return trimmed.length > 180 ? '${trimmed.substring(0, 180)}...' : trimmed;
}

void _summary() {
  print('');
  print('== Summary: $_passes pass, $_fails fail ==');
}
